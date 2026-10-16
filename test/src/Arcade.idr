module Arcade

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

-- An empty spawn tile keeps release tests independent of the player's route.
idleGame : Game
idleGame = { phase := Playing, player := MkActor (At 13 23) North 0, wanted := North,
             dots := empty, powers := empty } newGame

hasGhost : Identity -> (Ghost -> Bool) -> Game -> Bool
hasGhost identity predicate game = any (\g => g.identity == identity && predicate g) game.ghosts

waiting : Identity -> Game -> Bool
waiting identity = hasGhost identity (\g => case g.state of InPen _ => True; _ => False)

leaving : Identity -> Game -> Bool
leaving identity = hasGhost identity (\g => case g.state of Leaving _ => True; _ => False)

-- Synthetic pellet frames isolate counter thresholds from maze navigation.
eatDot : Game -> Game
eatDot game = step ({ player := MkActor (At 1 1) North 0, wanted := North, stall := 1,
                      dots := singleton (key (At 1 1)), powers := empty, remaining := 244 } game)

eatPower : Game -> Game
eatPower game = step ({ player := MkActor (At 1 3) North 0, wanted := North, stall := 1,
                        dots := empty, powers := singleton (key (At 1 3)), remaining := 244 } game)

feed : Nat -> Game -> Game
feed Z game = game
feed (S count) game = feed count (eatDot game)

cycleDistance : Game -> Ghost -> Int
cycleDistance game ghost = sum (map (\frame => ghostSpeed ({ frame := frame } game) ghost) (the (List Int) [0..98]))

speedTests : (Int, Int, Int, Int, Int, Int) -> List (String, Bool)
speedTests (level, player, powered, normal, scared, tunnel) =
  let game = { level := level } idleGame
      fright = { frightened := frightDuration level } game
      ghost = MkGhost Red (MkActor (At 12 11) East 0) Hunting False False Nothing
      inTunnel = { actor := MkActor (At 5 14) West 0 } ghost
      moved = step ({ player := MkActor (At 0 14) West 0, wanted := West, ghosts := [] } game)
      advanced = step ({ ghosts := [ghost] } game)
      label = "Speed table, level " ++ show level ++ ": "
   in [ (label ++ "player percentages", playerSpeed game == player && playerSpeed fright == powered)
      , (label ++ "active play uses the player speed even in tunnels",
         moved.player.progress == speedStep player moved.frame)
      , (label ++ "active play uses the normal ghost speed",
         hasGhost Red (\g => g.actor.progress == speedStep normal advanced.frame) advanced)
      , (label ++ "all four normal ghost percentages",
         all (\identity => huntingSpeed game identity == normal) [Red, Pink, Cyan, Orange])
      , (label ++ "normal ghost distance", cycleDistance game ghost == normal * 40)
      , (label ++ "ghost distance after an energizer", cycleDistance fright ghost == scared * 40)
      , (label ++ "revived ghosts keep normal speed",
         cycleDistance fright ({ revived := True } ghost) == normal * 40)
      , (label ++ "both tunnel entrances slow ghosts",
         all (\x => cycleDistance game ({ actor := MkActor (At x 14) West 0 } ghost) == tunnel * 40)
           (the (List Int) [0, 5, 22, 27]))
      , (label ++ "tunnel speed overrides frightened speed", cycleDistance fright inTunnel == tunnel * 40)
      , (label ++ "the adjacent corridor keeps normal speed",
         all (\x => cycleDistance game ({ actor := MkActor (At x 14) West 0 } ghost) == normal * 40) (the (List Int) [6, 21]))
      ]

