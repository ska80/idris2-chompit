module Main

import Chompit.Types
import Chompit.Maze
import Chompit.Game
import Chompit.Input
import Chompit.Render
import Chompit.Audio

import SDL3
import SDL3.Scoped

import Data.List

import System

%default covering

record Options where
  constructor MkOptions
  smoke, silent : Bool
  assets : String

parse : List String -> Options -> Either String Options
parse [] options = Right options
parse ("--smoke" :: rest) options = parse rest ({ smoke := True } options)
parse ("--silent" :: rest) options = parse rest ({ silent := True } options)
parse ("--assets" :: directory :: rest) options = parse rest ({ assets := directory } options)
parse _ _ = Left "Usage: chompit [--smoke] [--silent] [--assets DIRECTORY]"

record Context where
  constructor MkContext
  window : Window
  identifier : WindowID
  display : Display
  events : EventBuffer
  audio : Maybe SoundBank
  smoke : Bool

record State where
  constructor MkState
  game : Game
  muted : Bool
  previous : Bits64
  remainder : Double
  frames : Int
  heard : List Cue
  -- Difficulty level and the layout that the renderer receives.
  seenLevels : List (Int, Int)

poll : Nat -> Context -> Game -> Bool -> IO (Either String (Maybe (Game, Bool)))
poll Z context game muted = pure (Right (Just (game, muted)))
poll (S fuel) context game muted = do
  Just event <- pollEventData context.events | Nothing => pure (Right (Just (game, muted)))
  let Right input = commandFor context.identifier event | Left err => pure (Left err)
  case input of
    Quit => pure (Right Nothing)
    ToggleMute => poll fuel context game (not muted)
    _ => poll fuel context (command input game) muted

stepMany : Nat -> Game -> Game
stepMany Z game = game
stepMany (S count) game = stepMany count (step game)

-- Exercise drawing and audio without a real window, keyboard, or sound device.
-- Simulation rules have separate tests. These setups reach each visual state.
smokeInput : Int -> Game -> Game
smokeInput 1 game = command Start game
smokeInput 200 game = command (Turn North) game
smokeInput 210 game = command Pause game
smokeInput 220 game = command Pause game
smokeInput 240 game = { player := MkActor (At 1 3) North 0, ghosts := [], stall := 1 } game
smokeInput 260 game = { ghosts := [MkGhost Red game.player Hunting False], stall := 1 } game
smokeInput 300 game = { frightened := 0, ghosts := [MkGhost Pink game.player Hunting False], stall := 1 } game
smokeInput 400 game = { phase := Playing, ghosts := [], remaining := 0 } game
smokeInput 410 game = { phase := Clearing 1 } game
smokeInput 430 game = { phase := Clearing 1 } game
smokeInput 450 game = { phase := Clearing 1 } game
smokeInput 470 game = { phase := Clearing 1 } game
smokeInput 490 game = { phase := Clearing 1 } game
smokeInput 510 game = { phase := GameOver, sounds := [FruitEaten, BonusLife] } game
smokeInput 530 game = command Start game
smokeInput _ game = game

smokePassed : State -> Bool
smokePassed state = state.game.level == 1 && state.game.maze.layoutId == 1 && state.game.highScore >= 260 &&
  all (\level => elem (level, layoutNumber level) state.seenLevels) [1..6] &&
  all (\cue => elem cue state.heard) [BeginGame, ChompLow, Energize, GhostEaten, PlayerDied, LevelWon]

loop : Context -> State -> IO (Either String ())
loop context state = if context.smoke && state.frames >= 560 then
  if smokePassed state then do
    let mode : String = case context.audio of Nothing => "silent"; Just _ => "audio"
    putStrLn ("Chompit " ++ mode ++ " smoke passed: 560 frames, five layouts, level cycling, retry, movement, capture, death, and pause.")
    pure (Right ())
  else pure (Left "The Chompit smoke test did not reach every required game state.")
  else do
    start <- ticksNS
    Right (Just (input, muted)) <- poll 128 context state.game state.muted
      | Right Nothing => pure (Right ())
      | Left err => pure (Left err)
    let edited = if context.smoke then smokeInput state.frames input else input
    let (count, remainder) = if context.smoke then (1, 0)
          else if edited.paused then (0, 0)
          else accumulate state.remainder (cast (start - state.previous) / 1000000000)
    let game = stepMany count edited
    Right () <- updateAudio context.audio state.game game muted | Left err => pure (Left err)
    Right () <- render context.display game muted | Left err => pure (Left err)
    end <- ticksNS
    if context.smoke then pure () else
      delayNS (if end - start < 16666667 then 16666667 - (end - start) else 0)
    let heard = if context.smoke then nub (game.sounds ++ state.heard) else []
    let levels = if context.smoke then nub ((game.level, game.maze.layoutId) :: state.seenLevels) else []
    loop context (MkState ({ sounds := [] } game) muted start remainder (state.frames + 1) heard levels)

runWindow : Options -> Maybe SoundBank -> IO (Either String ())
runWindow options audio = withWindow "Chompit | Idris 2 + SDL3" 672 864 resizable $ \window =>
  withRenderer window $ \renderer => do
    Right identifier <- getWindowID window | Left err => pure (Left err)
    True <- setRenderLogicalPresentation renderer 224 288 PresentationLetterbox | False => Left <$> getError
    -- Timer pacing works with software rendering and monitors of any refresh rate.
    _ <- setRenderVSync renderer VSyncDisabled
    let game = newGame
    withDisplay renderer $ \display => withEventBuffer $ \events => do
      Right () <- startAudio audio game | Left err => pure (Left err)
      now <- ticksNS
      loop (MkContext window identifier display events audio options.smoke)
           (MkState game False now 0 0 [] [])

main : IO ()
main = do
  args <- getArgs
  options <- either die pure (parse (drop 1 args) (MkOptions False False "assets/sounds"))
  ok <- SDL3.init video
  result <- if not ok then Left <$> getError
            else if options.silent then runWindow options Nothing
            else withSounds options.assets (\bank => runWindow options (Just bank))
  quit
  either (\err => die ("Chompit: " ++ err)) pure result
