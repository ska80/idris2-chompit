module Chompit.Render

import Chompit.Types
import Chompit.Maze
import Chompit.Game
import Chompit.Font
import Chompit.Fruit

import SDL3
import SDL3.Scoped

import Data.List
import Data.SortedSet

%default covering

black, blue, yellow, white, pellet, red, pink, cyan, orange : Color
black = MkColor 0 0 0 255
blue = MkColor 33 33 255 255
yellow = MkColor 255 255 0 255
white = MkColor 255 255 255 255
pellet = MkColor 255 184 174 255
red = MkColor 255 0 0 255
pink = MkColor 255 184 255 255
cyan = MkColor 0 255 255 255
orange = MkColor 255 184 82 255

record Batch where
  constructor Ink
  color : Color
  rects : List FRect

record WallLayer where
  constructor MkWallLayer
  layoutId : Int
  buffer : RectBuffer
  count : Bits32

export
record Display where
  constructor MkDisplay
  renderer : Renderer
  walls : List WallLayer
  scratch : RectBuffer

color : Renderer -> Color -> IO Bool
color renderer (MkColor r g b a) = setDrawColor renderer r g b a

upload : RectBuffer -> Bits32 -> List FRect -> IO Bool
upload buffer index [] = pure True
upload buffer index (rect :: rest) = do
  True <- setRect buffer index rect | False => pure False
  upload buffer (index + 1) rest

paint : Display -> List Batch -> IO Bool
paint display [] = pure True
paint display (Ink ink rects :: rest) = do
  True <- color display.renderer ink | False => pure False
  True <- upload display.scratch 0 rects | False => pure False
  True <- fillRects display.renderer display.scratch (cast (length rects)) | False => pure False
  paint display rest

wallPixel : Maze -> Tile -> Bool
wallPixel maze pixel = pixel.x >= 0 && pixel.y >= 0 && pixel.x < 224 && pixel.y < 248 &&
  cellAt maze (At (pixel.x `div` 8) (pixel.y `div` 8)) == '#'

-- An inset pixel outline joins both convex and concave corners. Computing the
-- outline once avoids disconnected segments where wall tiles meet.
wallRects : Maze -> Tile -> List FRect
wallRects maze tile = if cellAt maze tile /= '#' then [] else
  let pixels = concatMap (\y => map (\x => At (tile.x * 8 + x) (tile.y * 8 + y)) [0..7]) [0..7]
      near = map delta directions
      ring = map (scaled 2) near ++ [At 1 1, At 1 (-1), At (-1) 1, At (-1) (-1)]
      outline = filter (\p => all (\offset => wallPixel maze (plus p offset)) near &&
                              any (\offset => not (wallPixel maze (plus p offset))) ring) pixels
   in map (\p => MkFRect (cast p.x) (cast (p.y + 24)) 1 1) outline

-- Allocate and upload every layout before the loop. Level changes select an
-- existing buffer, including the return to layout one after level five.
withWallLayers : List Int -> (List WallLayer -> IO (Either String a)) -> IO (Either String a)
withWallLayers [] action = action []
withWallLayers (number :: rest) action =
  let maze = buildMaze number
      walls = concatMap (wallRects maze) allTiles in
  withRectBuffer (cast (max 1 (length walls))) $ \buffer => do
    True <- upload buffer 0 walls | False => Left <$> getError
    withWallLayers rest $ \layers => action (MkWallLayer number buffer (cast (length walls)) :: layers)

export
withDisplay : Renderer -> (Display -> IO (Either String a)) -> IO (Either String a)
withDisplay renderer action = withWallLayers [1..layoutCount] $ \walls =>
  withRectBuffer 4096 $ \scratch => action (MkDisplay renderer walls scratch)

textRects : Double -> Double -> Double -> String -> List FRect
textRects x y scale text = concatMap letter (zip [0 .. cast (length text)] (unpack text))
  where
    letter : (Int, Char) -> List FRect
    letter (index, char) = concatMap row (zip [0..6] (glyph char))
      where
        row : (Int, String) -> List FRect
        row (line, bits) = map (\(column, _) => MkFRect (x + (cast index * 6 + cast column) * scale)
                                      (y + cast line * scale) scale scale)
                               (filter (\(_, bit) => bit == '1') (zip [0..4] (unpack bits)))

label : Color -> Double -> Double -> Double -> String -> Batch
label ink x y scale text = Ink ink (textRects x y scale text)

centered : Color -> Double -> Double -> String -> Batch
centered ink y scale text = label ink ((224 - (cast (length text) * 6 - 1) * scale) / 2) y scale text