speedRules : List (String, Bool)
speedRules =
  let dot = eatDot ({ ghosts := [] } idleGame)
      dotWait = step dot
      power = eatPower ({ ghosts := [] } idleGame)
      powerWait = advance 3 power
      noProtection = eatPower ({ level := 21, ghosts := [] } idleGame)
   in concatMap speedTests
        [(1, 80, 90, 75, 50, 40), (2, 90, 95, 85, 55, 45), (4, 90, 95, 85, 55, 45),
         (5, 100, 100, 95, 60, 50), (18, 100, 100, 95, 60, 50), (21, 90, 90, 95, 95, 50)] ++
      [ ("Fractional speeds preserve the reference average over any 99 updates",
         all (\percent => all (\start => sum (map (speedStep percent) [start..start + 98]) == 40 * percent)
           [0, 97, 500]) [40, 45, 50, 55, 60, 75, 80, 85, 90, 95, 100, 105])
      , ("Every scheduled movement step stays below one tile",
         all (\percent => all (\frame => let amount = speedStep percent frame in amount > 0 && amount < 256)
           [0..98]) [40, 45, 50, 55, 60, 75, 80, 85, 90, 95, 100, 105])
      , ("Dot eating stops the player for one update",
         dot.stall == 1 && dotWait.stall == 0 && actorPosition dot.player == actorPosition dotWait.player)
      , ("Power pellets stop the player for three updates",
         power.stall == 3 && (advance 2 power).stall == 1 && powerWait.stall == 0 &&
         actorPosition power.player == actorPosition powerWait.player)
      , ("The player slows again at level 21",
         playerSpeed ({ level := 20 } idleGame) == 100 && playerSpeed noProtection == 90 &&
         noProtection.frightened == 0 && playerSpeed ({ level := 100 } idleGame) == 90)
      ]

scheduleTests : Int -> List Int -> List (String, Bool)
scheduleTests level boundaries =
  let expected = zip boundaries [False, True, False, True, False, True, False]
      label = "Mode schedule, level " ++ show level ++ ": "
   in [ (label ++ "every scatter and chase boundary",
         all (\(tick, scatter) => isScatter level tick == scatter &&
                                  isScatter level (tick - 1) /= scatter) expected)
      , (label ++ "starts in scatter and ends in permanent chase",
         isScatter level 0 && not (isScatter level 1000000))
      ]

scheduleRules : List (String, Bool)
scheduleRules =
  let ghost = MkGhost Red (MkActor (At 12 11) East 120) Hunting False False Nothing
      game = { level := 2, modeTicks := 65519, ghosts := [ghost] } idleGame
      pulse = step game
      chase = step pulse
      frozen = advance 2 ({ frightened := 2 } game)
      zero = eatPower ({ level := 19, ghosts := [ghost] } idleGame)
      afterZero = step zero
   in concatMap (\level => scheduleTests level [420, 1620, 2040, 3240, 3540, 65520, 65521]) [2, 3, 4] ++
      concatMap (\level => scheduleTests level [300, 1500, 1800, 3000, 3300, 65520, 65521]) [5, 21, 100] ++
      scheduleTests 1 [420, 1620, 2040, 3240, 3540, 4740, 5040] ++
      [ ("The later fourth scatter sends two requests that can share one reversal",
         pulse.modeTicks == 65520 && hasGhost Red (\g => g.reversePending && g.actor.heading == East) pulse &&
         chase.modeTicks == 65521 && hasGhost Red (\g => g.reversePending && g.actor.heading == East) chase &&
         hasGhost Red (\g => not g.reversePending && g.actor.heading == West) (advance 4 chase))
      , ("The permanent chase clock stops increasing", (advance 100 chase).modeTicks == 65521)
      , ("Frightened time holds a pending mode boundary without an expiry reversal",
         frozen.modeTicks == 65519 && frozen.frightened == 0 &&
         hasGhost Red (\g => g.actor.heading == East) frozen && (step frozen).modeTicks == 65520)
      , ("Zero-duration power pellets still request a reversal without pausing the mode clock",
         zero.frightened == 0 && hasGhost Red (\g => g.reversePending && g.actor.heading == East) zero &&
         hasGhost Red (\g => not g.reversePending && g.actor.heading == West) (advance 4 zero) &&
         afterZero.modeTicks == zero.modeTicks + 1)
      , ("The complete frightened-duration table includes the late exceptions",
         map frightDuration [1..21] ==
           [360, 300, 240, 180, 120, 300, 120, 120, 60, 300, 120, 60, 60, 180, 60, 60, 0, 60, 0, 0, 0])
      ]

