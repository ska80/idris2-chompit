module Cornering

import Chompit.Types
import Chompit.Maze
import Chompit.Game

import Data.List
import Data.Maybe
import Data.SortedSet

%default covering

maze : Maze
maze = buildMaze 1

junction : Tile
junction = At 6 5

quiet : Game
quiet = { phase := Playing, ghosts := [], dots := empty, powers := empty, modeTicks := 100 } newGame

sameActor : Actor -> Actor -> Bool
sameActor a b = a.tile == b.tile && a.heading == b.heading && a.progress == b.progress && a.offset == b.offset

name : Direction -> String
name North = "North"
name West = "West"
name South = "South"
name East = "East"

perpendicular : Direction -> Direction -> Bool
perpendicular a b = a /= b && a /= opposite b

-- Negative distances approach the junction. Positive distances have passed it.
approach : Tile -> Direction -> Int -> Actor
approach tile incoming distance = if distance < 0
  then MkActor (neighbor tile (opposite incoming)) incoming (256 + distance)
  else MkActor tile incoming distance

expected : Tile -> Direction -> Direction -> Int -> Int -> Actor
expected tile incoming wanted distance budget =
  let left = if distance < 0 then min 0 (distance + budget) else max 0 (distance - budget)
   in { offset := scaled left (delta incoming) } (MkActor tile wanted budget)

boundaryRules : Direction -> Direction -> List (String, Bool)
boundaryRules incoming wanted =
  let early = preTurnLimit incoming
      late = postTurnLimit incoming
      label = name incoming ++ " to " ++ name wanted ++ ": "
      move = movePlayer maze wanted
      before = approach junction incoming (-early - 1)
      first = move 0 (approach junction incoming (-early))
      last = move 0 (approach junction incoming late)
   in [ (label ++ "the earliest turn uses the directional pixel limit",
         sameActor first (expected junction incoming wanted (-early) 0))
      , (label ++ "one unit before the early limit keeps the incoming heading", sameActor (move 0 before) before)
      , (label ++ "arrival at the early limit commits the turn with no position jump",
         sameActor (move 1 before) first)
      , (label ++ "movement left after entering the turn window follows the diagonal",
         sameActor (move 32 (approach junction incoming (-early - 7)))
                   (expected junction incoming wanted (-early) 25))
      , (label ++ "the last legal late turn preserves its physical position",
         sameActor last (expected junction incoming wanted late 0) &&
         actorPosition last == actorPosition (approach junction incoming late))
      , (label ++ "one unit past the late limit cannot turn back to this junction",
         let missed = approach junction incoming (late + 1) in sameActor (move 0 missed) missed)
      , (label ++ "a turn at the center needs no diagonal correction",
         sameActor (move 32 (approach junction incoming 0)) (MkActor junction wanted 32))
      , (label ++ "early cornering gains its full three or four pixels along the exit",
         sameActor (move early (approach junction incoming (-early))) (MkActor junction wanted early))
      , (label ++ "late cornering drifts back to the new corridor centerline",
         sameActor (move late (approach junction incoming late)) (MkActor junction wanted late))
      ]

turns : Maze -> List (Tile, Direction, Direction)
turns board = concatMap (\tile => if not (walkable board False tile) then [] else
  concatMap (\incoming => if not (canMove board False tile (opposite incoming)) then [] else
    map (\wanted => (tile, incoming, wanted))
      (filter (\wanted => perpendicular incoming wanted && canMove board False tile wanted) directions)) directions) allTiles

geometry : Maze -> (Tile, Direction, Direction) -> Bool
geometry board (tile, incoming, wanted) =
  all (\distance => if distance > 0 && not (canMove board False tile incoming) then True else
    all (\budget => sameActor (movePlayer board wanted budget (approach tile incoming distance))
                              (expected tile incoming wanted distance budget))
      (the (List Int) [0, 1, 31, 32, 33, 40, 41, 128, 255]))
    [-preTurnLimit incoming, -1, 0, 1, postTurnLimit incoming]

