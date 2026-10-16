module Main

import Chompit.Types
import Chompit.Maze
import Chompit.Game
import Chompit.Input
import Chompit.Render
import Chompit.Audio
import Chompit.HighScore

import SDL3
import SDL3.Scoped

import Data.List

import System

%default covering

record Options where
  constructor MkOptions
  smoke, silent, noSave : Bool
  assets : String

parse : List String -> Options -> Either String Options
parse [] options = Right options
parse ("--smoke" :: rest) options = parse rest ({ smoke := True } options)
parse ("--silent" :: rest) options = parse rest ({ silent := True } options)
parse ("--no-save" :: rest) options = parse rest ({ noSave := True } options)
parse ("--assets" :: directory :: rest) options = parse rest ({ assets := directory } options)
parse _ _ = Left "Usage: chompit [--smoke] [--silent] [--no-save] [--assets DIRECTORY]"

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
  frames, scriptFrame, sceneFrames : Int
  heard : List Cue
  -- Difficulty level, layout, and intermission quarters seen by the renderer.
  seenLevels : List (Int, Int)
  seenScenes : List (Interlude, Int)
  scores : ScoreStore

finish : State -> Either String () -> IO (Either String ())
finish state result = do
  _ <- checkpointScore state.scores state.game.highScore
  pure result

checkpointNeeded : Game -> Bool
checkpointNeeded game = game.paused || case game.phase of Playing => False; _ => True

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
smokeInput 180 game = { fruitTime := 300 } game
smokeInput 200 game = command (Turn North) game
smokeInput 210 game = command Pause game
smokeInput 220 game = command Pause game
smokeInput 240 game = { player := MkActor (At 1 3) North 0, ghosts := [], stall := 1 } game
smokeInput 260 game = { ghosts := [MkGhost Red game.player Hunting False], stall := 1 } game
smokeInput 300 game = { frightened := 0, ghosts := [MkGhost Pink game.player Hunting False], stall := 1 } game
smokeInput 400 game = { phase := Playing, ghosts := [], remaining := 0 } game
smokeInput 410 game = { phase := Clearing 1 } game
smokeInput 420 game = { phase := Ready 1, fruitTime := 300 } game
smokeInput 430 game = { phase := Clearing 1 } game
smokeInput 440 game = { phase := Ready 1, fruitTime := 300 } game
smokeInput 450 game = { phase := Clearing 1 } game
smokeInput 460 game = { phase := Ready 1, fruitTime := 300 } game
smokeInput 470 game = { phase := Clearing 1 } game
smokeInput 480 game = { phase := Ready 1, fruitTime := 300 } game
smokeInput 490 game = { phase := Clearing 1 } game
smokeInput 500 game = { phase := Ready 1, fruitTime := 300 } game
smokeInput 510 game = { phase := Clearing 1 } game
smokeInput 520 game = { phase := Ready 1, fruitTime := 300 } game
smokeInput 530 game = { phase := Clearing 1 } game
smokeInput 540 game = { phase := Ready 1, fruitTime := 300 } game
smokeInput 550 game = { phase := Clearing 1 } game
smokeInput 560 game = { phase := Ready 1, fruitTime := 300 } game
smokeInput 570 game = { phase := Clearing 1 } game
smokeInput 580 game = { phase := Ready 1, fruitTime := 300 } game
smokeInput 590 game = { phase := Clearing 1 } game
smokeInput 600 game = { phase := Ready 1, fruitTime := 300 } game
smokeInput 610 game = { phase := Clearing 1 } game
smokeInput 620 game = { phase := Ready 1, fruitTime := 300 } game
smokeInput 630 game = { phase := Clearing 1 } game
smokeInput 640 game = { phase := Ready 1, fruitTime := 300 } game
smokeInput 644 game = { remaining := 80 } game
smokeInput 647 game = { remaining := 40 } game
smokeInput 650 game = { phase := GameOver, sounds := [FruitEaten, BonusLife] } game
smokeInput 670 game = command Start game
smokeInput 680 game = { phase := Ready 1 } game
smokeInput _ game = game

smokeMute : Int -> Bool -> Bool
smokeMute 225 _ = True
smokeMute 235 _ = False
smokeMute _ muted = muted

-- Let every scene finish without advancing the gameplay script. Pause for
-- fifteen rendered frames, then mute and unmute its music without a restart.
smokeSceneInput : Int -> Game -> Game
smokeSceneInput 45 game = command Pause game
smokeSceneInput 60 game = command Pause game
smokeSceneInput _ game = game

smokeSceneMute : Int -> Bool -> Bool
smokeSceneMute 90 _ = True
smokeSceneMute 100 _ = False
smokeSceneMute _ muted = muted

