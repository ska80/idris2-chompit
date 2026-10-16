module Intermissions

import Chompit.Types
import Chompit.Maze
import Chompit.Game
import Chompit.Audio

import Data.List
import Data.Maybe
import Data.SortedSet

%default covering

advance : Nat -> Game -> Game
advance Z game = game
advance (S count) game = advance count (step game)

cleared : Int -> Game
cleared level =
  let maze = buildMaze level
   in { maze := maze, level := level, dots := empty, powers := empty, remaining := 0,
        eaten := pelletCount maze, phase := Clearing 1,
        score := 15000, highScore := 20000, lives := 2, extraLife := True,
        player := MkActor (At 1 1) East 72, wanted := West,
        ghosts := map (\g => { reversePending := g.identity == Red } g) newGame.ghosts,
        modeTicks := 1000, chain := 3, stall := 2, freeze := 30,
        fruitTime := 90, fruitStage := 2, popup := Just (At 13 17, 100, 60),
        release := MkReleaseCounters 0 30 60 Nothing 12 False, seed := 123 } newGame

sameState : GhostState -> GhostState -> Bool
sameState Hunting Hunting = True
sameState (InPen a) (InPen b) = a == b
sameState (Leaving a) (Leaving b) = a == b
sameState Eyes Eyes = True
sameState _ _ = False

sameActor : Actor -> Actor -> Bool
sameActor a b = a.tile == b.tile && a.heading == b.heading && a.progress == b.progress

sameGhost : Ghost -> Ghost -> Bool
sameGhost a b = a.identity == b.identity && sameActor a.actor b.actor &&
  sameState a.state b.state && a.revived == b.revived && a.reversePending == b.reversePending

sameCounters : ReleaseCounters -> ReleaseCounters -> Bool
sameCounters a b = a.pinkDots == b.pinkDots && a.cyanDots == b.cyanDots &&
  a.orangeDots == b.orangeDots && a.globalDots == b.globalDots &&
  a.idleTicks == b.idleTicks && a.elroyWaiting == b.elroyWaiting

sameRound : Game -> Game -> Bool
sameRound a b =
  a.level == b.level && a.maze.layoutId == b.maze.layoutId &&
  all (\tile => cellAt a.maze tile == cellAt b.maze tile) allTiles &&
  Prelude.toList a.dots == Prelude.toList b.dots && Prelude.toList a.powers == Prelude.toList b.powers &&
  a.remaining == b.remaining && a.eaten == b.eaten && sameActor a.player b.player && a.wanted == b.wanted &&
  length a.ghosts == length b.ghosts && all (uncurry sameGhost) (zip a.ghosts b.ghosts) &&
  a.score == b.score && a.highScore == b.highScore && a.lives == b.lives && a.extraLife == b.extraLife &&
  a.frightened == b.frightened && a.chain == b.chain && a.modeTicks == b.modeTicks &&
  a.stall == b.stall && a.freeze == b.freeze && a.fruitTime == b.fruitTime && a.fruitStage == b.fruitStage &&
  a.popup == b.popup && a.seed == b.seed && a.sounds == b.sounds && sameCounters a.release b.release

isReady : Game -> Bool
isReady game = case game.phase of Ready 120 => True; _ => False

isPlaying : Game -> Bool
isPlaying game = case game.phase of Playing => True; _ => False

scheduledScene : (Int, Interlude) -> List (String, Bool)
scheduledScene (level, scene) =
  let before = cleared level
      start = step before
      middle = advance 240 start
      last = advance 239 middle
      loaded = step last
      expected = buildMaze (level + 1)
      label = "Intermission after level " ++ show level ++ ": "
   in [ (label ++ "starts only after the completion animation",
         case start.phase of Intermission found ticks => found == scene && ticks == intermissionDuration; _ => False)
      , (label ++ "entry preserves the completed round", sameRound before start && start.frame == before.frame + 1)
      , (label ++ "the first update counts down without simulating the maze",
         sameRound start (step start) && case (step start).phase of Intermission _ ticks => ticks == 479; _ => False)
      , (label ++ "the whole eight-second scene keeps actors, score, lives, and timers frozen",
         sameRound start middle && sameRound start last &&
         last.frame == start.frame + 479 && case last.phase of Intermission _ 1 => True; _ => False)
      , (label ++ "automatically loads the next layout exactly once",
         loaded.level == level + 1 && loaded.maze.layoutId == expected.layoutId &&
         isReady loaded && (step loaded).level == loaded.level && not (isIntermission loaded))
      , (label ++ "keeps score, high score, lives, and the extra-life flag",
         loaded.score == 15000 && loaded.highScore == 20000 && loaded.lives == 2 && loaded.extraLife)
      , (label ++ "restores pellets and resets the next round",
         loaded.remaining == pelletCount expected && Prelude.toList loaded.dots == Prelude.toList expected.pellets &&
         Prelude.toList loaded.powers == Prelude.toList expected.energizers &&
         loaded.eaten == 0 && loaded.modeTicks == 0 && loaded.stall == 0 && loaded.freeze == 0 &&
         loaded.fruitTime == 0 && loaded.fruitStage == 0 && isNothing loaded.popup &&
         loaded.player.tile == At 13 23 && loaded.player.progress == 0 &&
         sameCounters loaded.release newGame.release && loaded.seed == 42)
      , (label ++ "resumes play after the normal ready countdown", isPlaying (advance 120 loaded))
      , (label ++ "the schedule uses difficulty, not layout identity", intermissionFor level == Just scene)
      ]

