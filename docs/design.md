# Design

Chompit separates game rules from SDL operations.  `Chompit.Types`, `Chompit.Maze`, and
`Chompit.Game` use `%default total`.  The compiler requires these functions to cover every input and
terminate.  This does not prove that the game rules match the arcade machine.

## Source map

| File | Responsibility |
| --- | --- |
| `src/Chompit/Types.idr` | Positions, actors, directions, phases, commands, and sound cues |
| `src/Chompit/Maze.idr` | Five maze layouts, pellets, tunnel neighbors, and routes to the house |
| `src/Chompit/Game.idr` | Movement, ghost decisions, timers, collisions, score, and level changes |
| `src/Chompit/Input.idr` | SDL events to game commands |
| `src/Chompit/Font.idr` | Original 5 × 7 bitmap alphabet |
| `src/Chompit/Render.idr` | Wall outlines, sprites, text, and rectangle batches |
| `src/Chompit/Audio.idr` | Reusable mixer tracks, sound cues, loops, pause, and mute |
| `src/Main.idr` | Options, resource scopes, event polling, frame timing, and smoke scenarios |
| `test/src/Main.idr` | Simulation and input tests |
| `tools/generate_audio.py` | Deterministic synthesis of twelve WAV files |
| `test/src/test_audio.py` | Audio format, amplitude, endpoints, and reproducibility tests |

## Simulation and movement

A fixed update advances the simulation by 1/60 second.  The main loop accumulates elapsed time and
permits at most six updates per rendered frame.  It discards time beyond 100 milliseconds after a
stall.  Paused frames discard accumulated time, so resuming does not trigger delayed movement.

An actor stores a tile, a direction, and progress toward the next tile.  Progress uses integer units
of 1/256 tile.  An update cannot move an actor by a whole tile.  At each tile center, the player
tries the queued direction before the current direction.  A reversal changes the actor's tile and
progress without changing its position.  Tunnel rendering draws copies at both edges, and collision
distances wrap across those edges.

Ghosts choose from legal directions in up, left, down, right order.  Equal target distances keep
that order.  Normal ghosts avoid reversing except at a dead end or after a mode change.  Frightened
ghosts use a deterministic pseudo-random choice, a repeatable sequence of direction choices.
Returning eyes follow precomputed shortest distances to the house.  The house and its door block the
player and hunting ghosts.

`Game` contains all mutable game state as an immutable value.  An update returns a new value and
appends sound cues to it.  The main loop plays the cues once, then clears them.  Score popups,
capture freezes, death animations, and level-clear flashes use simulation timers.  Pausing stops all
of those timers and pauses the mixer tracks.

## Mazes and level changes

`buildMaze level` selects one of five 28 × 31 layouts.  `Maze.layoutId` identifies the selected
layout independently of the difficulty level.  All layouts share the player spawn, ghost house,
fruit position, and side tunnel.  The first layout uses the classic maze, and the other four are
original designs.

| Layout | Dots | Power pellets |
| --- | --- | --- |
| 1. Classic | 240 | 4 |
| 2. Crossroads | 254 | 4 |
| 3. Switchback | 246 | 4 |
| 4. Courtyard | 248 | 4 |
| 5. Circuit | 256 | 4 |

The last pellet starts a 120-update completion animation.  The game then loads the next layout,
including its cells, pellets, and shortest routes to the house.  Actors and round timers reset,
followed by a 120-update ready countdown.  Score, high score, lives, and the extra-life award status
carry over.  Death keeps the current layout and collected pellets, but a retry starts at level one.

After level five, layouts repeat while the level number continues to increase.  Speed, fruit value,
and power-pellet duration still use that level number.  This layout cycle is an intentional
difference from the arcade game.

## Drawing and ownership

The logical display is 224 × 288 pixels.  Each tile occupies eight pixels, with score and life
panels outside the maze.  The renderer adds borders when the window has different proportions.
Sprites and text use filled pixel rectangles instead of textures or font files.

Before the frame loop, the renderer computes wall outlines for all five layouts.  It stores each
layout in a separate reusable rectangle buffer.  Each frame selects the wall buffer that matches
`Maze.layoutId` and reuses another buffer for sprites, pellets, and text.  The main loop owns one
event buffer and a fixed set of mixer tracks.  No application-owned native buffer or audio track is
created in the frame loop.  Idris still allocates managed values during simulation and drawing.

All SDL calls run on the main thread.  Scoped helpers release resources on ordinary success and
error returns.  They release rectangle and event buffers before the renderer, and the renderer
before the window.  Audio tracks retain their loaded assets and are destroyed before the mixer.  SDL
shuts down last.  The [library resource
contract](https://github.com/ska80/idris2-sdl3/blob/master/docs/resources.md) defines the remaining
safety limits.

A renderer device reset exits with an error rather than using an invalid renderer.  A target reset
needs no texture recovery because Chompit does not use render-target textures.  Focus loss pauses
the game, and only events for its window affect keyboard controls.  The event loop processes at most
128 queued events per frame.