sceneSample : Game -> List (Interlude, Int)
sceneSample game = case game.phase of
  Intermission scene ticks => [(scene, (intermissionDuration - ticks) `div` 120)]
  _ => []

smokePassed : State -> Bool
smokePassed state = not state.muted && state.game.level == 1 && state.game.maze.layoutId == 1 &&
  state.game.highScore >= 260 && state.frames == 700 + 3 * (intermissionDuration + 15) &&
  all (\level => elem (level, layoutNumber level) state.seenLevels) [1..13] &&
  all (\scene => all (\quarter => elem (scene, quarter) state.seenScenes) [0..3]) [Turnabout, Snag, Costume] &&
  all (\cue => elem cue state.heard) [BeginGame, ChompLow, Energize, GhostEaten, PlayerDied, LevelWon]

loop : Context -> State -> IO (Either String ())
loop context state = if context.smoke && (state.scriptFrame >= 700 || state.frames >= 3000) then
  if smokePassed state then do
    let mode : String = case context.audio of Nothing => "silent"; Just _ => "audio"
    putStrLn ("Chompit " ++ mode ++ " smoke passed: " ++ show state.frames ++ " frames, five layouts, eight bonus icons, three intermissions, level cycling, retry, movement, capture, death, pause, and mute.")
    finish state (Right ())
  else finish state (Left "The Chompit smoke test did not reach every required game state.")
  else do
    start <- ticksNS
    Right (Just (input, inputMuted)) <- poll 128 context state.game state.muted
      | Right Nothing => finish state (Right ())
      | Left err => finish state (Left err)
    let inScene = context.smoke && isIntermission state.game
    let muted = if not context.smoke then inputMuted
                else if inScene then smokeSceneMute state.sceneFrames inputMuted
                else smokeMute state.scriptFrame inputMuted
    let edited = if not context.smoke then input
                 else if inScene then smokeSceneInput state.sceneFrames input
                 else smokeInput state.scriptFrame input
    let (count, remainder) = if context.smoke then (1, 0)
          else if edited.paused then (0, 0)
          else accumulate state.remainder (cast (start - state.previous) / 1000000000)
    let simulated = stepMany count edited
    scores <- if checkpointNeeded simulated then checkpointScore state.scores simulated.highScore
              else pure state.scores
    let game = { highScore := max simulated.highScore scores.saved } simulated
    Right () <- updateAudio context.audio state.game game muted
      | Left err => finish ({ game := game, scores := scores } state) (Left err)
    Right () <- render context.display game muted
      | Left err => finish ({ game := game, scores := scores } state) (Left err)
    end <- ticksNS
    if context.smoke then pure () else
      delayNS (if end - start < 16666667 then 16666667 - (end - start) else 0)
    let heard = if context.smoke then nub (game.sounds ++ state.heard) else []
    let levels = if context.smoke then nub ((game.level, game.maze.layoutId) :: state.seenLevels) else []
    let scenes = if context.smoke then nub (sceneSample game ++ state.seenScenes) else []
    loop context ({ game := { sounds := [] } game, muted := muted, previous := start,
                    remainder := remainder, frames := state.frames + 1,
                    scriptFrame := if context.smoke && not inScene then state.scriptFrame + 1 else state.scriptFrame,
                    sceneFrames := if inScene then state.sceneFrames + 1 else 0,
                    heard := heard, seenLevels := levels, seenScenes := scenes, scores := scores } state)

runWindow : Options -> Maybe SoundBank -> IO (Either String ())
runWindow options audio = withWindow "Chompit | Idris 2 + SDL3" 672 864 resizable $ \window =>
  withRenderer window $ \renderer => do
    Right identifier <- getWindowID window | Left err => pure (Left err)
    True <- setRenderLogicalPresentation renderer 224 288 PresentationLetterbox | False => Left <$> getError
    -- Timer pacing works with software rendering and monitors of any refresh rate.
    _ <- setRenderVSync renderer VSyncDisabled
    scores <- if options.smoke || options.noSave then pure disabledScores else openScores
    let game = { highScore := scores.saved } newGame
    withDisplay renderer $ \display => withEventBuffer $ \events => do
      Right () <- startAudio audio game | Left err => pure (Left err)
      now <- ticksNS
      loop (MkContext window identifier display events audio options.smoke)
           (MkState game False now 0 0 0 0 [] [] [] scores)

main : IO ()
main = do
  args <- getArgs
  options <- either die pure (parse (drop 1 args) (MkOptions False False False "assets/sounds"))
  ok <- SDL3.init video
  result <- if not ok then Left <$> getError
            else if options.silent then runWindow options Nothing
            else withSounds options.assets (\bank => runWindow options (Just bank))
  quit
  either (\err => die ("Chompit: " ++ err)) pure result