personalRules : List (String, Bool)
personalRules =
  let start = step idleGame
      cyan29 = feed 29 start
      cyan30 = eatDot cyan29
      orange59 = feed 59 cyan30
      orange60 = eatDot orange59
      powered = eatPower start
   in [ ("Personal release limits match the level table",
         map (\level => map (releaseLimit level) [Pink, Cyan, Orange]) [1, 2, 3, 21] ==
           [[0, 30, 60], [0, 0, 50], [0, 0, 0], [0, 0, 0]])
      , ("Pink leaves immediately while cyan and orange wait at level one",
         leaving Pink start && waiting Cyan start && waiting Orange start && start.release.cyanDots == 0)
      , ("The first dot counts for cyan, not the zero-limit pink ghost",
         (eatDot idleGame).release.cyanDots == 1 && (eatDot idleGame).release.pinkDots == 0)
      , ("Counter priority does not depend on ghost list order",
         (eatDot ({ ghosts := reverse idleGame.ghosts } idleGame)).release.cyanDots == 1)
      , ("Cyan leaves on its thirtieth dot",
         waiting Cyan cyan29 && cyan29.release.cyanDots == 29 && leaving Cyan cyan30 &&
         cyan30.release.cyanDots == 30 && cyan30.release.orangeDots == 0)
      , ("Orange counts only dots eaten after cyan leaves",
         waiting Orange orange59 && orange59.release.orangeDots == 59 && leaving Orange orange60 &&
         orange60.release.orangeDots == 60 && orange60.release.cyanDots == 30)
      , ("Level two releases pink and cyan before counting for orange",
         let game = eatDot ({ level := 2 } idleGame) in leaving Pink game && leaving Cyan game &&
         waiting Orange game && game.release.orangeDots == 1)
      , ("Level two releases orange on its fiftieth personal dot",
         let game = feed 49 ({ level := 2 } idleGame) in waiting Orange game && leaving Orange (eatDot game))
      , ("All three waiting ghosts have zero limits from level three",
         let game = step ({ level := 3 } idleGame) in all (\identity => leaving identity game) [Pink, Cyan, Orange])
      , ("Power pellets count toward personal release and reset the idle timer",
         powered.release.cyanDots == 1 && powered.release.idleTicks == 0)
      ]

respawn : Game
respawn = step ({ phase := Dying 1,
                  release := MkReleaseCounters 0 12 3 Nothing 90 False, seed := 123 } idleGame)

globalAt : Nat -> Game
globalAt count = feed count ({ phase := Playing } respawn)

globalRules : List (String, Bool)
globalRules =
  let global31 = globalAt 31
      global32 = eatDot global31
      personalAgain = eatDot global32
   in [ ("The global counter releases pink at seven and cyan at seventeen",
         waiting Pink (globalAt 6) && leaving Pink (globalAt 7) &&
         waiting Cyan (globalAt 16) && leaving Cyan (globalAt 17))
      , ("Global counting leaves personal counts unchanged",
         global31.release.cyanDots == 12 && global31.release.orangeDots == 3 && global31.release.globalDots == Just 31)
      , ("Power pellets also count toward global release", (eatPower (globalAt 0)).release.globalDots == Just 1)
      , ("At 32, waiting orange restores personal limits rather than bypassing them",
         global32.release.globalDots == Nothing && waiting Orange global32 &&
         personalAgain.release.orangeDots == 4 && waiting Orange personalAgain)
      , ("Pause holds the house clocks and counters",
         let game = advance 300 (command Pause (globalAt 16)) in game.release.globalDots == Just 16 &&
         game.release.idleTicks == 0 && waiting Cyan game)
      ]

