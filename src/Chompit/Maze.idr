module Chompit.Maze

import Chompit.Types

import Data.List
import Data.Maybe
import Data.SortedMap
import Data.SortedSet

%default total

-- x is outside the maze, a space is an empty passage, h is the ghost house.
-- Every layout keeps the house, tunnel, player spawn, and fruit position fixed.
classicRows : List String
classicRows =
  [ "############################"
  , "#............##............#"
  , "#.####.#####.##.#####.####.#"
  , "#o####.#####.##.#####.####o#"
  , "#.####.#####.##.#####.####.#"
  , "#..........................#"
  , "#.####.##.########.##.####.#"
  , "#.####.##.########.##.####.#"
  , "#......##....##....##......#"
  , "######.##### ## #####.######"
  , "xxxxx#.##### ## #####.#xxxxx"
  , "xxxxx#.##          ##.#xxxxx"
  , "xxxxx#.## ###--### ##.#xxxxx"
  , "######.## #hhhhhh# ##.######"
  , "      .   #hhhhhh#   .      "
  , "######.## #hhhhhh# ##.######"
  , "xxxxx#.## ######## ##.#xxxxx"
  , "xxxxx#.##          ##.#xxxxx"
  , "xxxxx#.## ######## ##.#xxxxx"
  , "######.## ######## ##.######"
  , "#............##............#"
  , "#.####.#####.##.#####.####.#"
  , "#.####.#####.##.#####.####.#"
  , "#o..##.......  .......##..o#"
  , "###.##.##.########.##.##.###"
  , "###.##.##.########.##.##.###"
  , "#......##....##....##......#"
  , "#.##########.##.##########.#"
  , "#.##########.##.##########.#"
  , "#..........................#"
  , "############################"
  ]

-- Level 2: paired ladders and a broad lower crossing.
crossroadsRows : List String
crossroadsRows =
  [ "############################"
  , "#..........................#"
  , "#.####.#####.##.#####.####.#"
  , "#o####.#####.##.#####.####o#"
  , "#............##............#"
  , "#.####.#####.##.#####.####.#"
  , "#.####.#####.##.#####.####.#"
  , "#.####.#####.##.#####.####.#"
  , "#............##............#"
  , "######.##### ## #####.######"
  , "xxxxx#.##### ## #####.#xxxxx"
  , "xxxxx#.##          ##.#xxxxx"
  , "xxxxx#.## ###--### ##.#xxxxx"
  , "######.## #hhhhhh# ##.######"
  , "      .   #hhhhhh#   .      "
  , "######.## #hhhhhh# ##.######"
  , "xxxxx#.## ######## ##.#xxxxx"
  , "xxxxx#.##          ##.#xxxxx"
  , "xxxxx#.## ######## ##.#xxxxx"
  , "######.## ######## ##.######"
  , "#..........................#"
  , "#.####.#####.##.#####.####.#"
  , "#.####.#####.##.#####.####.#"
  , "#......##....  ....##......#"
  , "#.####.##.########.##.####.#"
  , "#.####.##.########.##.####.#"
  , "#..........................#"
  , "#o#######.##.##.##.#######o#"
  , "#.#######.##.##.##.#######.#"
  , "#............##............#"
  , "############################"
  ]

-- Level 3: staggered crossings force more turns in the upper half.
switchbackRows : List String
switchbackRows =
  [ "############################"
  , "#............##............#"
  , "#.####.##.##.##.##.##.####.#"
  , "#o####.##.##.##.##.##.####o#"
  , "#.........##....##.........#"
  , "#.#######.########.#######.#"
  , "#.#######.########.#######.#"
  , "#.#######.########.#######.#"
  , "#......##..........##......#"
  , "######.##### ## #####.######"
  , "xxxxx#.##### ## #####.#xxxxx"
  , "xxxxx#.##          ##.#xxxxx"
  , "xxxxx#.## ###--### ##.#xxxxx"
  , "######.## #hhhhhh# ##.######"
  , "      .   #hhhhhh#   .      "
  , "######.## #hhhhhh# ##.######"
  , "xxxxx#.## ######## ##.#xxxxx"
  , "xxxxx#.##          ##.#xxxxx"
  , "xxxxx#.## ######## ##.#xxxxx"
  , "######.## ######## ##.######"
  , "#............##............#"
  , "#.####.#####.##.#####.####.#"
  , "#.####.#####.##.#####.####.#"
  , "#............  ............#"
  , "#.####.##.########.##.####.#"
  , "#.####.##.########.##.####.#"
  , "#......##..........##......#"
  , "#o#######.##.##.##.#######o#"
  , "#.#######.##.##.##.#######.#"
  , "#..........................#"
  , "############################"
  ]

-- Level 4: long outer loops surround an inner crossing.
courtyardRows : List String
courtyardRows =
  [ "############################"
  , "#..........................#"
  , "#.####.##############.####.#"
  , "#o####.##############.####o#"
  , "#.####................####.#"
  , "#.####.#####.##.#####.####.#"
  , "#.####.#####.##.#####.####.#"
  , "#.####.#####.##.#####.####.#"
  , "#..........................#"
  , "######.##### ## #####.######"
  , "xxxxx#.##### ## #####.#xxxxx"
  , "xxxxx#.##          ##.#xxxxx"
  , "xxxxx#.## ###--### ##.#xxxxx"
  , "######.## #hhhhhh# ##.######"
  , "      .   #hhhhhh#   .      "
  , "######.## #hhhhhh# ##.######"
  , "xxxxx#.## ######## ##.#xxxxx"
  , "xxxxx#.##          ##.#xxxxx"
  , "xxxxx#.## ######## ##.#xxxxx"
  , "######.## ######## ##.######"
  , "#..........................#"
  , "#.####.#####.##.#####.####.#"
  , "#.####.#####.##.#####.####.#"
  , "#.........##.  .##.........#"
  , "#.#######.##.##.##.#######.#"
  , "#.#######.##.##.##.#######.#"
  , "#..........................#"
  , "#o####.##.########.##.####o#"
  , "#.####.##.########.##.####.#"
  , "#..........................#"
  , "############################"
  ]

