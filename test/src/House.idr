module House

import Chompit.Types
import Chompit.Maze
import Chompit.Game
import Chompit.Audio

import Data.List
import Data.Maybe
import Data.SortedSet

%default covering

quiet : Game
quiet = { phase := Playing, ghosts := [], player := MkActor (At 13 23) North 0,
          wanted := North, dots := empty, powers := empty, modeTicks := 100 } newGame

identities : List Identity
identities = [Red, Pink, Cyan, Orange]

name : Identity -> String
name Red = "Red"
name Pink = "Pink"
name Cyan = "Cyan"
name Orange = "Orange"

waiting, hunting : Ghost -> Bool
waiting ghost = case ghost.state of InPen _ => True; _ => False
hunting ghost = case ghost.state of Hunting => True; _ => False

inside : Identity -> Direction -> GhostState -> Tile -> Ghost
inside identity heading state point =
  MkGhost identity (MkActor (At (point.x `div` 256) (point.y `div` 256)) heading 0)
          state False False (Just point)

pen : Identity -> Ghost
pen identity = inside identity North (InPen West) (houseSeat identity)

eye : Identity -> Tile -> Ghost
eye identity tile = MkGhost identity (MkActor tile East 0) Eyes False False Nothing

advance : Nat -> Game -> Game
advance Z game = game
advance (S ticks) game = advance ticks (step game)

trace : (Ghost -> Bool) -> Nat -> Game -> Ghost -> List Ghost
trace stop Z game ghost = [ghost]
trace stop (S ticks) game ghost =
  if stop ghost then [ghost] else
    let next : Game = { frame := game.frame + 1 } game
     in ghost :: trace stop ticks next (moveGhost next ghost)

lastGhost : List Ghost -> Ghost
lastGhost = foldl (\_, ghost => ghost) (pen Red)

distance : Tile -> Tile -> Int
distance a b = let dx = abs (a.x - b.x) in min dx (abs (7168 - dx)) + abs (a.y - b.y)

bounded : Game -> List Ghost -> Bool
bounded game (first :: second :: rest) =
  let next : Game = { frame := game.frame + 1 } game
   in distance (ghostPosition first) (ghostPosition second) <= ghostSpeed next first &&
      bounded next (second :: rest)
bounded _ _ = True

samePose : Ghost -> Ghost -> Bool
samePose a b = ghostPosition a == ghostPosition b && a.actor.heading == b.actor.heading &&
               a.housePosition == b.housePosition && a.revived == b.revived &&
               a.reversePending == b.reversePending

pacing : Nat -> Game -> Ghost -> Bool
pacing Z game ghost = True
pacing (S ticks) game ghost =
  let next : Game = { frame := game.frame + 1 } game
      speed = ghostSpeed next ghost
      point = ghostPosition ghost
      upward = ghost.actor.heading == North
      proposed = point.y + (if upward then -speed else speed)
      expected = if proposed <= houseTop then 2 * houseTop - proposed
                 else if proposed >= houseBottom then 2 * houseBottom - proposed else proposed
      heading = if proposed <= houseTop then South else if proposed >= houseBottom then North else ghost.actor.heading
      moved = moveGhost next ghost
   in ghostPosition moved == At point.x expected && moved.actor.heading == heading && waiting moved &&
      not moved.reversePending && moved.revived == ghost.revived && pacing ticks next moved