-- Rasterize small shapes in logical pixels. SDL scales the complete 224 x 288
-- image, so the maze, sprites, and lettering share the same pixel grid.
pixels : Double -> Double -> (Double -> Double -> Bool) -> List FRect
pixels x y predicate = concatMap row [-7..6]
  where
    row : Int -> List FRect
    row dy = map (\dx => MkFRect (floor x + cast dx) (floor y + cast dy) 1 1)
                 (filter (\dx => predicate (cast dx + 0.5) (cast dy + 0.5)) [-7..6])

chomper : Double -> Double -> Direction -> Double -> Batch
chomper x y heading mouth = Ink yellow (pixels x y shape)
  where
    shape : Double -> Double -> Bool
    shape dx dy =
      let (forward, side) : (Double, Double) = case heading of
            East => (dx, dy)
            West => (-dx, dy)
            North => (-dy, dx)
            South => (dy, dx)
       in dx * dx + dy * dy <= 43 && acos (forward / sqrt (dx * dx + dy * dy)) >= mouth

position : Actor -> (Double, Double)
position actor = let point = actorPosition actor
                 in (cast point.x / 32 + 4, cast point.y / 32 + 28)

ghostColor : Identity -> Color
ghostColor Red = red
ghostColor Pink = pink
ghostColor Cyan = cyan
ghostColor Orange = orange

ghostAt : Int -> Bool -> Bool -> Bool -> Identity -> Direction -> Double -> Double -> List Batch
ghostAt frame scared flashing eyes identity heading x y =
  let ink = if scared then (if flashing then white else blue) else ghostColor identity
      body = Ink ink (pixels x y (\dx, dy =>
        (if dy < 0 then dx * dx + dy * dy < 44 else abs dx < 6.5) &&
        (dy < 4 || (cast (floor (dx + 7)) + frame `div` 8) `mod` 4 < 2)))
      face = if flashing then red else pellet
      gaze = delta heading
      pupils = [MkFRect (x - 3 + cast gaze.x) (y - 2 + cast gaze.y) 2 3,
                MkFRect (x + 2 + cast gaze.x) (y - 2 + cast gaze.y) 2 3]
   in if scared && not eyes then
        [body, Ink face [MkFRect (x - 4) (y - 3) 2 2, MkFRect (x + 2) (y - 3) 2 2],
         Ink face (map (\i => MkFRect (x - 4 + cast i) (y + 2 + cast (i `mod` 2)) 1 1) [0..7])]
      else (if eyes then [] else [body]) ++
           [Ink white [MkFRect (x - 5) (y - 4) 4 6, MkFRect (x + 1) (y - 4) 4 6], Ink blue pupils]

ghostPicture : Game -> Ghost -> List Batch
ghostPicture game ghost =
  let (x, y) = position ghost.actor
      eyes = case ghost.state of Eyes => True; _ => False
      scared = isFrightened game ghost
      flash = game.frightened < 120 && game.frame `mod` 20 < 10
      offsets : List Double = if ghost.actor.tile.y == 14 then [-224, 0, 224] else [0]
   in concatMap (\offset => ghostAt game.frame scared flash eyes ghost.identity ghost.actor.heading (x + offset) y) offsets

fruitPicture : Fruit -> Double -> Double -> List Batch
fruitPicture fruit x y =
  let palette = [('r', red), ('g', MkColor 0 255 0 255), ('w', white),
                 ('o', orange), ('y', yellow), ('c', cyan), ('b', blue)]
      cells = concatMap (\(row, text) => map (\(column, symbol) =>
                (symbol, MkFRect (x - 8 + cast column) (y - 8 + cast row) 1 1))
                  (zip [0..15] (unpack text))) (zip [0..15] (fruitSprite fruit))
   in map (\(symbol, ink) => Ink ink (map snd (filter (\cell => fst cell == symbol) cells))) palette

foodPicture : Game -> List Batch
foodPicture game =
  let dots = map (\i => MkFRect (cast ((i `mod` 28) * 8 + 3)) (cast ((i `div` 28) * 8 + 27)) 2 2)
                 (Prelude.toList game.dots)
      powers = if game.frame `mod` 30 < 20 then concatMap (\i =>
        let x = cast ((i `mod` 28) * 8 + 4)
            y = cast ((i `div` 28) * 8 + 28)
         in [MkFRect (x - 3) (y - 2) 6 4, MkFRect (x - 2) (y - 3) 4 6]) (Prelude.toList game.powers)
        else []
   in [Ink pellet (dots ++ powers), Ink pink [MkFRect 104 124 16 2]] ++
      (if game.fruitTime > 0 then fruitPicture (fruitForLevel game.level) 108 164 else [])