idleRules : List (String, Bool)
idleRules =
  let global = globalAt 0
      beforeIdle = advance 239 global
      forced = step beforeIdle
      fastBefore = advance 179 ({ level := 5 } global)
      fedAtDeadline = eatDot ({ release := { idleTicks := 239 } global.release } global)
      emptyHouse = advance 240 ({ ghosts := [] } idleGame)
      lateReturn = step ({ ghosts := [MkGhost Cyan (MkActor (At 13 14) North 0) (InPen West) True False Nothing] } emptyHouse)
   in [ ("The idle timeout releases the preferred ghost at exactly four seconds",
         waiting Pink beforeIdle && beforeIdle.release.idleTicks == 239 && leaving Pink forced &&
         forced.release.idleTicks == 0 && forced.release.globalDots == Just 0 && waiting Cyan forced)
      , ("The idle timeout falls to three seconds at level five",
         waiting Pink fastBefore && leaving Pink (step fastBefore) &&
         releaseTimeout 4 == 240 && releaseTimeout 5 == 180)
      , ("A pellet on the timeout update prevents a forced release",
         waiting Pink fedAtDeadline && fedAtDeadline.release.globalDots == Just 1 && fedAtDeadline.release.idleTicks == 0)
      , ("The idle timer keeps running while the house is empty",
         emptyHouse.release.idleTicks == 240 && leaving Cyan lateReturn && lateReturn.release.idleTicks == 0)
      , ("Capture freezes also hold the house timer",
         (advance 10 ({ freeze := 10, release := { idleTicks := 99 } idleGame.release } idleGame)).release.idleTicks == 99)
      , ("Ready countdowns do not release ghosts or advance the house timer",
         let game = step ({ phase := Ready 1 } global) in waiting Pink game && game.release.idleTicks == 0)
      ]

resetRules : List (String, Bool)
resetRules =
  let next = step ({ phase := Clearing 1 } respawn)
      retry = command Start ({ phase := GameOver } respawn)
   in [ ("Death enables a fresh global counter and keeps personal counts",
         respawn.release.globalDots == Just 0 && respawn.release.cyanDots == 12 &&
         respawn.release.orangeDots == 3 && respawn.release.idleTicks == 0 && respawn.release.elroyWaiting)
      , ("Death resets the mode clock and frightened random sequence",
         respawn.modeTicks == 0 && respawn.seed == 42)
      , ("The next level resets every release counter and restores Elroy",
         next.release.pinkDots == 0 && next.release.cyanDots == 0 && next.release.orangeDots == 0 &&
         next.release.globalDots == Nothing && next.release.idleTicks == 0 && not next.release.elroyWaiting)
      , ("Retry resets release counters and the random sequence",
         retry.release.globalDots == Nothing && retry.release.cyanDots == 0 && retry.release.orangeDots == 0 && retry.seed == 42)
      ]

returnRules : List (String, Bool)
returnRules =
  let returned = step ({ ghosts := [MkGhost Cyan (MkActor (At 11 14) North 0) Entering False False (Just (At (houseSeat Cyan).x houseBottom))] } (feed 30 idleGame))
      redReturn = step ({ ghosts := [MkGhost Red (MkActor (At 13 14) North 0) (InPen West) True False Nothing],
                         release := { globalDots := Just 100 } idleGame.release } idleGame)
      outside = { ghosts := [MkGhost Orange (MkActor (At 13 11) West 0) Hunting False False Nothing],
                  release := { globalDots := Just 31, elroyWaiting := False } idleGame.release } idleGame
      missed = eatDot outside
      home = step ({ ghosts := [MkGhost Pink (MkActor (At 13 14) North 0) Entering False False (Just (At (houseSeat Pink).x houseBottom))] } (eatDot missed))
      stuck = eatDot home
      timeout = step ({ release := { idleTicks := 239 } stuck.release } stuck)
   in [ ("Returned cyan retains its satisfied personal count and leaves without a fixed delay",
         waiting Cyan returned && leaving Cyan (step returned) && returned.release.cyanDots == 30 &&
         hasGhost Cyan (\g => g.revived) returned)
      , ("Returned red ignores the global counter", leaving Red redReturn)
      , ("The global-counter trap remains when orange is outside at 32",
         missed.release.globalDots == Just 32 && stuck.release.globalDots == Just 34 && waiting Pink stuck)
      , ("The idle timer still frees a ghost after the global thresholds are missed",
         leaving Pink timeout && timeout.release.globalDots == Just 34)
      ]