-- Level 5: narrow upper circuits and a dense set of lower junctions.
circuitRows : List String
circuitRows =
  [ "############################"
  , "#............##............#"
  , "#.##.####.##.##.##.####.##.#"
  , "#o##.####.##.##.##.####.##o#"
  , "#.##.####.##.##.##.####.##.#"
  , "#.........##....##.........#"
  , "#.#######.########.#######.#"
  , "#.#######.########.#######.#"
  , "#..........................#"
  , "######.##### ## #####.######"
  , "xxxxx#.##### ## #####.#xxxxx"
  , "xxxxx#.##          ##.#xxxxx"
  , "xxxxx#.## ###--### ##.#xxxxx"
  , "######.## #hhhhhh# ##.######"
  , "      .   #hhhhhh#   .      "
  , "######.## #hhhhhh# ##.######"
  , "xxxxx#.## ######## ##.#xxxxx"
  , "xxxxx#.##          ##.#xxxxx"
  , "xxxxx#.## ######## ##.#xxxxx"
  , "######.## ######## ##.######"
  , "#............##............#"
  , "#.####.##.##.##.##.##.####.#"
  , "#.####.##.##.##.##.##.####.#"
  , "#......##....  ....##......#"
  , "#.#######.########.#######.#"
  , "#.#######.########.#######.#"
  , "#..........................#"
  , "#o####.##.##.##.##.##.####o#"
  , "#.####.##.##.##.##.##.####.#"
  , "#............##............#"
  , "############################"
  ]

export
layoutCount : Int
layoutCount = 5

-- Keep increasing the difficulty level after the five layouts repeat.
export
layoutNumber : Int -> Int
layoutNumber level = (max 1 level - 1) `mod` layoutCount + 1

export
rows : Int -> List String
rows level = case layoutNumber level of
  2 => crossroadsRows
  3 => switchbackRows
  4 => courtyardRows
  5 => circuitRows
  _ => classicRows

public export
key : Tile -> Int
key (At x y) = y * 28 + x

export
allTiles : List Tile
allTiles = concatMap (\y => map (\x => At x y) [0..27]) [0..30]

public export
neighbor : Tile -> Direction -> Tile
neighbor tile direction =
  let next = plus tile (delta direction)
   in if next.y == 14 && next.x < 0 then At 27 14
      else if next.y == 14 && next.x > 27 then At 0 14
      else next

public export
record Maze where
  constructor MkMaze
  layoutId : Int
  cells : SortedMap Int Char
  pellets : SortedSet Int
  energizers : SortedSet Int
  homeDistances : SortedMap Int Int

export
cellAt : Maze -> Tile -> Char
cellAt maze tile =
  if tile.x < 0 || tile.x >= 28 || tile.y < 0 || tile.y >= 31 then 'x'
  else fromMaybe '#' (lookup (key tile) maze.cells)

export
walkable : Maze -> Bool -> Tile -> Bool
walkable maze house tile = case cellAt maze tile of
  '#' => False
  'x' => False
  '-' => house
  'h' => house
  _ => True

export
canMove : Maze -> Bool -> Tile -> Direction -> Bool
canMove maze house tile heading = walkable maze house (neighbor tile heading)

-- Preserve the four classic no-up junctions, but not corners in other layouts.
-- Both horizontal exits must exist so this rule cannot trap a hunting ghost.
export
restrictedUp : Maze -> Tile -> Bool
restrictedUp maze tile = elem tile [At 12 11, At 15 11, At 12 23, At 15 23] &&
  canMove maze False tile West && canMove maze False tile East

-- Breadth-first distances guide eyes to the entrance. A separate path crosses
-- the centered door and reaches the ghost's own slot. Visit at most 868 cells.
homeMap : Maze -> SortedMap Int Int
homeMap maze = visit 868 [(houseEntrance, 0)] (insert (key houseEntrance) 0 empty)
  where
    visit : Nat -> List (Tile, Int) -> SortedMap Int Int -> SortedMap Int Int
    visit Z _ known = known
    visit (S fuel) [] known = known
    visit (S fuel) ((tile, depth) :: queue) known =
      let fresh = filter (\t => walkable maze True t && isNothing (lookup (key t) known))
                         (map (neighbor tile) directions)
          next = foldl (\m, t => insert (key t) (depth + 1) m) known fresh
       in visit fuel (queue ++ map (\t => (t, depth + 1)) fresh) next

collect : Char -> List (Int, Char) -> List Int
collect wanted [] = []
collect wanted ((index, cell) :: rest) =
  if cell == wanted then index :: collect wanted rest else collect wanted rest

export
buildMaze : Int -> Maze
buildMaze level =
  let entries : List (Int, Char) = zip (map key allTiles) (concatMap unpack (rows level))
      cells = Data.SortedMap.fromList entries
      dots = Data.SortedSet.fromList (collect '.' entries)
      powers = Data.SortedSet.fromList (collect 'o' entries)
      maze = MkMaze (layoutNumber level) cells dots powers empty
   in { homeDistances := homeMap maze } maze

export
pelletCount : Maze -> Int
pelletCount maze = cast (length (Prelude.toList maze.pellets) +
                         length (Prelude.toList maze.energizers))