actorsPicture : Game -> List Batch
actorsPicture game =
  let (x, y) = position game.player
      mouth = case game.phase of
        Dying ticks => min pi (cast (90 - ticks) / 75 * pi)
        _ => [0.05, 0.35, 0.75, 0.35] `atFrame` game.frame
      players = map (\offset => chomper (x + offset) y game.player.heading mouth)
                    (if game.player.tile.y == 14 then [-224, 0, 224] else [0])
   in case game.phase of
        Dying _ => players
        _ => players ++ concatMap (ghostPicture game) game.ghosts
  where
    atFrame : List Double -> Int -> Double
    atFrame values frame = case drop (cast ((frame `div` 3) `mod` 4)) values of
      value :: _ => value
      [] => 0.35

hud : Game -> Bool -> List Batch
hud game muted =
  [ label white 19 1 1 "1UP", label white 105 1 1 "HIGH SCORE"
  , label white 13 12 1 (show game.score), label white 117 12 1 (show game.highScore)
  , label white 164 278 1 ("L" ++ show game.level)
  ] ++ map (\i => chomper (16 + cast i * 16) 281 West 0.6) [0 .. min 4 (game.lives - 2)] ++
  (if muted then [label pink 94 278 1 "MUTE"] else []) ++ fruitPicture (fruitForLevel game.level) 211 280

panel : Double -> Double -> Double -> Double -> Batch
panel x y w h = Ink black [MkFRect x y w h]

banner : Color -> String -> List Batch
banner ink text = [panel 66 157 92 15, centered ink 161 1 text]

menu : Game -> List Batch
menu game =
  [ panel 15 61 194 203
  , Ink blue [MkFRect 15 61 194 1, MkFRect 15 263 194 1, MkFRect 15 61 1 203, MkFRect 208 61 1 203]
  , centered yellow 77 3 "CHOMPIT"
  , centered white 108 1 "IDRIS 2 IS"
  , centered cyan 120 1 "PACMAN-COMPLETE"
  ] ++ concatMap (\(identity, x) => ghostAt game.frame False False False identity East x 146)
                     [(Red, 67), (Pink, 97), (Cyan, 127), (Orange, 157)] ++
  [ centered pellet 166 1 "EAT DOTS. DODGE GHOSTS."
  , centered white 187 1 "ARROWS / WASD TO MOVE"
  , centered yellow 207 1 (if game.frame `mod` 60 < 40 then "ENTER TO START" else "")
  , centered white 233 1 "P PAUSE   M MUTE"
  , centered white 247 1 "ESC TO QUIT"
  ]

-- Intermission pictures use the same scratch buffer as the maze sprites.
-- Scaling changes rectangle sizes, not the number of native rectangles.
placePicture : Double -> Double -> Double -> List Batch -> List Batch
placePicture scale x y = map place
  where
    place : Batch -> Batch
    place (Ink ink rects) = Ink ink (map (\(MkFRect u v w h) =>
      MkFRect (floor x + u * scale) (floor y + v * scale) (w * scale) (h * scale)) rects)

scenePlayer : Int -> Direction -> Double -> Double -> Double -> List Batch
scenePlayer tick heading scale x y =
  let beat = (tick `div` 6) `mod` 4
      mouth = if beat == 0 then 0.05 else if beat == 2 then 0.75 else 0.35
   in placePicture scale x y [chomper 0 0 heading mouth]

chasePass : Bool -> Int -> List Batch
chasePass patched tick =
  let player = 244 - 1.8 * cast tick
      ghost = player + 44
   in scenePlayer tick West 1 player 152 ++ ghostAt tick False False False Red West ghost 152 ++
      (if patched then [Ink white [MkFRect (floor ghost + 2) 152 4 4],
                        Ink red [MkFRect (floor ghost + 3) 153 2 2]] else [])

looseCostume : Int -> Double -> List Batch
looseCostume tick x =
  let y = 158 + cast ((tick `div` 8) `mod` 2)
   in [ Ink red [MkFRect (floor x - 8) y 17 4, MkFRect (floor x - 5) (y - 3) 10 3]
      , Ink white [MkFRect (floor x - 3) (y - 1) 4 3]
      ]

bareGhost : Int -> Double -> List Batch
bareGhost tick x =
  let foot = cast ((tick `div` 6) `mod` 2)
   in [ Ink pellet (pixels x 155 (\dx, dy => dx * dx * 4 + dy * dy * 9 < 144))
      , Ink orange [MkFRect (floor x - 5) (159 + foot) 4 3, MkFRect (floor x + 1) (160 - foot) 4 3]
      , Ink white [MkFRect (floor x - 3) 152 2 3, MkFRect (floor x + 1) 152 2 3]
      , Ink blue [MkFRect (floor x - 2) 153 1 2, MkFRect (floor x + 2) 153 1 2]
      ]

