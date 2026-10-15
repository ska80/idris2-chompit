module Main

import Chompit.Types
import Chompit.Maze
import Chompit.Game
import Chompit.Input

import SDL3

import Data.List
import Data.Maybe
import Data.SortedMap
import Data.SortedSet

import System

%default covering

advance : Nat -> Game -> Game
advance Z game = game
advance (S n) game = advance n (step game)

playing : Game
playing = { phase := Playing, ghosts := [] } newGame

atTile : Tile -> Game
atTile tile = { player := MkActor tile North 0, wanted := North, stall := 1 } playing

isPlaying : Game -> Bool
isPlaying game = case game.phase of Playing => True; _ => False

isDying : Game -> Bool
isDying game = case game.phase of Dying _ => True; _ => False

isReady : Game -> Bool
isReady game = case game.phase of Ready _ => True; _ => False

isOver : Game -> Bool
isOver game = case game.phase of GameOver => True; _ => False

isClearing : Game -> Bool
isClearing game = case game.phase of Clearing _ => True; _ => False

isEyes : Ghost -> Bool
isEyes ghost = case ghost.state of Eyes => True; _ => False

firstGhost : Game -> Maybe Ghost
firstGhost game = head' game.ghosts

flood : Maze -> SortedSet Int
flood maze = visit 868 [At 13 23] (singleton (key (At 13 23)))
  where
    visit : Nat -> List Tile -> SortedSet Int -> SortedSet Int
    visit Z _ known = known
    visit (S n) [] known = known
    visit (S n) (tile :: rest) known =
      let next = filter (\t => walkable maze False t && not (contains (key t) known))
                        (map (neighbor tile) directions)
       in visit n (rest ++ next) (foldl (\set, t => insert (key t) set) known next)

validActor : Maze -> Bool -> Actor -> Bool
validActor maze house actor = walkable maze house actor.tile &&
  actor.progress >= 0 && actor.progress < 256 &&
  (actor.progress == 0 || canMove maze house actor.tile actor.heading)

validGame : Game -> Bool
validGame game = validActor game.maze False game.player &&
  all (\ghost => validActor game.maze True ghost.actor) game.ghosts &&
  game.remaining == cast (length (Prelude.toList game.dots) + length (Prelude.toList game.powers))