scheduleRules : List (String, Bool)
scheduleRules =
  [ ("Scenes occur after levels 2, 5, 9, 13, and 17 only",
      filter (isJust . intermissionFor) [1..256] == [2, 5, 9, 13, 17])
  , ("The third scene repeats without restarting the scene sequence",
      map intermissionFor [2, 5, 9, 13, 17, 21] ==
        [Just Turnabout, Just Snag, Just Costume, Just Costume, Just Costume, Nothing])
  , ("Nonscheduled levels proceed straight to the next ready countdown",
      all (\level => let game = step (cleared level) in isReady game && game.level == level + 1)
        [1, 3, 4, 6, 7, 8, 10, 14, 18, 21, 25, 256])
  , ("Nonpositive and very late levels do not schedule a scene",
      all (isNothing . intermissionFor) [-1, 0, 1000])
  , ("The completion animation cannot be skipped with Enter",
      case (command Start (cleared 2)).phase of Clearing 1 => True; _ => False)
  ]

controlRules : List (String, Bool)
controlRules =
  let start = step (cleared 2)
      paused = command Pause start
      held = advance 600 paused
      resumed = command Pause held
      skipped = command Start start
      finished = advance 480 start
      focused = command LoseFocus start
   in [ ("Pause freezes the intermission clock and all round data",
         held.paused && held.frame == paused.frame && sameRound held paused &&
         case held.phase of Intermission Turnabout 480 => True; _ => False)
      , ("Resume continues the same scene from the same point",
         not resumed.paused && sameRound resumed start &&
         case (step resumed).phase of Intermission Turnabout 479 => True; _ => False)
      , ("Focus loss pauses an intermission", focused.paused && (advance 600 focused).frame == focused.frame)
      , ("Movement commands cannot change actors or queued turns during a scene",
         all (\direction => sameRound start (command (Turn direction) start)) directions)
      , ("Enter skips to the same next round as normal completion",
         isReady skipped && sameRound skipped finished && skipped.level == 3)
      , ("Repeated Enter cannot skip another level", sameRound skipped (command Start skipped))
      , ("Enter does not skip a paused scene", isIntermission (command Start paused) && (command Start paused).paused)
      , ("An expired or invalid scene countdown still advances safely",
         all (\ticks => isReady (step ({ phase := Intermission Turnabout ticks } start))) (the (List Int) [0, -1]))
      ]

audioRules : List (String, Bool)
audioRules =
  let before = cleared 2
      scene = step before
      paused = command Pause scene
      next = command Start scene
      playing = { phase := Playing } newGame
   in [ ("Intermissions start only their own music", loopChanges before scene == ([], ["intermission"]))
      , ("Scene updates keep the music position", loopChanges scene (step scene) == ([], []))
      , ("Pausing an intermission does not restart its music", loopChanges scene paused == ([], []))
      , ("Resuming an intermission keeps its music position", loopChanges paused (command Pause paused) == ([], []))
      , ("Skipping stops the intermission music before the ready countdown",
         loopChanges scene next == (["intermission"], []))
      , ("Automatic completion stops the same track",
         loopChanges ({ phase := Intermission Turnabout 1 } scene) next == (["intermission"], []))
      , ("Gameplay starts only after the next ready countdown",
         loopChanges next (advance 120 next) == ([], ["gameplay", "siren-fast"]))
      , ("Scene music does not overlap gameplay music or warning loops",
         loopChanges playing scene == (["gameplay", "siren"], ["intermission"]))
      , ("All three scenes use the preloaded intermission track",
         all (\kind => loopChanges before ({ phase := Intermission kind 480 } scene) ==
           ([], ["intermission"])) [Turnabout, Snag, Costume])
      ]

export
intermissionTests : List (String, Bool)
intermissionTests = scheduleRules ++
  concatMap scheduledScene [(2, Turnabout), (5, Snag), (9, Costume), (13, Costume), (17, Costume)] ++
  controlRules ++ audioRules
