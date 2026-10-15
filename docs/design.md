# Design

Chompit separates game rules from SDL operations.  `Chompit.Types`, `Chompit.Maze`, and
`Chompit.Game` use `%default total`.  The compiler requires these functions to cover every input and
terminate.  This does not prove that the game rules match the arcade machine.

## Source map

| File | Responsibility |
| --- | --- |
| `src/Chompit/Types.idr` | Positions, actors, directions, phases, commands, and sound cues |
| `src/Chompit/Maze.idr` | Maze cells, pellets, tunnel neighbors, and routes to the house |
| `src/Chompit/Game.idr` | Movement, ghost decisions, timers, collisions, score, and level changes |
| `src/Chompit/Input.idr` | SDL events to game commands |
| `src/Chompit/Font.idr` | Original 5 × 7 bitmap alphabet |
| `src/Chompit/Render.idr` | Wall outlines, sprites, text, and rectangle batches |
| `src/Chompit/Audio.idr` | Reusable mixer tracks, sound cues, loops, pause, and mute |
| `src/Main.idr` | Options, resource scopes, event polling, frame timing, and smoke scenarios |
| `src/TestMain.idr` | Simulation and input tests |
| `tools/generate_audio.py` | Deterministic synthesis of twelve WAV files |
| `tools/test_audio.py` | Audio format, amplitude, endpoints, and reproducibility tests |

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

## Drawing and ownership

The logical display is 224 × 288 pixels.  Each tile occupies eight pixels, with score and life
panels outside the maze.  The renderer adds borders when the window has different proportions.
Sprites and text use filled pixel rectangles instead of textures or font files.

The renderer computes wall outlines once and uploads them to a reusable rectangle buffer.  Each
frame reuses another buffer for sprites, pellets, and text.  The main loop owns one event buffer and
a fixed set of mixer tracks.  No application-owned native buffer or audio track is created in the
frame loop.  Idris still allocates managed values during simulation and drawing.

All SDL calls run on the main thread.  Scoped helpers release resources on ordinary success and
error returns.  They release rectangle and event buffers before the renderer, and the renderer
before the window.  Audio tracks retain their loaded assets and are destroyed before the mixer.  SDL
shuts down last.  The [library resource contract](../../idris2-sdl3/docs/resources.md) defines the
remaining safety limits.

A renderer device reset exits with an error rather than using an invalid renderer.  A target reset
needs no texture recovery because Chompit does not use render-target textures.  Focus loss pauses
the game, and only events for its window affect keyboard controls.  The event loop processes at most
128 queued events per frame.