initialRules : List (String, Bool)
initialRules =
  [ ("Red starts centered above the door", maybe False (\g => ghostPosition g == houseDoorPosition && hunting g) (head' newGame.ghosts))
  , ("House starting positions use the three half-tile lanes",
      all (\identity => maybe False (\g => ghostPosition g == houseSeat identity && waiting g)
        (find (\g => g.identity == identity) newGame.ghosts)) [Pink, Cyan, Orange])
  , ("Pink initially faces down while cyan and orange face up",
      all (\identity => maybe False (\g => g.actor.heading == if identity == Pink then South else North)
        (find (\g => g.identity == identity) newGame.ghosts)) [Pink, Cyan, Orange])
  , ("House motion uses 40 percent on every level, even during frightened time",
      all (\level => all (\state =>
        let ghost = { state := state } (pen Cyan)
            game = { level := level, frightened := 120 } quiet
         in sum (map (\frame => ghostSpeed ({ frame := frame } game) ghost) (the (List Int) [0..98])) == 1600)
        [InPen West, Leaving East]) (the (List Int) [1, 2, 5, 21, 100]))
  , ("Returning eyes use two pixels per update outside and inside the house",
      all (\level => all (\state => ghostSpeed ({ level := level } quiet) ({ state := state } (pen Red)) == 64)
        [Eyes, Entering]) (the (List Int) [1, 5, 21]))
  ] ++ map (\identity => (name identity ++ ": pacing reflects at both bounds without losing the movement remainder",
        all (\heading => pacing 500 quiet ({ actor := { heading := heading } (pen identity).actor } (pen identity)))
          [North, South])) identities

exitPath : Identity -> Direction -> Int -> Int -> Bool
exitPath identity exit y frame =
  let point = At (houseSeat identity).x y
      ghost = inside identity South (Leaving exit) point
      game = { frame := frame } quiet
      path = trace hunting 120 game ghost
      finished = lastGhost path
      final = ghostPosition finished
      onRoute = \g => let p = ghostPosition g in
        p.y >= houseDoorPosition.y && p.y <= y &&
        (p.x == houseDoorPosition.x || p.y == y || hunting g) &&
        walkable game.maze True g.actor.tile
   in hunting finished && finished.actor.heading == exit && isNothing finished.housePosition &&
      finished.actor.progress >= 0 && finished.actor.progress < 256 &&
      final.y == houseDoorPosition.y && abs (final.x - houseDoorPosition.x) <= 17 &&
      all onRoute path && bounded game path

exitRules : List (String, Bool)
exitRules = concatMap (\identity => map (\exit =>
  (name identity ++ ": a centered house exit preserves position and its remembered direction",
   all (\y => all (exitPath identity exit y) [0, 42, 98])
     [houseTop, houseTop + 17, 14 * 256, houseBottom - 5, houseBottom])) [West, East]) identities ++
  let start = inside Cyan East (Leaving West) (At (houseDoorPosition.x - 5) (14 * 256))
      corner = moveGhost quiet start
      nearDoor = inside Cyan North (Leaving East) (At houseDoorPosition.x (houseDoorPosition.y + 5))
      outside = moveGhost quiet nearDoor
      speed = speedStep 40 quiet.frame
   in [ ("A house exit spends its remaining movement after the horizontal bend",
          ghostPosition corner == At houseDoorPosition.x (14 * 256 - (speed - 5)) && corner.actor.heading == North)
      , ("Crossing the door does not snap the ghost to a tile center",
          hunting outside && ghostPosition outside == At (houseDoorPosition.x + speed - 5) houseDoorPosition.y)
      , ("A reversal during departure changes only the eventual exit direction",
          let changed = requestReverse start in ghostPosition changed == ghostPosition start &&
          not changed.reversePending && case changed.state of Leaving East => True; _ => False)
      ]

returnPath : Int -> Identity -> Tile -> Bool
returnPath level identity tile =
  let game = { level := level, maze := buildMaze level } quiet
      path = trace waiting 1500 game (eye identity tile)
      returned = lastGhost path
      correctEntry = \ghost => case ghost.state of
        Entering => let p = ghostPosition ghost in
          if p.y > houseDoorPosition.y && p.y < houseBottom then p.x == houseDoorPosition.x else True
        _ => True
   in waiting returned && returned.revived && not returned.reversePending &&
      returned.actor.heading == North && ghostPosition returned == At (houseSeat identity).x houseBottom &&
      all correctEntry path && bounded game path &&
      any (\g => case g.state of Entering => True; _ => False) path

returnRules : List (String, Bool)
returnRules = concatMap (\level => map (\identity =>
  ("Layout " ++ show level ++ ", " ++ name identity ++ ": eyes reach their own slot from corners and tunnels",
   all (returnPath level identity) [At 1 1, At 26 1, At 1 29, At 26 29, At 0 14, At 27 14])) identities) [1..5] ++
  let west = moveGhost quiet (eye Pink houseEntrance)
      east = moveGhost quiet ({ actor := MkActor (At 14 11) West 0 } (eye Pink (At 14 11)))
      bend = inside Pink East Entering (At (houseDoorPosition.x - 5) houseDoorPosition.y)
      below = moveGhost quiet bend
      lower = moveGhost quiet (inside Cyan South Entering (At houseDoorPosition.x (houseBottom - 5)))
      almost = inside Orange East Entering (At ((houseSeat Orange).x - 5) houseBottom)
      returned = moveGhost quiet almost
   in [ ("Eyes align with the door from either side without changing position abruptly",
          ghostPosition west == At (13 * 256 + 64) (11 * 256) &&
          ghostPosition east == At (14 * 256 - 64) (11 * 256) && isReturning west && isReturning east)
      , ("Eyes spend the remainder below the door after reaching its centerline",
          ghostPosition below == At houseDoorPosition.x (houseDoorPosition.y + 59) && below.actor.heading == South)
      , ("Eyes turn toward their own lane at the lower house bound",
          ghostPosition lower == At (houseDoorPosition.x - 59) houseBottom && lower.actor.heading == West)
      , ("Revival waits for the exact slot and stops at that point",
          waiting returned && returned.revived && not (isReturning returned) &&
          ghostPosition returned == At (houseSeat Orange).x houseBottom)
      ]

releaseDuringPace : (Int, Ghost) -> Bool
releaseDuringPace (frame, ghost) =
  let game = { frame := frame, ghosts := [ghost], stall := 1,
               player := MkActor (At 1 1) North 0, wanted := North,
               dots := singleton (key (At 1 1)),
               release := { cyanDots := 29 } quiet.release } quiet
      released = step game
      before = ghostPosition ghost
   in maybe False (\g => ghostPosition g == At (before.x + speedStep 40 released.frame) before.y &&
        case g.state of Leaving West => True; _ => False) (head' released.ghosts)

powerStep : Ghost -> Game
powerStep ghost = step ({ player := MkActor (At 1 3) North 0, wanted := North, stall := 1,
                         powers := singleton (key (At 1 3)), frightened := 14,
                         ghosts := [ghost] } quiet)

controlRules : List (String, Bool)
controlRules =
  let paced = take 64 (trace (const False) 64 quiet (pen Cyan))
      ghost = inside Cyan North (InPen West) (At (houseSeat Cyan).x (houseTop + 33))
      frozen = advance 50 ({ ghosts := [ghost], freeze := 50 } quiet)
      paused = advance 50 (command Pause ({ ghosts := [ghost] } quiet))
      ready = advance 50 ({ ghosts := [ghost], phase := Ready 60 } quiet)
      entry = inside Cyan South Entering (At houseDoorPosition.x (houseDoorPosition.y + 64))
      changed = requestReverse entry
      powered = powerStep entry
      returned = moveGhost quiet (inside Cyan South Entering (At (houseSeat Cyan).x houseBottom))
      refreshed = powerStep returned
   in [ ("Pellet release starts a horizontal exit from every tested bounce position",
          all releaseDuringPace (zip (the (List Int) [0..63]) paced))
      , ("Pause, capture freezes, and ready countdowns hold the exact house position",
          all (\game => maybe False (samePose ghost) (head' game.ghosts)) [frozen, paused, ready])
      , ("House pacing resumes without losing its position",
          maybe False (\g => ghostPosition g /= ghostPosition ghost && waiting g) (head' (step frozen).ghosts))
      , ("Reversal signals cannot redirect entering eyes", isReturning changed && samePose entry changed)
      , ("Power pellets do not frighten or reverse entering eyes",
          maybe False (\g => isReturning g && not (isFrightened powered g) &&
            ghostPosition g == At houseDoorPosition.x (houseDoorPosition.y + 128)) (head' powered.ghosts))
      , ("A new power pellet removes immunity after the body returns",
          returned.revived && maybe False (\g => not g.revived && isFrightened refreshed g &&
            case g.state of InPen East => True; _ => False) (head' refreshed.ghosts))
      , ("The eyes warning continues during house entry",
          loopChanges ({ ghosts := [eye Cyan houseEntrance] } quiet) ({ ghosts := [entry] } quiet) == ([], []))
      , ("The eyes warning ends only when the final body returns",
          loopChanges ({ ghosts := [entry] } quiet) ({ ghosts := [returned] } quiet) == (["eyes"], ["siren"]))
      , ("One restored body does not stop another ghost's eyes warning",
          loopChanges ({ ghosts := [entry, eye Red houseEntrance] } quiet)
                      ({ ghosts := [returned, eye Red houseEntrance] } quiet) == ([], []))
      ]

resetRules : List (String, Bool)
resetRules =
  let poses = [ inside Cyan South (InPen East) (At (houseSeat Cyan).x (houseTop + 73))
              , inside Pink North (Leaving East) (At houseDoorPosition.x (12 * 256))
              , inside Orange South Entering (At houseDoorPosition.x (13 * 256)) ]
      game = { ghosts := poses } quiet
      paused = advance 50 (command LoseFocus game)
      frozen = advance 50 ({ freeze := 50 } game)
      held = \state => length state.ghosts == length poses && all (\(a, b) => samePose a b) (zip poses state.ghosts)
      died = step ({ phase := Dying 1, lives := 2 } game)
      loaded = step ({ phase := Clearing 1 } game)
      retry = command Start ({ phase := GameOver } game)
      initial = \state => length state.ghosts == 4 && all (\(a, b) => samePose a b) (zip newGame.ghosts state.ghosts)
   in [ ("Focus loss and capture freezes hold waiting, departing, and entering ghosts", all held [paused, frozen])
      , ("Death, new levels, and retry restore house positions and headings", all initial [died, loaded, retry])
      ]

export
houseTests : List (String, Bool)
houseTests = initialRules ++ exitRules ++ returnRules ++ controlRules ++ resetRules
