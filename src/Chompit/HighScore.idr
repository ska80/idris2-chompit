module Chompit.HighScore

import Data.List
import Data.List1
import Data.Maybe
import Data.String

import System
import System.Directory
import System.File
import System.FFI

%default covering

-- These C file operations use the same FILE pointers as System.File.
-- Exclusive creation prevents a stale file or symlink from being overwritten.
%foreign "C:fopen,libc 6"
prim__exclusiveOpen : String -> String -> PrimIO FilePtr

%foreign "C:fflush,libc 6"
prim__flush : FilePtr -> PrimIO Int

%foreign "C:rename,libc 6"
prim__replace : String -> String -> PrimIO Int

%foreign "C:fgetc,libc 6"
prim__readByte : FilePtr -> PrimIO Int

export
parseHighScore : String -> Maybe Int
parseHighScore text =
  let digits = trim text
   in if length text > 64 || null digits ||
         not (all (\c => c >= '0' && c <= '9') (unpack digits)) then Nothing else do
      value <- parsePositive {a = Integer} digits
      let score : Int = cast value
      if score >= 0 && cast {to = Integer} score == value then Just score else Nothing

-- The XDG specification requires absolute state paths. Ignore relative values.
export
defaultScorePath : Maybe String -> Maybe String -> Maybe String
defaultScorePath stateHome home = case usable stateHome of
  Just root => Just (root ++ "/chompit/high-score")
  Nothing => map (++ "/.local/state/chompit/high-score") (usable home)
  where
    usable : Maybe String -> Maybe String
    usable Nothing = Nothing
    usable (Just path) = if isPrefixOf "/" path && not (elem '\0' (unpack path))
      then Just (pack (reverse (dropWhile (== '/') (reverse (unpack path))))) else Nothing

export
parentDirectories : String -> List String
parentDirectories path =
  let parts = filter (/= "") (forget (split (== '/') path))
   in prefixes (if isPrefixOf "/" path then "/" else "") (reverse (drop 1 (reverse parts)))
  where
    prefixes : String -> List String -> List String
    prefixes _ [] = []
    prefixes parent (part :: rest) =
      let path = parent ++ (if parent == "" || parent == "/" then "" else "/") ++ part
       in path :: prefixes path rest

-- Read at most 65 bytes. Reject oversized files, non-ASCII data, and embedded
-- NULs instead of passing arbitrary file contents through a UTF-8 decoder.
readBytes : Nat -> File -> List Char -> IO (Either FileError String)
readBytes Z _ bytes = pure (Right (pack (reverse bytes)))
readBytes (S fuel) file@(FHandle pointer) bytes = do
  value <- primIO (prim__readByte pointer)
  case value < 0 of
    True => do
      failed <- fileError file
      if failed then returnError else pure (Right (pack (reverse bytes)))
    False => readBytes fuel file (cast value :: bytes)

export
readHighScore : String -> IO (Either String Int)
readHighScore path = do
  Right file <- openFile path Read
    | Left FileNotFound => pure (Right 0)
    | Left err => pure (Left ("Cannot read high score at " ++ path ++ ": " ++ show err))
  result <- readBytes 65 file []
  closeFile file
  pure $ case result of
    Left err => Left ("Cannot read high score at " ++ path ++ ": " ++ show err)
    Right text => Right (fromMaybe 0 (parseHighScore text))

ensureDirectories : List String -> IO (Either String ())
ensureDirectories [] = pure (Right ())
ensureDirectories (path :: rest) = do
  result <- createDir path
  case result of
    Right () => ensureDirectories rest
    Left err => do
      Right directory <- openDir path
        | Left _ => pure (Left ("Cannot create score directory " ++ path ++ ": " ++ show err))
      closeDir directory
      ensureDirectories rest

writeTemporary : String -> Int -> IO (Either String ())
writeTemporary path score = do
  pointer <- primIO (prim__exclusiveOpen path "wx")
  case prim__nullAnyPtr pointer /= 0 of
    True => do
      failure <- the (IO (Either FileError ())) returnError
      pure (Left ("Cannot create temporary score file " ++ path ++ ": " ++
                  either show (const "unknown error") failure))
    False => do
      let file = FHandle pointer
      written <- fPutStrLn file (show score)
      flushed <- the (IO (Either FileError ())) $ case written of
        Left err => pure (Left err)
        Right () => do
          result <- primIO (prim__flush pointer)
          if result == 0 then pure (Right ()) else returnError
      closeFile file
      case flushed of
        Right () => pure (Right ())
        Left err => do
          _ <- removeFile path
          pure (Left ("Cannot write high score at " ++ path ++ ": " ++ show err))

export
writeHighScore : String -> Int -> IO (Either String Int)
writeHighScore path score = if score < 0 || path == "" || isSuffixOf "/" path || elem '\0' (unpack path)
  then pure (Left "The high score must be nonnegative and its path must name a file.")
  else do
    Right previous <- readHighScore path | Left err => pure (Left err)
    if score <= previous then pure (Right previous) else do
      Right () <- ensureDirectories (parentDirectories path) | Left err => pure (Left err)
      process <- getPID
      let temporary = path ++ ".tmp." ++ show process
      Right () <- writeTemporary temporary score | Left err => pure (Left err)
      result <- primIO (prim__replace temporary path)
      if result == 0 then pure (Right score) else do
        failure <- the (IO (Either FileError ())) returnError
        _ <- removeFile temporary
        pure (Left ("Cannot replace high score at " ++ path ++ ": " ++ either show (const "unknown error") failure))

public export
record ScoreStore where
  constructor MkScoreStore
  path : Maybe String
  saved : Int

export
disabledScores : ScoreStore
disabledScores = MkScoreStore Nothing 0

warn : String -> IO ()
warn message = do
  _ <- fPutStrLn stderr ("Chompit: " ++ message ++ ". High scores remain in memory for this session.")
  pure ()

export
openScores : IO ScoreStore
openScores = do
  stateHome <- getEnv "XDG_STATE_HOME"
  home <- getEnv "HOME"
  let Just path = defaultScorePath stateHome home
    | Nothing => do
        warn "Set an absolute XDG_STATE_HOME or HOME to save high scores"
        pure disabledScores
  Right score <- readHighScore path
    | Left err => do
        warn err
        pure disabledScores
  pure (MkScoreStore (Just path) score)

-- Call on death, completion, pause, or exit, not after every pellet. A failed
-- write disables persistence for this run so an error cannot repeat each frame.
export
checkpointScore : ScoreStore -> Int -> IO ScoreStore
checkpointScore store score = if score <= store.saved then pure store else case store.path of
  Nothing => pure ({ saved := score } store)
  Just path => do
    Right saved <- writeHighScore path score
      | Left err => do
          warn err
          pure (MkScoreStore Nothing score)
    pure ({ saved := saved } store)
