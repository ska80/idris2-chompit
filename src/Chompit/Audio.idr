module Chompit.Audio

import Chompit.Types
import Chompit.Game

import SDL3
import SDL3.Mixer
import SDL3.Mixer.Scoped

import Data.List

%default covering

export
record SoundBank where
  constructor MkSoundBank
  mixer : Mixer DeviceOutput
  tracks : List (String, Track)
  looping : PlayOptions
  musicFadeFrames : Bits64

withTracks : Mixer DeviceOutput -> String -> List String ->
             (List (String, Track) -> IO (Either String a)) -> IO (Either String a)
withTracks mixer directory [] action = action []
withTracks mixer directory (name :: names) action = withTrack mixer $ \track => do
  Right () <- withAudio mixer (directory ++ "/" ++ name ++ ".wav") Predecode (\asset => do
    True <- setTrackAudio track (Just asset) | False => Left <$> getError
    pure (Right ())) | Left err => pure (Left err)
  withTracks mixer directory names $ \rest => action ((name, track) :: rest)

cueName : Cue -> String
cueName ChompLow = "chomp-low"
cueName ChompHigh = "chomp-high"
cueName Energize = "power"
cueName GhostEaten = "eat-ghost"
cueName PlayerDied = "death"
cueName LevelWon = "clear"
cueName BeginGame = "begin"
cueName FruitEaten = "fruit"
cueName BonusLife = "extra-life"

findTrack : String -> List (String, Track) -> Maybe Track
findTrack _ [] = Nothing
findTrack name ((key, track) :: rest) = if name == key then Just track else findTrack name rest

export
withSounds : String -> (SoundBank -> IO (Either String a)) -> IO (Either String a)
withSounds directory action = withMixerLibrary $ withMixer $ \mixer =>
  withTracks mixer directory ["title", "gameplay", "begin", "chomp-low", "chomp-high", "power", "eat-ghost",
    "death", "clear", "fruit", "extra-life", "siren", "siren-fast", "siren-faster", "siren-fastest",
    "frightened", "eyes"] $ \tracks =>
      withPlayOptions $ \looping => do
        True <- setMixerGain mixer 0.65 | False => Left <$> getError
        True <- setPlayLoops looping LoopForever | False => Left <$> getError
        let Just music = findTrack "gameplay" tracks
          | Nothing => pure (Left "The gameplay music track is missing. Rebuild Chompit.")
        Right fadeFrames <- trackMSToFrames music 80 | Left err => pure (Left err)
        action (MkSoundBank mixer tracks looping fadeFrames)

play : SoundBank -> String -> Bool -> IO Bool
play bank name loop = case findTrack name bank.tracks of
  Nothing => pure False
  Just track => playTrack track (if loop then Just bank.looping else Nothing)

export
sirenName : Game -> String
sirenName game =
  let speed = huntingSpeed game Red
   in if speed <= 38 then "siren" else if speed <= 42 then "siren-fast" else
      if speed <= 46 then "siren-faster" else "siren-fastest"

warningLoop : Game -> String
warningLoop game = if any (\ghost => case ghost.state of Eyes => True; _ => False) game.ghosts
  then "eyes" else if game.frightened > 0 then "frightened" else sirenName game

ambientLoops : Game -> List String
ambientLoops game = case game.phase of
  Title => ["title"]
  Playing => ["gameplay", warningLoop game]
  _ => []

-- Loops to stop, then loops to start. Keep shared tracks running so that
-- collecting a power pellet does not restart the gameplay music.
export
loopChanges : Game -> Game -> (List String, List String)
loopChanges old new =
  let previous = ambientLoops old
      current = ambientLoops new
   in (filter (\name => not (elem name current)) previous,
       filter (\name => not (elem name previous)) current)

playLoops : SoundBank -> List String -> IO Bool
playLoops bank [] = pure True
playLoops bank (name :: rest) = do
  True <- play bank name True | False => pure False
  playLoops bank rest

stopLoops : SoundBank -> List String -> IO Bool
stopLoops bank [] = pure True
stopLoops bank (name :: rest) = do
  let Just track = findTrack name bank.tracks | Nothing => pure False
  True <- stopTrack track (if name == "gameplay" then bank.musicFadeFrames else 0)
    | False => pure False
  stopLoops bank rest

pauseAll : Bool -> List (String, Track) -> IO Bool
pauseAll paused [] = pure True
pauseAll paused ((_, track) :: rest) = do
  True <- (if paused then pauseTrack track else resumeTrack track) | False => pure False
  pauseAll paused rest

playCues : SoundBank -> List Cue -> IO Bool
playCues bank [] = pure True
playCues bank (cue :: rest) = do
  True <- play bank (cueName cue) False | False => pure False
  playCues bank rest

export
startAudio : Maybe SoundBank -> Game -> IO (Either String ())
startAudio Nothing _ = pure (Right ())
startAudio (Just bank) game = do
  True <- playLoops bank (ambientLoops game) | False => Left <$> getError
  True <- (if game.paused then pauseAll True bank.tracks else pure True) | False => Left <$> getError
  pure (Right ())

export
updateAudio : Maybe SoundBank -> Game -> Game -> Bool -> IO (Either String ())
updateAudio Nothing _ _ _ = pure (Right ())
updateAudio (Just bank) old new muted = do
  True <- setMixerGain bank.mixer (if muted then 0 else 0.65) | False => Left <$> getError
  let (stopped, started) = loopChanges old new
  True <- stopLoops bank stopped | False => Left <$> getError
  True <- playLoops bank started | False => Left <$> getError
  True <- playCues bank new.sounds | False => Left <$> getError
  True <- (if old.paused /= new.paused then pauseAll new.paused bank.tracks else pure True)
    | False => Left <$> getError
  pure (Right ())
