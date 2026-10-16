module Main

import Arcade
import Chompit.Types
import Chompit.Maze
import Chompit.Game
import Chompit.Input
import Chompit.Audio
import Chompit.Fruit
import Chompit.HighScore

import SDL3

import Data.List
import Data.Maybe
import Data.SortedMap
import Data.SortedSet
import Data.String

import System

%default covering

advance : Nat -> Game -> Game
advance Z game = game
advance (S n) game = advance n (step game)

playing : Game
playing = { phase := Playing, ghosts := [] } newGame

freshLevel : Int -> Game
freshLevel number =
  let maze = buildMaze number
   in { maze := maze, dots := maze.pellets, powers := maze.energizers,
        level := number, remaining := pelletCount maze } playing

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
validGame game = game.maze.layoutId == layoutNumber game.level &&
  validActor game.maze False game.player &&
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

homeTest : Game -> Tile -> Bool
homeTest game tile = returned 1500 ({ ghosts := [MkGhost Red (MkActor tile East 0) Eyes False] } game)

capture : Game -> Game
capture game = step ({ player := MkActor (At 13 23) West 0, wanted := West,
                       stall := 1, freeze := 0, ghosts := [MkGhost Red (MkActor (At 13 23) West 0) Hunting False] } game)

samePosition : Actor -> Actor -> Bool
samePosition a b = actorPosition a == actorPosition b