unitWalk : Nat -> Maze -> Direction -> Actor -> Actor
unitWalk Z board wanted actor = movePlayer board wanted 0 actor
unitWalk (S count) board wanted actor = unitWalk count board wanted (movePlayer board wanted 1 actor)

splitBudget : Maze -> (Tile, Direction, Direction) -> Bool
splitBudget board (tile, incoming, wanted) =
  let start = approach tile incoming (-preTurnLimit incoming - 13)
      corner = movePlayer board wanted 17 (approach tile incoming (-preTurnLimit incoming))
      late = if canMove board False tile incoming
        then [movePlayer board wanted 17 (approach tile incoming (postTurnLimit incoming - 16))] else []
   in all (\actor => all (\direction => all (\budget =>
        let turned = if direction == opposite actor.heading then reverseActor actor else actor
         in sameActor (movePlayer board direction budget turned)
                      (unitWalk (cast budget) board direction turned))
        (the (List Int) [1, 32, 33, 36, 37, 38, 40, 41, 128, 255])) directions) (start :: corner :: late)

validActor : Maze -> Actor -> Bool
validActor board actor =
  let point = actorPosition actor
      occupied = At (((point.x + 128 + 7168) `div` 256) `mod` 28) ((point.y + 128) `div` 256)
      heading = delta actor.heading
   in walkable board False actor.tile && walkable board False occupied &&
      actor.progress >= 0 && actor.progress < 256 &&
      (actor.progress == 0 || canMove board False actor.tile actor.heading) &&
      abs actor.offset.x <= 128 && abs actor.offset.y <= 128 &&
      actor.offset.x * heading.x + actor.offset.y * heading.y == 0

bounded : Int -> Actor -> Actor -> Bool
bounded budget before after =
  let a = actorPosition before
      b = actorPosition after
      dx = abs (a.x - b.x)
   in min dx (abs (7168 - dx)) <= budget && abs (a.y - b.y) <= budget