elroyTests : (Int, Int) -> List (String, Bool)
elroyTests (level, threshold) =
  let game = { level := level, remaining := threshold + 1 } idleGame
      first = { remaining := threshold } game
      second = { remaining := threshold `div` 2 } game
      blocked = { release := { elroyWaiting := True } game.release } second
      normal = if level <= 1 then 75 else if level < 5 then 85 else 95
      label = "Red acceleration, level " ++ show level ++ ": "
   in [ (label ++ "inclusive thresholds",
         elroyLimit level == threshold && elroyStage game == 0 && elroyStage first == 1 &&
         elroyStage ({ remaining := threshold `div` 2 + 1 } game) == 1 && elroyStage second == 2)
      , (label ++ "two speed increases",
         huntingSpeed game Red == normal && huntingSpeed first Red == normal + 5 && huntingSpeed second Red == normal + 10)
      , (label ++ "other ghosts do not accelerate",
         all (\identity => huntingSpeed second identity == normal) [Pink, Cyan, Orange])
      , (label ++ "death suppresses both speed increases",
         elroyStage blocked == 0 && huntingSpeed blocked Red == normal)
      ]

elroyRules : List (String, Bool)
elroyRules =
  let red = MkGhost Red (MkActor (At 12 11) East 0) Hunting False False Nothing
      fast = { remaining := 10 } idleGame
      blocked = { release := { elroyWaiting := True, cyanDots := 30, orangeDots := 59 } fast.release } fast
      released = step ({ release := { orangeDots := 60 } blocked.release } blocked)
      timed = step ({ release := { globalDots := Just 40, idleTicks := 239 } blocked.release,
                     ghosts := [MkGhost Orange (MkActor (At 15 14) North 0) (InPen West) False False Nothing] } blocked)
      base = { level := 5 } idleGame
      quick = { remaining := 40 } base
   in concatMap elroyTests
        [(1, 20), (2, 30), (3, 40), (5, 40), (6, 50), (8, 50), (9, 60), (11, 60),
         (12, 80), (14, 80), (15, 100), (18, 100), (19, 120), (21, 120), (100, 120)] ++
      [ ("Accelerated red targets the player even during scatter",
         ghostTarget idleGame red == At 25 (-3) && ghostTarget fast red == fast.player.tile &&
         ghostTarget fast ({ identity := Pink } red) == At 2 (-3))
      , ("Death also suppresses Red's scatter override", ghostTarget blocked red == At 25 (-3))
      , ("Orange leaving restores Red's speed and scatter override",
         leaving Orange released && not released.release.elroyWaiting && elroyStage released == 2 &&
         ghostTarget released red == released.player.tile)
      , ("A timed orange release also restores Red's acceleration",
         leaving Orange timed && not timed.release.elroyWaiting && elroyStage timed == 2)
      , ("The highest siren follows Red's acceleration without restarting music",
         loopChanges base quick == (["siren-faster"], ["siren-fastest"]))
      , ("Fractional movement and tunnel positions do not make the siren fluctuate",
         all (\frame => sirenName ({ frame := frame, ghosts := [{ actor := MkActor (At 0 14) West 0 } red] } quick) ==
           "siren-fastest") (the (List Int) [0..98]))
      ]

