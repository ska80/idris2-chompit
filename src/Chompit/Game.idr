module Chompit.Game

import Chompit.Types
import Chompit.Maze

import Data.List
import Data.Maybe
import Data.SortedMap
import Data.SortedSet

%default total

public export
record Game where
  constructor MkGame
  maze : Maze
  dots, powers : SortedSet Int
  player : Actor
  wanted : Direction
  ghosts : List Ghost
  phase : Phase
  paused : Bool
  score, highScore, lives, level : Int
  extraLife : Bool
  remaining, eaten : Int
  frightened, chain, modeTicks, frame, stall, freeze : Int
  fruitTime, fruitStage : Int
  popup : Maybe (Tile, Int, Int)
  sounds : List Cue
  seed : Bits32

initialGhosts : List Ghost
initialGhosts =
  [ MkGhost Red (MkActor (At 13 11) West 0) Hunting False
  , MkGhost Pink (MkActor (At 13 14) North 0) (InPen 60) False
  , MkGhost Cyan (MkActor (At 11 14) North 0) (InPen 300) False
  , MkGhost Orange (MkActor (At 15 14) North 0) (InPen 540) False
  ]

export
newGame : Game
newGame =
  let maze = buildMaze
   in MkGame maze maze.pellets maze.energizers (MkActor (At 13 23) West 0) West
             initialGhosts Title False 0 0 3 1 False (pelletCount maze) 0
             0 0 0 0 0 0 0 0 Nothing [] 42

restartActors : Phase -> Game -> Game
restartActors phase game =
  { player := MkActor (At 13 23) West 0, wanted := West, ghosts := initialGhosts,
    phase := phase, paused := False, frightened := 0, chain := 0, modeTicks := 0,
    stall := 0, freeze := 0, fruitTime := 0, popup := Nothing } game

export
reverseActor : Actor -> Actor
reverseActor actor = if actor.progress == 0
  then { heading := opposite actor.heading } actor
  else MkActor (neighbor actor.tile actor.heading) (opposite actor.heading) (256 - actor.progress)

reverseGhost : Ghost -> Ghost
reverseGhost ghost = case ghost.state of
  Hunting => { actor := reverseActor ghost.actor } ghost
  _ => ghost

export
command : Command -> Game -> Game
command (Turn direction) game =
  let actor = if direction == opposite game.player.heading && game.player.progress > 0
                 then reverseActor game.player else game.player
   in if game.paused then game else { wanted := direction, player := actor } game
command Start game = case game.phase of
  Title => { highScore := game.highScore, phase := Ready 180, sounds := [BeginGame] } newGame
  GameOver => { highScore := game.highScore, phase := Ready 180, sounds := [BeginGame] } newGame
  _ => game
command Pause game = case game.phase of
  Title => game
  GameOver => game
  _ => { paused := not game.paused } game
command LoseFocus game = case game.phase of
  Title => game
  GameOver => game
  _ => { paused := True } game
command _ game = game

-- One update is 1/60 second. Speeds remain below one tile per update.
-- Decisions occur at centers. A blocked turn stays queued until it is legal.
export
moveActor : Maze -> Bool -> (Actor -> Direction) -> Int -> Actor -> Actor
moveActor maze house choose speed actor =
  let heading = if actor.progress == 0 then choose actor else actor.heading
      moving = { heading := heading } actor
   in if not (canMove maze house actor.tile heading) then { progress := 0 } moving
      else let progress = actor.progress + speed in
        if progress < 256 then { progress := progress } moving
        else let arrived = MkActor (neighbor actor.tile heading) heading 0
                 next = choose arrived
              in if canMove maze house arrived.tile next
                    then { heading := next, progress := progress - 256 } arrived
                    else arrived

playerDirection : Game -> Actor -> Direction
playerDirection game actor = if canMove game.maze False actor.tile game.wanted
  then game.wanted else actor.heading

export
isScatter : Int -> Bool
isScatter tick = tick < 420 || (tick >= 1620 && tick < 2040) ||
                 (tick >= 3240 && tick < 3540) || (tick >= 4740 && tick < 5040)

corner : Identity -> Tile
corner Red = At 25 (-3)
corner Pink = At 2 (-3)
corner Cyan = At 27 33
corner Orange = At 0 33

-- These targets reproduce the four familiar personalities. The original
-- upward look-ahead overflow is intentional, including the cyan target.
export
lookAhead : Int -> Actor -> Tile
lookAhead amount actor = if actor.heading == North
  then plus actor.tile (At (-amount) (-amount))
  else plus actor.tile (scaled amount (delta actor.heading))