walkTest : Nat -> Game -> Bool
walkTest Z game = validGame game
walkTest (S count) game =
  let index : Int = cast count
      direction = fromMaybe West (head' (drop (cast (index `mod` 4)) directions))
      next = step (command (Turn direction) game)
   in validGame game && walkTest count next

returned : Nat -> Game -> Bool
returned Z game = False
returned (S fuel) game = case firstGhost game of
  Nothing => False
  Just ghost => case ghost.state of
    InPen _ => ghost.actor.tile == At 13 14
    _ => returned fuel (step game)

homeTest : Tile -> Bool
homeTest tile = returned 1500 ({ ghosts := [MkGhost Red (MkActor tile East 0) Eyes False] } playing)

capture : Game -> Game
capture game = step ({ player := MkActor (At 13 23) West 0, wanted := West,
                       stall := 1, freeze := 0, ghosts := [MkGhost Red (MkActor (At 13 23) West 0) Hunting False] } game)

samePosition : Actor -> Actor -> Bool
samePosition a b = actorPosition a == actorPosition b

mazeTests : List (String, Bool)
mazeTests =
  let maze = buildMaze
      reached = flood maze
      descend = \tile => tile == At 13 14 || not (walkable maze True tile) ||
        any (\d => case (lookup (key tile) maze.homeDistances, lookup (key (neighbor tile d)) maze.homeDistances) of
          (Just a, Just b) => b == a - 1
          _ => False) directions
   in [ ("The maze has 31 rows and 28 columns", length rows == 31 && all (\row => length row == 28) rows)
      , ("The maze has 240 dots and four power pellets", length (Prelude.toList maze.pellets) == 240 && length (Prelude.toList maze.energizers) == 4)
      , ("Every pellet is reachable from the player spawn", all (\i => contains i reached) (Prelude.toList maze.pellets ++ Prelude.toList maze.energizers))
      , ("The ghost house blocks the player", not (walkable maze False (At 13 14)) && not (walkable maze False (At 13 12)))
      , ("Returning ghosts can cross the house door", walkable maze True (At 13 12) && walkable maze True (At 13 14))
      , ("Outside cells and walls block all actors", not (walkable maze True (At 0 10)) && not (walkable maze True (At 0 0)))
      , ("Only the side tunnel wraps", neighbor (At 0 14) West == At 27 14 && neighbor (At 27 14) East == At 0 14 && neighbor (At 0 1) West == At (-1) 1)
      , ("Every ghost passage has a descending route home", all descend allTiles)
      ]

movementTests : List (String, Bool)
movementTests =
  let maze = buildMaze
      blocked = moveActor maze False (const North) 40 (MkActor (At 1 1) North 0)
      moving = MkActor (At 6 5) East 120
      reversed = reverseActor moving
      queued = advance 20 (command (Turn North) playing)
      tunnel = moveActor maze False (const West) 40 (MkActor (At 0 14) West 240)
      stationary = { player := MkActor (At 1 1) North 0, wanted := North } playing
   in [ ("Actors stop at walls", blocked.tile == At 1 1 && blocked.progress == 0)
      , ("Reversal keeps the same position", samePosition moving reversed && reversed.heading == West)
      , ("Two reversals restore the actor", samePosition moving (reverseActor reversed) && (reverseActor reversed).heading == East)
      , ("Turns stay queued until a junction", queued.player.tile.y < 23 && queued.player.heading == North)
      , ("Tunnel movement keeps its remainder", tunnel.tile == At 27 14 && tunnel.progress == 24)
      , ("Collision detection wraps across the tunnel", touching (MkActor (At 0 14) West 120) (MkActor (At 27 14) East 120))
      , ("Distant actors do not collide", not (touching (MkActor (At 1 1) East 0) (MkActor (At 26 29) East 0)))
      , ("Ten thousand input updates preserve movement invariants", walkTest 10000 ({ phase := Playing } newGame))
      , ("Long stationary runs stay in the corridor", validGame (advance 1000 stationary))
      , ("Frame stalls allow at most six updates", fst (accumulate 0 5) == 6)
      , ("A half step waits for the next frame", fst (accumulate 0 (1.0 / 120)) == 0 && fst (accumulate (1.0 / 120) (1.0 / 120)) == 1)
      , ("Negative elapsed time cannot move the simulation", fst (accumulate 0 (-1)) == 0)
      ]

ghostTests : List (String, Bool)
ghostTests =
  let game = { player := MkActor (At 12 20) East 0 } newGame
      north = { player := MkActor (At 12 20) North 0 } game
      red = MkGhost Red (MkActor (At 1 1) East 0) Hunting False
      pink = { identity := Pink } red
      cyan = { identity := Cyan } red
      far = { identity := Orange } red
      near = MkGhost Orange (MkActor (At 13 20) West 0) Hunting False
      active = { phase := Playing } newGame
      pen = advance 61 active
      power = step ({ ghosts := [{ actor := MkActor (At 6 5) East 120 } red] } (atTile (At 1 3)))
   in [ ("Red targets the player", chaseTarget game red == At 12 20)
      , ("Pink targets four tiles ahead", chaseTarget game pink == At 16 20)
      , ("Pink preserves the upward look-ahead quirk", chaseTarget north pink == At 8 16)
      , ("Cyan doubles the vector from red to two tiles ahead", chaseTarget game cyan == At 15 29)
      , ("Orange chases from a distance", chaseTarget game far == At 12 20)
      , ("Orange retreats when the player is near", chaseTarget game near == At 0 33)
      , ("Scatter and chase use timed phases", isScatter 0 && not (isScatter 420) && isScatter 1620 && not (isScatter 5040))
      , ("Ghosts leave the pen after their release delay", any (\g => case g.state of Leaving => True; _ => False) pen.ghosts)
      , ("A power pellet reverses hunting ghosts", maybe False (\g => g.actor.heading == West) (firstGhost power))
      , ("Frightened time pauses the scatter clock", (step ({ frightened := 100, modeTicks := 100 } playing)).modeTicks == 100)
      , ("Frightened time expires", (step ({ frightened := 1 } playing)).frightened == 0)
      , ("Later levels reduce power-pellet protection", frightDuration 1 == 360 && frightDuration 19 == 0)
      , ("Revived ghosts resist the current power pellet", not (isFrightened ({ frightened := 360 } playing) ({ revived := True } red)))
      , ("A new power pellet removes revival immunity", maybe False (isFrightened power) (firstGhost (step ({ ghosts := [{ revived := True } red] } (atTile (At 1 3))))))
      , ("Eyes regain immunity inside the house", maybe False (\g => g.revived) (firstGhost (step ({ ghosts := [MkGhost Red (MkActor (At 13 14) North 0) Eyes False] } playing))))
      , ("Eyes return from all maze corners and both tunnel ends", all homeTest [At 1 1, At 26 1, At 1 29, At 26 29, At 0 14, At 27 14])
      ]

scoreTests : List (String, Bool)
scoreTests =
  let dot = step (atTile (At 1 1))
      twice = step dot
      power = step (atTile (At 1 3))
      first = capture ({ frightened := 360 } playing)
      second = capture first
      third = capture second
      fourth = capture third
      lethal = capture playing
      bonus = addScore 10 ({ score := 9990 } playing)
      fruit = step ({ fruitTime := 100 } (atTile (At 13 17)))
      spawn = step ({ eaten := 69 } (atTile (At 1 1)))
      respawn = step ({ eaten := 169, fruitStage := 1 } (atTile (At 1 1)))
   in [ ("Dots score ten points and disappear", dot.score == 10 && dot.remaining == 243 && not (contains (key (At 1 1)) dot.dots))
      , ("A dot cannot score twice", twice.score == dot.score && twice.remaining == dot.remaining)
      , ("Power pellets score fifty points and start protection", power.score == 50 && power.frightened == 360 && power.remaining == 243)
      , ("The ghost capture chain scores 200, 400, 800, 1600", first.score == 200 && second.score == 600 && third.score == 1400 && fourth.score == 3000)
      , ("Captured ghosts become returning eyes", maybe False isEyes (firstGhost first))
      , ("Capture briefly freezes movement", (step first).freeze == 29 && samePosition first.player (step first).player)
      , ("Unprotected collision starts the death animation", isDying lethal && elem PlayerDied lethal.sounds)
      , ("The high score follows the score", fourth.highScore == 3000)
      , ("Ten thousand points award one extra life", bonus.lives == 4 && bonus.extraLife && elem BonusLife bonus.sounds)
      , ("The score bonus is awarded only once", (addScore 20000 bonus).lives == 4)
      , ("Fruit scores the current level value", fruit.score == 100 && fruit.fruitTime == 0 && elem FruitEaten fruit.sounds)
      , ("Fruit appears after seventy pellets", spawn.fruitTime == 600 && spawn.fruitStage == 1)
      , ("Fruit appears again after 170 pellets", respawn.fruitTime == 600 && respawn.fruitStage == 2)
      , ("Fruit expires", (step ({ fruitTime := 1 } playing)).fruitTime == 0)
      , ("Fruit values increase with levels", fruitValue 1 == 100 && fruitValue 2 == 300 && fruitValue 13 == 5000)
      ]

stateTests : List (String, Bool)
stateTests =
  let started = command Start newGame
      paused = command Pause playing
      dead = { phase := Dying 1, score := 100, remaining := 240, eaten := 4 } playing
      respawn = step dead
      over = step ({ lives := 1 } dead)
      won = step ({ remaining := 0 } playing)
      next = step ({ phase := Clearing 1, score := 1230, lives := 2 } playing)
      lostFocus = command LoseFocus playing
      retried = command Start ({ highScore := 4500 } over)
   in [ ("Enter starts a ready countdown", isReady started && elem BeginGame started.sounds)
      , ("Ready blocks movement", samePosition started.player (step started).player)
      , ("Ready ends after three seconds", isPlaying (advance 180 started))
      , ("Pause freezes all simulation clocks", paused.paused && (advance 100 paused).frame == paused.frame)
      , ("Pause resumes play", not (command Pause paused).paused)
      , ("Focus loss pauses instead of losing a life", lostFocus.paused && (advance 1000 lostFocus).lives == 3)
      , ("Death removes a life and resets actors", respawn.lives == 2 && isReady respawn && respawn.player.tile == At 13 23)
      , ("Death keeps the score and collected pellets", respawn.score == 100 && respawn.remaining == 240 && respawn.eaten == 4)
      , ("The final life ends the game", isOver over && over.lives == 0)
      , ("Retry keeps the session high score", retried.highScore == 4500 && retried.score == 0 && retried.lives == 3)
      , ("The last pellet starts the level-clear animation", isClearing won && elem LevelWon won.sounds)
      , ("The next level restores all pellets and keeps lives and score", next.level == 2 && next.remaining == 244 && next.lives == 2 && next.score == 1230 && isReady next)
      ]

inputTests : List (String, Bool)
inputTests =
  let window = MkWindowID 1
      other = MkWindowID 2
      up = keyCommand (MkScancode 82) (MkKeycode 0)
      key = KeyboardEvent 0 (MkKeyboardData other Pressed (MkScancode 82) (MkKeycode 0) (MkKeyModifiers 0) False)
      enter = MkKeyboardData window Pressed (MkScancode 40) (MkKeycode 13) (MkKeyModifiers 0) False
   in [ ("Arrow keys select a direction", case up of Turn North => True; _ => False)
      , ("Escape quits", case keyCommand (MkScancode 0) escapeKey of Quit => True; _ => False)
      , ("Events from other windows are ignored", case commandFor window key of Right Ignore => True; _ => False)
      , ("Focus loss becomes a pause command", case commandFor window (WindowFocusLostEvent 0 window) of Right LoseFocus => True; _ => False)
      , ("Window close requests quit", case commandFor window (WindowCloseEvent 0 window) of Right Quit => True; _ => False)
      , ("Enter reaches the start command", case commandFor window (KeyboardEvent 0 enter) of Right Start => True; _ => False)
      , ("Repeated presses do not toggle controls", case commandFor window (KeyboardEvent 0 ({ repeated := True } enter)) of Right Ignore => True; _ => False)
      , ("Key releases do not issue commands", case commandFor window (KeyboardEvent 0 ({ action := Released } enter)) of Right Ignore => True; _ => False)
      , ("Letter controls also accept uppercase keys", case keyCommand (MkScancode 0) (MkKeycode 87) of Turn North => True; _ => False)
      ]

runTests : List (String, Bool) -> IO ()
runTests [] = pure ()
runTests ((name, passed) :: rest) = do
  if passed then putStrLn ("PASS " ++ name) else die ("FAIL " ++ name)
  runTests rest

main : IO ()
main = do
  let tests = mazeTests ++ movementTests ++ ghostTests ++ scoreTests ++ stateTests ++ inputTests
  runTests tests
  putStrLn (show (length tests) ++ " Chompit tests passed.")
