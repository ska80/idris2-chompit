module Chompit.Maze

import Chompit.Types

import Data.List
import Data.Maybe
import Data.SortedMap
import Data.SortedSet

%default total

-- x is outside the maze, a space is an empty passage, h is the ghost house.
export
rows : List String
rows =
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

-- Breadth-first distances let eaten ghosts return through the door, without
-- getting trapped in a greedy chase loop. The search visits at most 868 cells.
homeMap : Maze -> SortedMap Int Int
homeMap maze = visit 868 [(At 13 14, 0)] (insert (key (At 13 14)) 0 empty)
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
buildMaze : Maze
buildMaze =
  let entries : List (Int, Char) = zip (map key allTiles) (concatMap unpack rows)
      cells = Data.SortedMap.fromList entries
      dots = Data.SortedSet.fromList (collect '.' entries)
      powers = Data.SortedSet.fromList (collect 'o' entries)
      maze = MkMaze cells dots powers empty
   in { homeDistances := homeMap maze } maze

export
pelletCount : Maze -> Int
pelletCount maze = cast (length (Prelude.toList maze.pellets) +
                         length (Prelude.toList maze.energizers))