export
chaseTarget : Game -> Ghost -> Tile
chaseTarget game ghost = case ghost.identity of
  Red => game.player.tile
  Pink => lookAhead 4 game.player
  Cyan =>
    let red = fromMaybe (At 13 11) (map (\g => g.actor.tile) (find (\g => g.identity == Red) game.ghosts))
     in plus (scaled 2 (lookAhead 2 game.player)) (scaled (-1) red)
  Orange => if distanceSquared ghost.actor.tile game.player.tile >= 64
               then game.player.tile else corner Orange

choices : Maze -> Bool -> Bool -> Actor -> List Direction
choices maze house reverse actor =
  let legal = filter (canMove maze house actor.tile) directions
      forward = filter (/= opposite actor.heading) legal
   in if reverse || null forward then legal else forward

best : (Direction -> Int) -> Direction -> List Direction -> Direction
best cost fallback [] = fallback
best cost fallback (first :: rest) =
  foldl (\winner, candidate => if cost candidate < cost winner then candidate else winner) first rest

pick : Nat -> List a -> Maybe a
pick _ [] = Nothing
pick Z (x :: _) = Just x
pick (S n) (_ :: xs) = pick n xs

export
isFrightened : Game -> Ghost -> Bool
isFrightened game ghost = case ghost.state of
  Hunting => game.frightened > 0 && not ghost.revived
  _ => False

ghostDirection : Game -> Ghost -> Actor -> Direction
ghostDirection game ghost actor = case ghost.state of
  Eyes => best (\d => fromMaybe 9999 (lookup (key (neighbor actor.tile d)) game.maze.homeDistances))
               actor.heading (choices game.maze True True actor)
  InPen _ => North
  Leaving => toward True (At 13 11)
  Hunting => if isFrightened game ghost
    then let available = choices game.maze False False actor
             index : Nat = cast ((game.seed + cast (key actor.tile)) `mod` cast (max 1 (length available)))
          in fromMaybe actor.heading (pick index available)
    else toward False (if isScatter game.modeTicks then corner ghost.identity else chaseTarget game ghost)
  where
    toward : Bool -> Tile -> Direction
    toward house target = best (\d => distanceSquared (neighbor actor.tile d) target)
                               actor.heading (choices game.maze house False actor)

ghostSpeed : Game -> Ghost -> Int
ghostSpeed game ghost = case ghost.state of
  Eyes => 88
  Leaving => 30
  InPen _ => 0
  Hunting => if isFrightened game ghost then 22
             else if ghost.actor.tile.y == 14 && (ghost.actor.tile.x < 6 || ghost.actor.tile.x > 21) then 22
             else min 50 (38 + (game.level - 1) * 2 +
                    (if ghost.identity == Red && game.remaining < 30 then 4 else 0))

moveGhost : Game -> Ghost -> Ghost
moveGhost game ghost = case ghost.state of
  InPen ticks => if ticks <= 1 then { state := Leaving } ghost
                 else { state := InPen (ticks - 1) } ghost
  Eyes => if ghost.actor.tile == At 13 14 then
            { actor := MkActor (At 13 14) North 0, state := InPen 90, revived := True } ghost
          else advance True ghost
  Leaving => if ghost.actor.tile == At 13 11 then
               { actor := MkActor (At 13 11) West 0, state := Hunting } ghost
             else advance True ghost
  Hunting => advance False ghost
  where
    advance : Bool -> Ghost -> Ghost
    advance house ghost = { actor := moveActor game.maze house (ghostDirection game ghost)
                                               (ghostSpeed game ghost) ghost.actor } ghost

export
actorPosition : Actor -> Tile
actorPosition actor = plus (scaled 256 actor.tile) (scaled actor.progress (delta actor.heading))

export
touching : Actor -> Actor -> Bool
touching first second =
  let a = actorPosition first
      b = actorPosition second
      dx = abs (a.x - b.x)
      wrapped = min dx (7168 - dx)
      dy = a.y - b.y
   in wrapped * wrapped + dy * dy < 180 * 180

addCue : Cue -> Game -> Game
addCue cue game = { sounds := game.sounds ++ [cue] } game

export
addScore : Int -> Game -> Game
addScore points game =
  let score = game.score + points
      bonus = not game.extraLife && score >= 10000
      updated : Game = { score := score, highScore := max score game.highScore,
                  extraLife := game.extraLife || bonus,
                  lives := game.lives + (if bonus then 1 else 0) } game
   in if bonus then addCue BonusLife updated else updated

export
frightDuration : Int -> Int
frightDuration level = fromMaybe 0 (pick (cast (max 0 (level - 1)))
  [360, 300, 240, 180, 120, 300, 120, 120, 60, 300, 120, 60, 60, 180, 60, 60, 0, 60])

export
fruitValue : Int -> Int
fruitValue level = fromMaybe 5000 (pick (cast (max 0 (level - 1)))
  [100, 300, 500, 500, 700, 700, 1000, 1000, 2000, 2000, 3000, 3000])

energizeGhost : Ghost -> Ghost
energizeGhost ghost = case ghost.state of
  Eyes => ghost
  _ => reverseGhost ({ revived := False } ghost)