safeTurns : Int -> Bool
safeTurns level =
  let maze = buildMaze level
      game = { level := level, maze := maze, modeTicks := 500 } idleGame
   in all (\tile => all (\heading => not (canMove maze False tile (opposite heading)) ||
        let actor = MkActor tile heading 0
            direction = ghostDirection game (MkGhost Red actor Hunting False False Nothing) actor
         in canMove maze False tile direction && direction /= opposite heading) directions)
      (filter (walkable maze False) allTiles)

turnRules : List (String, Bool)
turnRules =
  let maze = buildMaze 1
      points = [At 12 11, At 15 11, At 12 23, At 15 23]
      actor = MkActor (At 12 11) East 0
      ghost = MkGhost Red actor Hunting False False Nothing
      game = { modeTicks := 500, player := MkActor (At 12 1) North 0 } idleGame
      frightened = { frightened := 100 } game
      eye = MkGhost Red (MkActor (At 12 23) East 0) Eyes False False Nothing
      atDoor = MkGhost Cyan (MkActor (At 13 11) North 0) (Leaving West) False False (Just houseDoorPosition)
      normalExit = step ({ ghosts := [atDoor] } idleGame)
      reversedExit = step ({ ghosts := [atDoor], modeTicks := 419 } idleGame)
      inHouse = MkGhost Cyan (MkActor (At 11 14) North 0) (InPen West) False False Nothing
      reversedHouse = step ({ ghosts := [inHouse], modeTicks := 419 } idleGame)
      poweredHouse = eatPower ({ ghosts := [inHouse] } idleGame)
   in [ ("The classic maze has exactly four restricted upward junctions",
         all (restrictedUp maze) points && length (filter (restrictedUp maze) allTiles) == 4)
      , ("Normal ghosts cannot choose an upward exit at any restricted junction",
         all (\tile => let actor = MkActor tile East 0
                       in ghostDirection ({ player := MkActor (At tile.x 0) North 0 } game)
                            (MkGhost Red actor Hunting False False Nothing) actor /= North) points)
      , ("The player can still turn upward at these junctions", all (\tile => canMove maze False tile North) points)
      , ("Frightened ghosts can choose the restricted upward exit",
         any (\seed => ghostDirection ({ seed := seed } frightened) ghost actor == North) (the (List Bits32) [0..3]))
      , ("Revived ghosts still obey upward restrictions during frightened time",
         all (\seed => ghostDirection ({ seed := seed } frightened) ({ revived := True } ghost) actor /= North) (the (List Bits32) [0..3]))
      , ("Returning eyes can use a restricted upward exit", ghostDirection game eye eye.actor == North)
      , ("A custom-maze corner does not become a ghost trap",
         not (restrictedUp (buildMaze 4) (At 12 23)) && not (restrictedUp (buildMaze 4) (At 15 23)))
      , ("House exits point west unless a reversal occurred inside",
         hasGhost Cyan (\g => g.actor.heading == West) normalExit &&
         hasGhost Cyan (\g => g.actor.heading == East) reversedExit)
      , ("Waiting ghosts remember a mode change for their eventual exit",
         hasGhost Cyan (\g => case g.state of InPen East => True; _ => False) reversedHouse)
      , ("Power pellets also change the remembered house-exit direction",
         hasGhost Cyan (\g => case g.state of InPen East => True; _ => False) poweredHouse)
      ] ++ map (\level => ("Layout " ++ show level ++ ": restricted turns always leave a legal forward exit", safeTurns level)) [1..5]

export
arcadeTests : List (String, Bool)
arcadeTests = speedRules ++ scheduleRules ++ personalRules ++ globalRules ++ idleRules ++
              resetRules ++ returnRules ++ elroyRules ++ turnRules