snagPicture : Int -> List Batch
snagPicture tick =
  let tug = 128 - cast (min 24 ((tick - 80) `div` 8)) - cast ((tick `div` 12) `mod` 2) * 2
      freed = 104 - cast (max 0 (tick - 360)) * 2
      nail = [Ink white [MkFRect 143 159 2 6, MkFRect 141 158 6 2]]
      player = scenePlayer tick West 1 (244 - 2 * cast tick) 152
      approach = ghostAt tick False False False Red West (288 - 2 * cast tick) 152
      pulling = [Ink red [MkFRect (tug + 4) 155 (141 - tug) 7]] ++
        ghostAt tick False False False Red (if tick `mod` 60 < 30 then West else East) tug 152 ++
        (if tick < 180 then [label white 145 134 1 "!"] else [])
      torn = ghostAt tick False False False Red (if tick < 360 then East else West) freed 152 ++
        [Ink black [MkFRect (freed + 2) 155 6 5], Ink pellet [MkFRect (freed + 1) 159 5 3]] ++
        looseCostume tick 141 ++
        (if tick < 318 then [Ink white [MkFRect 136 148 2 4, MkFRect 147 150 4 2,
                                        MkFRect 135 163 3 2]] else [])
   in (if tick < 80 then player ++ approach
       else if tick < 300 then player ++ pulling else torn) ++ nail

intermissionPicture : Interlude -> Int -> List Batch
intermissionPicture scene remaining =
  let tick = max 0 (min (intermissionDuration - 1) (intermissionDuration - remaining))
      title = case scene of Turnabout => "TURNABOUT"; Snag => "LOOSE THREAD"; Costume => "QUICK CHANGE"
      returning : Double = -20 + 1.5 * cast (tick - 210)
      actors : List Batch = case scene of
        Turnabout => if tick < 180 then chasePass False tick else if tick < 210 then [] else
          ghostAt tick True False False Red East returning 152 ++
          scenePlayer tick East 3 (returning - 64) 139
        Snag => snagPicture tick
        Costume => if tick < 180 then chasePass True tick else if tick < 210 then [] else
          looseCostume tick (returning - 25) ++
          [Ink pellet [MkFRect (floor returning - 20) 157 15 1]] ++ bareGhost tick returning
   in [centered white 66 1 "INTERMISSION", centered yellow 87 1 title,
       Ink blue [MkFRect 16 164 192 1]] ++ actors ++
      [centered white 236 1 "ENTER TO SKIP", centered pellet 250 1 "P PAUSE   M MUTE"]

overlay : Game -> List Batch
overlay game = if game.paused then banner yellow "PAUSED" else case game.phase of
  Title => menu game
  Ready _ => banner yellow "READY!"
  GameOver => banner red "GAME OVER" ++ [panel 48 182 128 15, centered white 186 1 "ENTER TO RETRY"]
  _ => case game.popup of
    Nothing => []
    Just (tile, value, _) => [label cyan (cast (tile.x * 8 - 4)) (cast (tile.y * 8 + 24)) 1 (show value)]

drawGame : Display -> Game -> Bool -> IO (Either String ())
drawGame display game muted = case game.phase of
  Intermission scene ticks => do
    True <- paint display (intermissionPicture scene ticks ++ hud game muted ++
                           if game.paused then banner yellow "PAUSED" else [])
      | False => Left <$> getError
    pure (Right ())
  _ => do
    let wallColor = case game.phase of
          Clearing ticks => if ticks `mod` 30 < 15 then white else blue
          _ => blue
    let Just layer = find (\layer => layer.layoutId == game.maze.layoutId) display.walls
      | Nothing => pure (Left "The maze wall buffer is missing. Restart Chompit.")
    True <- color display.renderer wallColor | False => Left <$> getError
    True <- fillRects display.renderer layer.buffer layer.count | False => Left <$> getError
    True <- paint display (foodPicture game ++ actorsPicture game ++ hud game muted ++ overlay game)
      | False => Left <$> getError
    pure (Right ())

export
render : Display -> Game -> Bool -> IO (Either String ())
render display game muted = do
  True <- color display.renderer black | False => Left <$> getError
  True <- clear display.renderer | False => Left <$> getError
  Right () <- drawGame display game muted | Left err => pure (Left err)
  True <- present display.renderer | False => Left <$> getError
  pure (Right ())