consume : Game -> Game
consume game =
  let here = key game.player.tile
      dot = contains here game.dots
      power = contains here game.powers
      chomp = if game.eaten `mod` 2 == 0 then ChompLow else ChompHigh
      ate = if dot || power
        then addCue (if power then Energize else chomp) $ addScore (if power then 50 else 10)
          ({ dots := delete here game.dots, powers := delete here game.powers,
             remaining := game.remaining - 1, eaten := game.eaten + 1,
             stall := if power then 3 else 1 } game)
        else game
      energized = if power then { frightened := frightDuration game.level, chain := 0,
                                   ghosts := map energizeGhost ate.ghosts } ate else ate
      spawn = (energized.eaten >= 70 && energized.fruitStage == 0) ||
              (energized.eaten >= 170 && energized.fruitStage == 1)
      fruit = if spawn then { fruitTime := 600, fruitStage := energized.fruitStage + 1 } energized
              else energized
   in if fruit.fruitTime > 0 && touching fruit.player (MkActor (At 13 17) West 0)
        then addCue FruitEaten $ addScore (fruitValue fruit.level)
          ({ fruitTime := 0, popup := Just (At 13 17, fruitValue fruit.level, 90) } fruit)
        else fruit

collisions : Game -> Game
collisions game = resolve game.ghosts [] game
  where
    resolve : List Ghost -> List Ghost -> Game -> Game
    resolve [] done state = { ghosts := reverse done } state
    resolve (ghost :: rest) done state = case ghost.state of
      Hunting => if not (touching state.player ghost.actor) then resolve rest (ghost :: done) state
        else if isFrightened state ghost then
          let points = fromMaybe 1600 (pick (cast state.chain) [200, 400, 800, 1600])
              eaten : Ghost = { state := Eyes } ghost
              scored = addCue GhostEaten $ addScore points
                ({ chain := state.chain + 1, freeze := 30,
                   popup := Just (ghost.actor.tile, points, 90) } state)
           in resolve rest (eaten :: done) scored
        else addCue PlayerDied ({ phase := Dying 90, frightened := 0,
                                  ghosts := reverse done ++ ghost :: rest } state)
      _ => resolve rest (ghost :: done) state

countPopup : Maybe (Tile, Int, Int) -> Maybe (Tile, Int, Int)
countPopup Nothing = Nothing
countPopup (Just (tile, value, ticks)) = if ticks <= 1 then Nothing else Just (tile, value, ticks - 1)

playTick : Game -> Game
playTick game =
  if game.freeze > 0 then { freeze := game.freeze - 1 } game else
    let mode = if game.frightened > 0 then game.modeTicks else game.modeTicks + 1
        ghosts = if isScatter mode /= isScatter game.modeTicks then map reverseGhost game.ghosts else game.ghosts
        timed = { frightened := max 0 (game.frightened - 1), modeTicks := mode,
                  fruitTime := max 0 (game.fruitTime - 1), ghosts := ghosts,
                  popup := countPopup game.popup, seed := game.seed * 1664525 + 1013904223 } game
        speed = min 54 (40 + (game.level - 1) * 2 + (if game.frightened > 0 then 4 else 0))
        moved = if game.stall > 0 then { stall := game.stall - 1 } timed
                else { player := moveActor game.maze False (playerDirection game) speed game.player } timed
        ate = consume moved
        advanced = { ghosts := map (moveGhost ate) ate.ghosts } ate
        hit = collisions advanced
     in case hit.phase of
          Playing => if hit.remaining == 0 then addCue LevelWon ({ phase := Clearing 120, frightened := 0 } hit) else hit
          _ => hit

export
step : Game -> Game
step game = if game.paused then game else
  let next = { frame := game.frame + 1 } game in case game.phase of
    Title => next
    GameOver => next
    Ready ticks => { phase := if ticks <= 1 then Playing else Ready (ticks - 1) } next
    Playing => playTick next
    Dying ticks => if ticks > 1 then { phase := Dying (ticks - 1) } next
                   else if game.lives <= 1 then { phase := GameOver, lives := 0 } next
                   else restartActors (Ready 120) ({ lives := game.lives - 1 } next)
    Clearing ticks => if ticks > 1 then { phase := Clearing (ticks - 1) } next
      else restartActors (Ready 120)
        ({ dots := game.maze.pellets, powers := game.maze.energizers,
           remaining := pelletCount game.maze, eaten := 0, level := game.level + 1,
           fruitStage := 0 } next)

-- Drop excess wall-clock time after a stall. At most six fixed updates/frame.
export
accumulate : Double -> Double -> (Nat, Double)
accumulate previous elapsed =
  let time = previous + max 0 (min 0.1 elapsed)
      count : Int = min 6 (cast (floor (time * 60)))
   in (cast count, max 0 (time - cast count / 60))
