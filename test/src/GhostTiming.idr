module GhostTiming

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

quiet : Game
quiet = { phase := Playing, player := MkActor (At 13 23) North 0, wanted := North,
          ghosts := [], dots := empty, powers := empty, modeTicks := 100 } newGame

hunter : Actor -> Ghost
hunter actor = MkGhost Red actor Hunting False False

sameActor : Actor -> Actor -> Bool
sameActor a b = a.tile == b.tile && a.heading == b.heading && a.progress == b.progress

validActor : Maze -> Actor -> Bool
validActor maze actor = walkable maze False actor.tile && actor.progress >= 0 && actor.progress < 256 &&
  (actor.progress == 0 || canMove maze False actor.tile actor.heading)

hasGhost : (Ghost -> Bool) -> Game -> Bool
hasGhost predicate game = maybe False predicate (head' game.ghosts)

signalRules : List (String, Bool)
signalRules =
  let ghost = hunter (MkActor (At 12 11) East 100)
      signaled = requestReverse ghost
      repeated = requestReverse signaled
      moved = moveGhost quiet repeated
      eyes = { state := Eyes, reversePending := True } ghost
      eyeCenter = moveGhost quiet (MkGhost Red (MkActor (At 13 11) West 0) Eyes False False)
      house = requestReverse ({ state := InPen West } ghost)
      leaving = requestReverse ({ state := Leaving West } ghost)
   in [ ("Requesting a reversal does not move or turn the ghost",
         signaled.reversePending && sameActor signaled.actor ghost.actor)
      , ("Repeated requests share one pending reversal",
         repeated.reversePending && sameActor repeated.actor signaled.actor &&
         moved.reversePending && moved.actor.heading == East)
      , ("A pending ghost keeps moving until the next center",
         moved.actor.tile == ghost.actor.tile && moved.actor.progress == 100 + ghostSpeed quiet ghost)
      , ("Waiting ghosts remember an eastward exit instead of a corridor reversal",
         not house.reversePending && case house.state of InPen East => True; _ => False)
      , ("Leaving ghosts also remember an eastward exit",
         not leaving.reversePending && case leaving.state of Leaving East => True; _ => False)
      , ("Returning eyes ignore reversal requests", not (requestReverse eyes).reversePending)
      , ("Eye movement discards any stale pending request", not (moveGhost quiet eyes).reversePending)
      , ("Eyes at a center choose the shortest route instead of keeping a hunting heading",
         eyeCenter.actor.heading == South && eyeCenter.actor.progress == 88)
      ]

centerRules : List (String, Bool)
centerRules =
  let game = { modeTicks := 500, player := MkActor (At 6 1) North 0 } quiet
      ghost = hunter (MkActor (At 5 5) East 0)
      speed = ghostSpeed game ghost
      exact = requestReverse ({ actor := { progress := 256 - speed } ghost.actor } ghost)
      arrived = moveGhost game exact
      departed = moveGhost game arrived
      overshoot = moveGhost game (requestReverse ({ actor := { progress := 250 } ghost.actor } ghost))
      atCenter = moveGhost game (requestReverse ghost)
      again = moveGhost game (requestReverse overshoot)
      normal = moveGhost game ({ reversePending := False } exact)
      changedTarget = moveGhost ({ player := MkActor (At 26 5) East 0 } game) normal
   in [ ("A request at a center waits for the following center",
         atCenter.reversePending && atCenter.actor.tile == At 5 5 &&
         atCenter.actor.heading == East && atCenter.actor.progress == speed)
      , ("Arrival reverses the incoming direction before choosing a junction turn",
         arrived.actor.tile == At 6 5 && arrived.actor.heading == West && arrived.actor.progress == 0 &&
         not arrived.reversePending && ghostDirection game arrived arrived.actor == North)
      , ("An exact-center reversal remains committed on the next update",
         departed.actor.tile == At 6 5 && departed.actor.heading == West && departed.actor.progress == speed)
      , ("A reversal spends the movement remainder in the new direction",
         overshoot.actor.tile == At 6 5 && overshoot.actor.heading == West &&
         overshoot.actor.progress == 250 + speed - 256 && not overshoot.reversePending)
      , ("A new request after a reversal waits for another arrival",
         again.reversePending && again.actor.heading == West && again.actor.tile == At 6 5 &&
         again.actor.progress == overshoot.actor.progress + speed)
      , ("Ordinary junction choices also stay committed when the remainder is zero",
         normal.actor.heading == North && normal.actor.progress == 0 &&
         changedTarget.actor.heading == North && changedTarget.actor.progress == speed)
      ]

boundaryStep : Game -> Tile -> Direction -> Int -> Bool
boundaryStep game tile heading progress =
  let ghost = requestReverse (hunter (MkActor tile heading progress))
      speed = ghostSpeed game ghost
      moved = moveGhost game ghost
      crossed = progress + speed >= 256
      nextGame : Game = { frame := game.frame + 1 } game
      after = moveGhost nextGame moved
      committed = not crossed || moved.actor.progress /= 0 ||
        (sameActor after.actor (MkActor moved.actor.tile moved.actor.heading (ghostSpeed nextGame moved)))
   in committed && validActor game.maze moved.actor &&
      moved.actor.tile == (if crossed then neighbor tile heading else tile) &&
      moved.actor.heading == (if crossed then opposite heading else heading) &&
      moved.actor.progress == (if crossed then progress + speed - 256 else progress + speed) &&
      moved.reversePending == not crossed

layoutReversals : Int -> Bool
layoutReversals level =
  let maze = buildMaze level
      normal = { level := level, maze := maze } quiet
      variants = [normal, { frightened := 120 } normal, { remaining := 10 } normal]
   in all (\base => all (\frame =>
        let game : Game = { frame := frame } base
         in all (\tile => all (\heading =>
              let speed = ghostSpeed game (hunter (MkActor tile heading 0))
               in not (canMove maze False tile heading) ||
                  all (boundaryStep game tile heading) [0, 1, 120, 128, 255 - speed, 256 - speed, 240, 255]) directions)
              (filter (walkable maze False) allTiles)) (the (List Int) [0, 1, 42, 98])) variants

specialReversals : List (String, Bool)
specialReversals =
  let up = moveGhost quiet (requestReverse (hunter (MkActor (At 12 22) South 250)))
      left = moveGhost quiet (requestReverse (hunter (MkActor (At 0 14) West 250)))
      right = moveGhost quiet (requestReverse (hunter (MkActor (At 27 14) East 250)))
      blocked = moveGhost quiet (requestReverse (hunter (MkActor (At 1 1) North 0)))
   in [ ("Forced reversals can point up at a restricted junction",
         restrictedUp quiet.maze up.actor.tile && up.actor.tile == At 12 23 &&
         up.actor.heading == North && not up.reversePending)
      , ("West tunnel reversals preserve wraparound",
         left.actor.tile == At 27 14 && left.actor.heading == East && not left.reversePending &&
         left.actor.progress == 250 + speedStep 40 quiet.frame - 256)
      , ("East tunnel reversals preserve wraparound",
         right.actor.tile == At 0 14 && right.actor.heading == West && not right.reversePending &&
         right.actor.progress == 250 + speedStep 40 quiet.frame - 256)
      , ("A blocked initial heading selects a legal route before reversing",
         validActor quiet.maze blocked.actor && blocked.actor.progress > 0 && blocked.reversePending)
      ] ++ map (\level => ("Layout " ++ show level ++ ": reversal positions, remainders, and directions stay legal", layoutReversals level)) [1..5]

lifecycleRules : List (String, Bool)
lifecycleRules =
  let ghost = requestReverse (hunter (MkActor (At 12 11) East 120))
      game = { ghosts := [ghost] } quiet
      paused = advance 100 (command Pause game)
      unfocused = advance 100 (command LoseFocus game)
      frozen = advance 30 ({ freeze := 30 } game)
      captured = step ({ frightened := 60, stall := 1,
                         ghosts := [requestReverse (hunter quiet.player)] } quiet)
      eyes = moveGhost quiet (MkGhost Red (MkActor (At 13 14) North 0) Eyes False True)
      died = step ({ phase := Dying 1, lives := 2 } game)
      loaded = step ({ phase := Clearing 1 } game)
      retried = command Start ({ phase := GameOver } game)
   in [ ("Pause and focus loss hold a pending reversal at the same position",
         all (hasGhost (\g => g.reversePending && sameActor g.actor ghost.actor)) [paused, unfocused])
      , ("Capture freezes do not consume pending reversals",
         hasGhost (\g => g.reversePending && sameActor g.actor ghost.actor) frozen)
      , ("Movement resumes with the request still pending",
         hasGhost (\g => g.reversePending && g.actor.progress > ghost.actor.progress) (step frozen))
      , ("Capture clears the eaten ghost's reversal request",
         hasGhost (\g => not g.reversePending && case g.state of Eyes => True; _ => False) captured)
      , ("Returning eyes cannot carry a request through revival",
         not eyes.reversePending && eyes.revived && case eyes.state of InPen _ => True; _ => False)
      , ("Death, level changes, and retry reset all pending reversals",
         all (\state => all (not . reversePending) state.ghosts) [died, loaded, retried])
      ]

modeRules : List (String, Bool)
modeRules =
  let early = hunter (MkActor (At 12 11) East 250)
      late = MkGhost Pink (MkActor (At 15 11) East 0) Hunting False False
      changed = step ({ modeTicks := 419, ghosts := [early, late] } quiet)
      firstPulse = step ({ level := 2, modeTicks := 65519, ghosts := [early] } quiet)
      secondPulse = step firstPulse
      expired = step ({ frightened := 1, ghosts := [hunter (MkActor (At 12 11) East 100)] } quiet)
      pendingExpiry = step ({ frightened := 1,
                             ghosts := [requestReverse (hunter (MkActor (At 12 11) East 100))] } quiet)
      simultaneous = step ({ level := 19, modeTicks := 299, stall := 1,
                             player := MkActor (At 1 3) North 0, wanted := North,
                             powers := singleton (key (At 1 3)),
                             ghosts := [hunter (MkActor (At 12 11) East 100)] } quiet)
   in [ ("The same mode change reverses ghosts on different updates",
         case changed.ghosts of
           [first, second] => first.actor.heading == West && not first.reversePending &&
                              second.actor.heading == East && second.reversePending
           _ => False)
      , ("Successive mode requests reverse twice when an arrival separates them",
         hasGhost (\g => g.actor.heading == West && not g.reversePending) firstPulse &&
         hasGhost (\g => g.actor.heading == West && g.reversePending) secondPulse &&
         hasGhost (\g => g.actor.heading == East && not g.reversePending) (advance 7 secondPulse))
      , ("Frightened expiry does not request a reversal",
         expired.frightened == 0 && hasGhost (\g => not g.reversePending && g.actor.heading == East) expired)
      , ("Frightened expiry does not discard an existing request",
         hasGhost (\g => g.reversePending && g.actor.heading == East) pendingExpiry)
      , ("A mode change and zero-duration energizer share one pending request",
         simultaneous.frightened == 0 && simultaneous.modeTicks == 300 &&
         hasGhost (\g => g.reversePending && g.actor.heading == East) simultaneous &&
         hasGhost (\g => not g.reversePending && g.actor.heading == West) (advance 4 simultaneous))
      ]

whiteRuns : List Bool -> Int
whiteRuns colors = snd (foldl (\(previous, count), white =>
  (white, count + if white && not previous then 1 else 0)) (False, 0) colors)

colors : Int -> List Bool
colors level =
  let times : List Int = reverse [1..frightDuration level]
      game = { level := level } quiet
      ghost = hunter (MkActor (At 12 11) East 0)
   in map (\ticks => isFlashing ({ frightened := ticks } game) ghost) times

flashTable : List (String, Bool)
flashTable =
  [ ("Frightened flash counts match every level",
      map frightFlashes [1..21] == [5, 5, 5, 5, 5, 5, 5, 5, 3, 5, 5, 3, 3, 5, 3, 3, 0, 3, 0, 0, 0])
  , ("Nonpositive flash requests use level one and later levels have no flashes",
      frightFlashes 0 == 5 && frightFlashes (-1) == 5 && frightFlashes 100 == 0)
  , ("One-second protection begins with a four-update white interval",
      length (takeWhile id (colors 9)) == 4 && frightDuration 9 == 60)
  , ("Two-second protection begins with an eight-update white interval",
      length (takeWhile id (colors 5)) == 8 && frightDuration 5 == 120)
  ] ++ map (\level => ("Level " ++ show level ++ ": the complete warning contains the scheduled number of white flashes",
                       whiteRuns (colors level) == frightFlashes level)) [1..21]

flashTiming : List (String, Bool)
flashTiming =
  let ghost = hunter (MkActor (At 12 11) East 0)
      white = \ticks => isFlashing ({ frightened := ticks } quiet) ghost
      before = { frightened := 15 } quiet
      paused = advance 100 (command Pause before)
      resumed = step (command Pause paused)
      frozen = advance 30 ({ frightened := 14, freeze := 30 } quiet)
      expired = advance 14 frozen
   in [ ("White intervals last fourteen updates and end at protection expiry",
         all (\(low, high) => all white [low..high] && not (white (high + 1)) && not (white (low - 1)))
           [(1, 14), (29, 42), (57, 70), (85, 98), (113, 126)])
      , ("Long protection begins blue", not (white 360) && not (white 140) && not (white 127))
      , ("Expired protection never flashes", not (white 0) && not (white (-1)))
      , ("Flash colors do not depend on the global animation frame",
         all (\ticks => all (\frame => isFlashing ({ frightened := ticks, frame := frame } quiet) ghost == white ticks)
           (the (List Int) [0, 7, 999])) (the (List Int) [1, 14, 15, 28, 29, 126, 127]))
      , ("Pause holds a blue interval and resume reaches the next white interval",
         paused.frightened == 15 && not (isFlashing paused ghost) && resumed.frightened == 14 && isFlashing resumed ghost)
      , ("Capture freezes hold white even while the global frame advances",
         frozen.frame == quiet.frame + 30 && frozen.frightened == 14 && isFlashing frozen ghost)
      , ("The final white interval does not lengthen power-pellet protection",
         expired.frightened == 0 && not (isFlashing expired ghost))
      , ("White and blue intervals keep the same music and warning loops",
         loopChanges before resumed == ([], []))
      ]

powerRefresh : Int -> Bool
powerRefresh level =
  let game = { level := level, frightened := 14, frame := 999, stall := 1,
               player := MkActor (At 1 3) North 0, wanted := North,
               powers := singleton (key (At 1 3)),
               ghosts := [hunter (MkActor (At 12 11) East 0)] } quiet
      refreshed = step game
   in refreshed.frightened == frightDuration level &&
      hasGhost (\g => isFlashing refreshed g == isFlashing ({ frightened := frightDuration level } game) g) refreshed

flashStates : List (String, Bool)
flashStates =
  let game = { frightened := 14 } quiet
      ghost = hunter (MkActor (At 12 11) East 0)
      waiting = { state := InPen West } ghost
      leaving = { state := Leaving West } ghost
      eyes = { state := Eyes } ghost
      revived = { revived := True } ghost
      returned = moveGhost game (MkGhost Red (MkActor (At 13 14) North 0) Eyes False True)
   in [ ("Frightened bodies in the maze and house use the same warning color",
         all (isFlashing game) [ghost, waiting, leaving])
      , ("Eyes and revived bodies do not flash",
         all (not . isFlashing game) [eyes, revived, { revived := True } waiting, returned])
      , ("A fresh power pellet restarts the level's warning sequence",
         all powerRefresh [1, 5, 9, 18, 19])
      , ("Levels without frightened time do not display warning flashes",
         all (\level => not (isFlashing ({ level := level } game) ghost)) (the (List Int) [17, 19, 21, 100]))
      ]

export
ghostTimingTests : List (String, Bool)
ghostTimingTests = signalRules ++ centerRules ++ specialReversals ++ lifecycleRules ++ modeRules ++
                   flashTable ++ flashTiming ++ flashStates