walkInputs : Nat -> Game -> Bool
walkInputs Z game = validActor game.maze game.player
walkInputs (S count) game =
  let index : Nat = cast ((game.seed `div` 65536) `mod` 4)
      direction = if (the Int (cast count)) `mod` 7 == 0 then fromMaybe West (head' (drop index directions)) else game.wanted
      input = command (Turn direction) game
      next = step input
      budget = speedStep (playerSpeed next) next.frame
   in validActor game.maze game.player && bounded budget game.player next.player && walkInputs count next

blockedTurns : Maze -> Bool
blockedTurns board = all (\tile => if not (walkable board False tile) then True else
  all (\incoming => if not (canMove board False tile incoming) then True else
    all (\wanted => if not (perpendicular incoming wanted) || canMove board False tile wanted ||
                       canMove board False (neighbor tile incoming) wanted then True else
      all (\progress => let actor = MkActor tile incoming progress in
        sameActor (movePlayer board wanted 41 actor) (moveActor board False (const incoming) 41 actor))
        (the (List Int) [0, 1, 96, 128, 159, 160, 255])) directions) directions) allTiles

layoutRules : Int -> List (String, Bool)
layoutRules level =
  let board = buildMaze level
      candidates = turns board
      label = "Layout " ++ show level ++ ": "
   in [ (label ++ "every legal early, centered, and late turn follows the diagonal geometry", all (geometry board) candidates)
      , (label ++ "fractional and large movement budgets match one-unit steps",
         all (splitBudget board) (take 24 candidates))
      , (label ++ "blocked perpendicular inputs cannot cut through walls or the house", blockedTurns board)
      , (label ++ "ten thousand changing inputs keep the player inside passages without position jumps",
         walkInputs 10000 ({ maze := board, level := level } quiet))
      ]

movementRules : List (String, Bool)
movementRules =
  let early = movePlayer maze North 32 (approach junction East (-96))
      late = movePlayer maze North 32 (approach junction East 96)
      reversed = reverseActor late
      home = movePlayer maze South 96 reversed
      pending = movePlayer maze East 20 early
      aligned = movePlayer maze East 64 early
      wall = movePlayer maze East 80 (MkActor (At 11 1) East 240)
      tunnel = movePlayer maze West 32 (MkActor (At 0 14) West 240)
      noUp = movePlayer maze North 32 (approach (At 12 11) West (-128))
      lCorner = movePlayer maze East 32 (approach (At 1 1) North 0)
      returnToWall = movePlayer maze West 100
        (reverseActor (movePlayer maze East 1 (approach (At 1 1) North (-96))))
   in [ ("Corner limits match all four approach directions in the reference diagram",
          map preTurnLimit [East, West, South, North] == [96, 128, 128, 96] &&
          map postTurnLimit [East, West, South, North] == [128, 96, 96, 128])
      , ("Normal actor constructors keep a zero corner displacement", (MkActor junction East 7).offset == At 0 0)
      , ("Reversing during a diagonal turn preserves the physical position",
          actorPosition reversed == actorPosition late && reversed.offset == late.offset && reversed.heading == South)
      , ("Two reversals restore every field of an off-center player", sameActor (reverseActor reversed) late)
      , ("A reversed diagonal keeps correcting toward the centerline after crossing a tile center",
          sameActor home (MkActor junction South 64))
      , ("A second perpendicular turn waits for the current diagonal to align",
          pending.heading == North && pending.offset == At (-44) 0 && pending.progress == 52)
      , ("A queued turn starts as soon as the previous diagonal aligns",
          aligned.heading == East && aligned.progress == 0 && aligned.offset == At 0 (-96) &&
          actorPosition aligned == At (6 * 256) (5 * 256 - 96))
      , ("Straight motion still stops at a wall without creating a corner",
          wall.tile == At 12 1 && wall.progress == 0 && wall.offset == At 0 0)
      , ("The player can turn at an L-shaped junction", sameActor lCorner (MkActor (At 1 1) East 32))
      , ("A reversed corner finishes its alignment without entering a blocked exit",
          sameActor returnToWall (MkActor (At 1 1) West 0))
      , ("Tunnel wrapping keeps the remaining straight movement",
          sameActor tunnel (MkActor (At 27 14) West 16))
      , ("Player cornering ignores ghost-only upward-turn restrictions",
          noUp.heading == North && noUp.offset == At 96 0)
      , ("Hunters do not gain the player's early cornering",
          let ghost = MkGhost Red (approach junction East (-96)) Hunting False False Nothing
              moved = moveGhost quiet ghost
           in moved.actor.heading == East && moved.actor.offset == At 0 0)
      ]

advance : Nat -> Game -> Game
advance Z game = game
advance (S count) game = advance count (step game)

controlRules : List (String, Bool)
controlRules =
  let actor = movePlayer maze North 32 (approach junction East (-96))
      game = { player := actor, wanted := North } quiet
      frozen = advance 30 ({ freeze := 30 } game)
      ready = advance 30 ({ phase := Ready 30 } game)
      paused = advance 30 (command Pause game)
      unfocused = advance 30 (command LoseFocus game)
      stalled = advance 3 ({ stall := 3 } game)
      reversed = command (Turn South) game
      reset = [step ({ phase := Dying 1, lives := 2 } game), step ({ phase := Clearing 1 } game),
               command Start ({ phase := GameOver } game)]
   in [ ("Pause, focus loss, ready countdowns, and capture freezes hold the entire corner",
          all (\state => sameActor actor state.player) [frozen, ready, paused, unfocused])
      , ("Pellet stalls hold both components of diagonal movement", sameActor actor stalled.player)
      , ("Resumed motion uses the next fractional speed without discarding the corner",
          let resumed = step stalled
           in sameActor resumed.player (movePlayer maze North (speedStep (playerSpeed resumed) resumed.frame) actor))
      , ("An input reversal during a corner changes heading without moving the player",
          reversed.player.heading == South && actorPosition reversed.player == actorPosition actor)
      , ("Paused direction commands cannot change the corner or queued turn",
          sameActor paused.player (command (Turn South) paused).player && (command (Turn South) paused).wanted == North)
      , ("Death, new levels, and retry reset the corner displacement",
          all (\state => sameActor state.player newGame.player && state.wanted == West) reset)
      , ("Frightened speed applies independently to both axes of the diagonal",
          let powered = step ({ frightened := 100 } game)
              budget = speedStep 90 powered.frame
           in sameActor powered.player (expected junction East North (-96) (32 + budget)))
      ]

pelletRules : List (String, Bool)
pelletRules =
  let start = { player := approach junction East (-96), wanted := North,
                dots := singleton (key junction), remaining := 2 } quiet
      eaten = step start
      held = step eaten
      continued = advance 4 held
      powered = step ({ dots := empty, powers := singleton (key junction) } start)
      completed = step ({ remaining := 1 } start)
      counted = step ({ ghosts := filter (\g => g.identity == Cyan) newGame.ghosts } start)
   in [ ("Early turns collect the junction dot instead of skipping it",
          eaten.player.tile == junction && eaten.player.offset /= At 0 0 && eaten.score == 10 &&
          eaten.remaining == 1 && eaten.eaten == 1 && eaten.stall == 1 && not (contains (key junction) eaten.dots))
      , ("A corner dot causes exactly one stalled update", sameActor eaten.player held.player && held.stall == 0)
      , ("A collected junction dot cannot score twice while the player aligns", continued.score == 10 && continued.eaten == 1)
      , ("Power pellets start protection during a corner and stall three updates",
          powered.frightened == 360 && powered.score == 50 && powered.stall == 3 &&
          sameActor powered.player (advance 3 powered).player)
      , ("A corner pellet advances the waiting ghost's personal counter once",
          counted.release.cyanDots == 1 && (advance 4 counted).release.cyanDots == 1)
      , ("A final junction pellet ends the maze with the corner position intact",
          completed.player.offset /= At 0 0 && case completed.phase of Clearing 120 => True; _ => False)
      ]

collisionRules : List (String, Bool)
collisionRules =
  let actor : Actor = { offset := At (-96) 0 } (MkActor junction North 32)
      close = MkActor (At 5 5) East 10
      far = MkActor (At 7 5) West 120
      ghost = \pose => MkGhost Red pose Hunting False False Nothing
      game = { player := actor, wanted := North, stall := 1 } quiet
      hit = step ({ ghosts := [ghost close] } game)
      missed = step ({ ghosts := [ghost far] } game)
      captured = step ({ ghosts := [ghost close], frightened := 100 } game)
      fruitActor : Actor = { offset := At 96 0 } (MkActor (At 12 17) South 32)
      fruit = step ({ player := fruitActor, wanted := South, stall := 1, fruitTime := 100 } quiet)
   in [ ("Collision distance includes the player's diagonal displacement", touching actor close && not (touching actor far))
      , ("A nearby hunter can kill an off-center player", case hit.phase of Dying _ => True; _ => False)
      , ("A hunter near the projected track cannot hit a distant diagonal position", case missed.phase of Playing => True; _ => False)
      , ("Off-center frightened captures keep the player's position during the freeze",
          captured.freeze == 30 && captured.score == 200 && sameActor actor captured.player)
      , ("Fruit pickup uses the physical corner position rather than the projected track",
          fruit.score == 100 && fruit.fruitTime == 0 && elem FruitEaten fruit.sounds)
      ]

export
corneringTests : List (String, Bool)
corneringTests = movementRules ++
  concatMap (\incoming => concatMap (boundaryRules incoming) (filter (perpendicular incoming) directions)) directions ++
  concatMap layoutRules [1..5] ++ controlRules ++ pelletRules ++ collisionRules
