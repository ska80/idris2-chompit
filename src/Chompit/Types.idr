module Chompit.Types

%default total

public export
record Tile where
  constructor At
  x, y : Int

public export
Eq Tile where
  (At x y) == (At u v) = x == u && y == v

public export
data Direction = North | West | South | East

public export
Eq Direction where
  North == North = True
  West == West = True
  South == South = True
  East == East = True
  _ == _ = False

public export
directions : List Direction
directions = [North, West, South, East]

public export
opposite : Direction -> Direction
opposite North = South
opposite West = East
opposite South = North
opposite East = West

public export
delta : Direction -> Tile
delta North = At 0 (-1)
delta West = At (-1) 0
delta South = At 0 1
delta East = At 1 0

public export
plus : Tile -> Tile -> Tile
plus (At x y) (At u v) = At (x + u) (y + v)

public export
scaled : Int -> Tile -> Tile
scaled n (At x y) = At (n * x) (n * y)

public export
distanceSquared : Tile -> Tile -> Int
distanceSquared (At x y) (At u v) = (x - u) * (x - u) + (y - v) * (y - v)

public export
record Actor where
  constructor MkActor
  tile : Tile
  heading : Direction
  -- Distance from this tile's center toward the next center, in 1/256 tiles.
  progress : Int
  -- Player corners carry a perpendicular displacement until the track is centered.
  -- Ordinary actors keep zero displacement without an extra constructor argument.
  {default (At 0 0) offset : Tile}

public export
data Identity = Red | Pink | Cyan | Orange

public export
Eq Identity where
  Red == Red = True
  Pink == Pink = True
  Cyan == Cyan = True
  Orange == Orange = True
  _ == _ = False

public export
-- Waiting and leaving bodies remember their eventual exit direction.
data GhostState = Hunting | InPen Direction | Leaving Direction | Eyes | Entering

-- The maze route ends beside the center of the two-tile door.
public export
houseEntrance : Tile
houseEntrance = At 13 11

public export
record Ghost where
  constructor MkGhost
  identity : Identity
  actor : Actor
  state : GhostState
  revived : Bool
  -- A reversal request waits until the next tile center.
  reversePending : Bool
  -- House paths can lie between tile centerlines. Coordinates use 1/256 tiles.
  housePosition : Maybe Tile

public export
record ReleaseCounters where
  constructor MkReleaseCounters
  pinkDots, cyanDots, orangeDots : Int
  globalDots : Maybe Int
  idleTicks : Int
  elroyWaiting : Bool

public export
data Fruit = Cherries | Strawberry | OrangeFruit | Apple | Melon | Galaxian | Bell | KeyFruit

public export
Eq Fruit where
  Cherries == Cherries = True
  Strawberry == Strawberry = True
  OrangeFruit == OrangeFruit = True
  Apple == Apple = True
  Melon == Melon = True
  Galaxian == Galaxian = True
  Bell == Bell = True
  KeyFruit == KeyFruit = True
  _ == _ = False

public export
data Interlude = Turnabout | Snag | Costume

public export
Eq Interlude where
  Turnabout == Turnabout = True
  Snag == Snag = True
  Costume == Costume = True
  _ == _ = False

public export
data Phase = Title | Ready Int | Playing | Dying Int | Clearing Int
           | Intermission Interlude Int | GameOver

public export
data Cue = ChompLow | ChompHigh | Energize | GhostEaten | PlayerDied
                | LevelWon | BeginGame | FruitEaten | BonusLife

public export
Eq Cue where
  ChompLow == ChompLow = True
  ChompHigh == ChompHigh = True
  Energize == Energize = True
  GhostEaten == GhostEaten = True
  PlayerDied == PlayerDied = True
  LevelWon == LevelWon = True
  BeginGame == BeginGame = True
  FruitEaten == FruitEaten = True
  BonusLife == BonusLife = True
  _ == _ = False

public export
data Command = Turn Direction | Start | Pause | LoseFocus | ToggleMute | Quit | Ignore