mazeTests : List (String, Bool)
mazeTests =
  let maze = buildMaze 1
      reached = flood maze
      descend = \tile => tile == At 13 14 || not (walkable maze True tile) ||
        any (\d => case (lookup (key tile) maze.homeDistances, lookup (key (neighbor tile d)) maze.homeDistances) of
          (Just a, Just b) => b == a - 1
          _ => False) directions
   in [ ("The maze has 31 rows and 28 columns", length (rows 1) == 31 && all (\row => length row == 28) (rows 1))
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
  let maze = buildMaze 1
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
      pen = step active
      power = step ({ ghosts := [{ actor := MkActor (At 6 5) East 120 } red] } (atTile (At 1 3)))
   in [ ("Red targets the player", chaseTarget game red == At 12 20)
      , ("Pink targets four tiles ahead", chaseTarget game pink == At 16 20)
      , ("Pink preserves the upward look-ahead quirk", chaseTarget north pink == At 8 16)
      , ("Cyan doubles the vector from red to two tiles ahead", chaseTarget game cyan == At 15 29)
      , ("Orange chases from a distance", chaseTarget game far == At 12 20)
      , ("Orange retreats when the player is near", chaseTarget game near == At 0 33)
      , ("Scatter and chase use timed phases", isScatter 1 0 && not (isScatter 1 420) && isScatter 1 1620 && not (isScatter 1 5040))
      , ("Pink leaves the pen without waiting for pellets", any (\g => case g.state of Leaving _ => g.identity == Pink; _ => False) pen.ghosts)
      , ("A power pellet reverses hunting ghosts", maybe False (\g => g.actor.heading == West) (firstGhost power))
      , ("Frightened time pauses the scatter clock", (step ({ frightened := 100, modeTicks := 100 } playing)).modeTicks == 100)
      , ("Frightened time expires", (step ({ frightened := 1 } playing)).frightened == 0)
      , ("Later levels reduce power-pellet protection", frightDuration 1 == 360 && frightDuration 19 == 0)
      , ("Revived ghosts resist the current power pellet", not (isFrightened ({ frightened := 360 } playing) ({ revived := True } red)))
      , ("A new power pellet removes revival immunity", maybe False (isFrightened power) (firstGhost (step ({ ghosts := [{ revived := True } red] } (atTile (At 1 3))))))
      , ("Eyes regain immunity inside the house", maybe False (\g => g.revived) (firstGhost (step ({ ghosts := [MkGhost Red (MkActor (At 13 14) North 0) Eyes False] } playing))))
      , ("Eyes return from all maze corners and both tunnel ends", all (homeTest playing) [At 1 1, At 26 1, At 1 29, At 26 29, At 0 14, At 27 14])
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
      , ("The next level restores all pellets and keeps lives and score", next.level == 2 && next.remaining == pelletCount (buildMaze 2) && next.lives == 2 && next.score == 1230 && isReady next)
      ]

sameMaze : Maze -> Maze -> Bool
sameMaze a b = a.layoutId == b.layoutId &&
  Prelude.toList a.pellets == Prelude.toList b.pellets &&
  Prelude.toList a.energizers == Prelude.toList b.energizers &&
  all (\tile => cellAt a tile == cellAt b tile &&
                lookup (key tile) a.homeDistances == lookup (key tile) b.homeDistances) allTiles

levelMazeTests : Int -> List (String, Bool)
levelMazeTests number =
  let maze = buildMaze number
      reached = flood maze
      label = "Layout " ++ show number ++ ": "
      expected : Int = case number of 1 => 244; 2 => 258; 3 => 250; 4 => 252; _ => 260
      passages = filter (walkable maze False) allTiles
      descend = \tile => tile == At 13 14 || not (walkable maze True tile) ||
        any (\d => case (lookup (key tile) maze.homeDistances, lookup (key (neighbor tile d)) maze.homeDistances) of
          (Just a, Just b) => b == a - 1
          _ => False) directions
      border = filter (\t => (t.x == 0 || t.x == 27 || t.y == 0 || t.y == 30) && t.y /= 14) allTiles
      anchors = [(At 13 23, ' '), (At 14 23, ' '), (At 13 11, ' '), (At 13 17, ' '),
                 (At 13 12, '-'), (At 14 12, '-'), (At 11 14, 'h'), (At 13 14, 'h'),
                 (At 15 14, 'h'), (At 0 14, ' '), (At 27 14, ' ')]
   in [ (label ++ "31 rows and 28 columns",
         length (rows number) == 31 && all (\row => length row == 28) (rows number))
      , (label ++ "only supported cell symbols",
         all (\c => elem c (unpack "#.ox h-")) (concatMap unpack (rows number)))
      , (label ++ "horizontal symmetry",
         all (\row => unpack row == reverse (unpack row)) (rows number))
      , (label ++ "four power pellets and the expected dot count",
         length (Prelude.toList maze.energizers) == 4 && pelletCount maze == expected)
      , (label ++ "all passages and pellets are reachable",
         all (\tile => contains (key tile) reached) passages &&
         all (\i => contains i reached) (Prelude.toList maze.pellets ++ Prelude.toList maze.energizers))
      , (label ++ "spawn, fruit, house, door, and tunnel positions stay legal",
         all (\(tile, symbol) => cellAt maze tile == symbol) anchors)
      , (label ++ "only the tunnel opens at the border",
         all (\tile => not (walkable maze True tile)) border)
      , (label ++ "no dead-end passages",
         all (\tile => length (filter (canMove maze False tile) directions) >= 2) passages)
      , (label ++ "every ghost passage has a route home", all descend allTiles)
      , (label ++ "eyes return from corners and tunnel ends",
         all (homeTest (freshLevel number)) [At 1 1, At 26 1, At 1 29, At 26 29, At 0 14, At 27 14])
      , (label ++ "movement stays legal at every tile boundary",
         all (\tile => all (\direction => validActor maze False
           (moveActor maze False (const direction) 40 (MkActor tile direction 240))) directions) passages)
      ]

lastPellet : Int -> Bool -> Game
lastPellet number power =
  let game = freshLevel number
      tile : Tile = if power then At 1 3 else At 1 1
   in { player := MkActor tile North 0, wanted := North, stall := 1,
        dots := if power then empty else singleton (key tile),
        powers := if power then singleton (key tile) else empty,
        remaining := 1, eaten := pelletCount game.maze - 1,
        score := 14000, highScore := 20000, lives := 2, extraLife := True,
        frightened := 12, chain := 3, modeTicks := 500,
        fruitStage := 2, fruitTime := 300, popup := Just (At 13 17, 100, 90) } game

levelTransitionTests : Int -> List (String, Bool)
levelTransitionTests number =
  let before = lastPellet number False
      cleared = step before
      flash = advance 119 cleared
      loaded = step flash
      started = advance 120 loaded
      expected = buildMaze (number + 1)
      power = step (lastPellet number True)
      paused = advance 500 (command Pause cleared)
      collected = step ({ player := MkActor (At 1 1) North 0, wanted := North, stall := 1 } (freshLevel number))
      respawn = step ({ phase := Dying 1, lives := 2 } collected)
      label = "Level " ++ show number ++ ": "
   in [ (label ++ "the last dot starts completion",
         isClearing cleared && cleared.remaining == 0 && cleared.score == 14010 && elem LevelWon cleared.sounds)
      , (label ++ "the last power pellet also completes the level",
         isClearing power && power.remaining == 0 && power.score == 14050)
      , (label ++ "the old maze remains during the clear animation",
         isClearing flash && flash.level == number && sameMaze flash.maze before.maze)
      , (label ++ "the next maze loads automatically",
         loaded.level == number + 1 && sameMaze loaded.maze expected && isReady loaded)
      , (label ++ "the new maze restores its own pellets",
         loaded.remaining == pelletCount expected && Prelude.toList loaded.dots == Prelude.toList expected.pellets &&
         Prelude.toList loaded.powers == Prelude.toList expected.energizers)
      , (label ++ "score, high score, lives, and bonus status carry over",
         loaded.score == 14010 && loaded.highScore == 20000 && loaded.lives == 2 && loaded.extraLife)
      , (label ++ "actors and round timers reset",
         validGame loaded && loaded.player.tile == At 13 23 && loaded.player.progress == 0 &&
         loaded.player.heading == West && loaded.wanted == West && length loaded.ghosts == 4 &&
         loaded.eaten == 0 && loaded.frightened == 0 && loaded.chain == 0 && loaded.modeTicks == 0 &&
         loaded.stall == 0 && loaded.freeze == 0 && loaded.fruitTime == 0 && loaded.fruitStage == 0 &&
         isNothing loaded.popup)
      , (label ++ "play resumes without another start command",
         isPlaying started && samePosition started.player loaded.player && started.remaining == loaded.remaining)
      , (label ++ "pause delays automatic progression",
         paused.paused && isClearing paused && paused.level == number &&
         (advance 120 (command Pause paused)).level == number + 1)
      , (label ++ "death preserves the current maze and collected pellets",
         isReady respawn && respawn.level == number && sameMaze respawn.maze collected.maze &&
         respawn.remaining == collected.remaining && Prelude.toList respawn.dots == Prelude.toList collected.dots &&
         Prelude.toList respawn.powers == Prelude.toList collected.powers)
      ]

levelTests : List (String, Bool)
levelTests =
  let wallShapes = map (\number => let maze = buildMaze number in
                        map (\tile => cellAt maze tile == '#') allTiles) [1..layoutCount]
      retried = command Start ({ phase := GameOver, highScore := 20000 } (freshLevel 5))
   in concatMap levelMazeTests [1..layoutCount] ++ concatMap levelTransitionTests [1..layoutCount] ++
      [ ("Five distinct wall layouts are available", layoutCount == 5 && length (nub wallShapes) == 5)
      , ("Layouts cycle while difficulty levels keep increasing",
         layoutNumber 6 == 1 && layoutNumber 10 == 5 && layoutNumber 11 == 1 && rows 6 == rows 1)
      , ("Nonpositive layout requests use the first maze", rows 0 == rows 1 && rows (-1) == rows 1)
      , ("Retry from a later maze returns to the first layout",
         retried.level == 1 && sameMaze retried.maze (buildMaze 1) && retried.remaining == 244 &&
         retried.highScore == 20000 && isReady retried)
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

audioTests : List (String, Bool)
audioTests =
  let ready = { phase := Ready 120 } newGame
      powered = { frightened := 360 } playing
      paused = command Pause playing
      dead = { phase := Dying 90 } playing
      cleared = { phase := Clearing 120 } playing
      over = { phase := GameOver } playing
      eyes = MkGhost Red (MkActor (At 1 1) East 0) Eyes False
      returning = { ghosts := [eyes] } playing
   in [ ("The start jingle does not overlap background loops",
         loopChanges newGame ready == (["title"], []))
      , ("Gameplay starts music and the siren together",
         loopChanges ready playing == ([], ["gameplay", "siren"]))
      , ("Ordinary updates do not restart the loops", loopChanges playing playing == ([], []))
      , ("Power pellets change the alarm without restarting music",
         loopChanges playing powered == (["siren"], ["frightened"]))
      , ("Expiring protection keeps the music playing",
         loopChanges powered playing == (["frightened"], ["siren"]))
      , ("Ghost capture keeps the music position",
         loopChanges powered ({ freeze := 30 } powered) == ([], []))
      , ("Pause keeps the selected loops", loopChanges playing paused == ([], []))
      , ("Resume does not restart the loops", loopChanges paused (command Pause paused) == ([], []))
      , ("Death stops both gameplay loops", loopChanges playing dead == (["gameplay", "siren"], []))
      , ("Death also stops the frightened loop",
         loopChanges powered dead == (["gameplay", "frightened"], []))
      , ("Level completion stops both gameplay loops",
         loopChanges playing cleared == (["gameplay", "siren"], []))
      , ("Game over stops the music", loopChanges playing over == (["gameplay", "siren"], []))
      , ("The ready countdown stays free of background music", loopChanges dead ready == ([], []))
      , ("The next level starts a fresh music loop",
         loopChanges ready (freshLevel 2) == ([], ["gameplay", "siren-fast"]))
      , ("Retry waits for play before starting music", loopChanges over (command Start over) == ([], []))
      , ("The four sirens follow scheduled hunting speeds",
         map (\level => sirenName (freshLevel level)) [1..7] ==
           ["siren", "siren-fast", "siren-fast", "siren-fast", "siren-faster", "siren-faster", "siren-faster"])
      , ("Red's late-maze acceleration also raises the siren",
         huntingSpeed playing Red == 75 && huntingSpeed ({ remaining := 20 } playing) Red == 80 &&
         sirenName ({ remaining := 21 } playing) == "siren" &&
         loopChanges playing ({ remaining := 20 } playing) == (["siren"], ["siren-fast"]))
      , ("Returning eyes replace the warning without restarting music",
         loopChanges playing returning == (["siren"], ["eyes"]))
      , ("Eyes take priority over frightened audio",
         loopChanges powered ({ ghosts := [eyes] } powered) == (["frightened"], ["eyes"]))
      , ("The eyes loop remains while any ghost is returning",
         loopChanges returning ({ ghosts := [eyes, { identity := Pink } eyes] } returning) == ([], []))
      , ("Returned ghosts restore the current siren",
         loopChanges returning ({ ghosts := [{ state := InPen West } eyes] } playing) == (["eyes"], ["siren"]))
      , ("Remaining protection restores frightened audio after eyes return",
         loopChanges ({ ghosts := [eyes] } powered) powered == (["eyes"], ["frightened"]))
      , ("A speed change during frightened time keeps the same warning",
         loopChanges powered ({ remaining := 1 } powered) == ([], []))
      , ("Death stops the eyes loop and music", loopChanges returning dead == (["gameplay", "eyes"], []))
      ]

bonusTests : List (String, Bool)
bonusTests =
  let tiers = [Cherries, Strawberry, OrangeFruit, Apple, Melon, Galaxian, Bell, KeyFruit]
      sprites = map fruitSprite tiers
   in [ ("Bonus tiers match the level schedule",
         map fruitForLevel [1..14] == [Cherries, Strawberry, OrangeFruit, OrangeFruit, Apple, Apple,
           Melon, Melon, Galaxian, Galaxian, Bell, Bell, KeyFruit, KeyFruit])
      , ("Each bonus tier keeps its score value",
         map fruitValue [1, 2, 3, 5, 7, 9, 11, 13] == [100, 300, 500, 700, 1000, 2000, 3000, 5000])
      , ("Nonpositive levels use cherries", fruitForLevel 0 == Cherries && fruitForLevel (-1) == Cherries)
      , ("Every bonus icon has its own artwork", length (nub sprites) == 8)
      , ("Bonus icons are sixteen pixels square",
         all (\sprite => length sprite == 16 && all (\row => length row == 16) sprite) sprites)
      , ("Bonus icons use only supported colors",
         all (\c => elem c (unpack ".rgwoycb")) (concatMap (concatMap unpack) sprites))
      , ("Each bonus icon has visible pixels", all (\sprite => any (/= '.') (concatMap unpack sprite)) sprites)
      ]

highScoreTests : List (String, Bool)
highScoreTests =
  [ ("Saved scores accept decimal text and surrounding whitespace",
     parseHighScore "12345" == Just 12345 && parseHighScore "  9000\n" == Just 9000)
  , ("Saved scores accept zero", parseHighScore "0\n" == Just 0)
  , ("Saved scores reject negative and signed values",
     isNothing (parseHighScore "-1") && isNothing (parseHighScore "+123"))
  , ("Saved scores reject empty, malformed, and multiline data",
     all (isNothing . parseHighScore) ["", " \n", "12x", "1.5", "100\n200", "100\0ignored"])
  , ("Saved scores reject overflow and oversized input",
     isNothing (parseHighScore "99999999999999999999999999999") &&
     isNothing (parseHighScore (pack (replicate 65 '1'))))
  , ("XDG state storage takes priority over HOME",
     defaultScorePath (Just "/state") (Just "/home/test") == Just "/state/chompit/high-score")
  , ("Empty and relative XDG paths fall back to HOME",
     all (\path => defaultScorePath path (Just "/home/test") == Just "/home/test/.local/state/chompit/high-score")
       [Nothing, Just "", Just "relative", Just "/bad\0path"])
  , ("Missing absolute state roots disable persistence",
     defaultScorePath Nothing Nothing == Nothing && defaultScorePath (Just "relative") (Just "relative") == Nothing)
  , ("State roots handle trailing slashes",
     defaultScorePath (Just "/state/") Nothing == Just "/state/chompit/high-score" &&
     defaultScorePath (Just "/") Nothing == Just "/chompit/high-score")
  , ("Score directories preserve absolute and relative paths",
     parentDirectories "/tmp/a/b/score" == ["/tmp", "/tmp/a", "/tmp/a/b"] &&
     parentDirectories "a/b/score" == ["a", "a/b"] && parentDirectories "score" == [])
  ]

runTests : List (String, Bool) -> IO ()
runTests [] = pure ()
runTests ((name, passed) :: rest) = do
  if passed then putStrLn ("PASS " ++ name) else die ("FAIL " ++ name)
  runTests rest

runSuite : IO ()
runSuite = do
  let tests = mazeTests ++ movementTests ++ ghostTests ++ scoreTests ++ stateTests ++
              levelTests ++ inputTests ++ audioTests ++ bonusTests ++ highScoreTests ++ arcadeTests
  runTests tests
  putStrLn (show (length tests) ++ " Chompit tests passed.")

-- The Python integration tests supply temporary paths to these I/O commands.
main : IO ()
main = do
  args <- getArgs
  case drop 1 args of
    [] => runSuite
    ["--read-score", path] => do
      result <- readHighScore path
      either die (putStrLn . show) result
    ["--write-score", path, text] => do
      let Just score = parseInteger {a = Int} text | Nothing => die "Invalid test score."
      result <- writeHighScore path score
      either die (putStrLn . show) result
    ["--session-score", text] => do
      let Just score = parseInteger {a = Int} text | Nothing => die "Invalid test score."
      store <- openScores
      saved <- checkpointScore store score
      putStrLn (show store.saved ++ " " ++ show saved.saved)
    _ => die "Unknown test command."
