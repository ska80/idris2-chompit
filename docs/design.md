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
| `src/Chompit/Fruit.idr` | Original 16 × 16 artwork for eight bonus tiers |
| `src/Chompit/HighScore.idr` | Score-file parsing, storage paths, and checkpoint writes |
| `src/Chompit/Render.idr` | Wall outlines, sprites, text, and rectangle batches |
| `src/Chompit/Audio.idr` | Reusable mixer tracks, sound cues, loops, pause, and mute |
| `src/Main.idr` | Options, resource scopes, event polling, frame timing, and smoke scenarios |
| `test/src/Main.idr` | Simulation, input, and audio transition tests |
| `test/src/Arcade.idr` | Arcade speed tables, release counters, mode schedules, and turn restrictions |
| `test/src/GhostTiming.idr` | Delayed reversals, movement remainders, and frightened flash schedules |
| `test/src/House.idr` | House pacing, centered paths, revival, and returning-eyes audio |
| `test/src/Cornering.idr` | Early and late player turns, diagonal geometry, controls, and collisions |
| `test/src/Intermissions.idr` | Scene timing, frozen round state, controls, and music transitions |
| `tools/generate_audio.py` | Deterministic synthesis of eighteen WAV files |
| `test/src/test_audio.py` | Audio format, signal level, repeat boundaries, and reproducibility tests |
| `test/src/test_high_score.py` | Isolated score-file and process-restart tests |
| `test/src/score_input.c` | SDL keyboard and quit events for normal-path score tests |

## Simulation and movement

A fixed update advances the simulation by 1/60 second.  The main loop accumulates elapsed time and
permits at most six updates per rendered frame.  It discards time beyond 100 milliseconds after a
stall.  Paused frames discard accumulated time, so resuming does not trigger delayed movement.

An actor stores a tile, a direction, progress toward the next tile, and `offset` for player corners.
Progress and `offset` use integer units of 1/256 tile.  An update cannot move an actor by a whole
tile.  An immediate player reversal changes its tile and progress but preserves `offset` and its
position.  Tunnel rendering draws copies at both edges, and collision distances wrap across those
edges.

Ghosts choose from legal directions in up, left, down, right order.  Equal target distances keep
that order.  Normal ghosts avoid reversing except at a dead end or after a mode change.  Frightened
ghosts use a deterministic pseudo-random choice, a repeatable sequence of direction choices.
Returning eyes follow precomputed shortest distances to `houseEntrance`, beside the door.  The house
and its door block the player and hunting ghosts.

`Ghost.reversePending` records a requested reversal.  `requestReverse` sets it without moving the
ghost, and repeated requests before arrival share one reversal.  `moveGhost` applies it at the next
tile center before any junction choice.  Remaining movement continues in the reversed direction.
The selected heading stays fixed between centers, including when arrival leaves zero movement.

Waiting and leaving ghosts remember an eastward house exit instead.  Capture clears a pending
reversal, and eyes ignore requests.  Death, retry, and new levels reset pending reversals.  Pause,
capture freezes, and intermissions preserve them.

`restrictedUp` excludes four upward turns for normal ghosts.  It requires both horizontal exits, so
the restriction cannot block a corner in an original layout.

`playerSpeed` and `huntingSpeed` return percentages of the reference arcade speed.  `speedStep`
converts a percentage to movement units for the current update.  Its 99-update pattern preserves
fractional speed without floating-point positions.  The siren uses the percentage, not the changing
per-update distance.  `isScatter` takes both a level number and elapsed mode time.

`ReleaseCounters` stores three personal pellet counts, an optional shared count, and the idle timer.
Death enables the shared count but preserves personal counts.  Each new level resets all counts.
The record also holds the temporary block on Red's acceleration after death.  House states retain
the direction to take after leaving the door, rather than a fixed release delay.

Each active update handles satisfied release counts before player movement.  It counts a newly eaten
pellet and handles releases again afterward.  This frees zero-limit ghosts before counting for the
next ghost.  The idle timeout runs after consumption, so a pellet on that update cancels it.  See
[arcade rules](arcade-rules.md) for the source tables and intentional differences.

`Game` contains all mutable game state as an immutable value.  An update returns a new value and
appends sound cues to it.  The main loop plays the cues once, then clears them.  Score popups,
capture freezes, death animations, and level-clear flashes use simulation timers.  Pausing stops all
of those timers and pauses the mixer tracks.

`frightFlashes` supplies each level's white flash count.  `isFlashing` derives a ghost's warning
color from the remaining protection time, with fourteen updates per color.  The final white interval
ends with protection, and short durations truncate the first white interval.  Capture freezes hold
the color even while the global frame count advances.  Eyes and revived bodies never flash under the
current power pellet.

## Player cornering

The centerline runs through the middle of a corridor.  `Actor.offset` stores a sideways distance
from that line.  `MkActor` defaults this field to zero, so ordinary actors keep their existing
positions.  Only player turns change it.  `actorPosition` includes this distance for rendering,
ghost collisions, and fruit pickup.

`movePlayer` handles the queued direction separately from ghost movement.  `preTurnLimit` and
`postTurnLimit` give the directional three- or four-pixel limits.  A turn selects the junction tile,
changes heading, and stores the old physical displacement in `offset`.  The position does not jump.
The junction pellet can then be collected even though an early turn never crosses its center.

Each unit of movement advances along the new heading and reduces the sideways distance by one unit.
Once that distance reaches zero, remaining movement follows the new corridor.  A blocked exit cannot
start a turn.  Reversals preserve the sideways distance and continue reducing it, even if forward
movement reaches a wall.

A perpendicular turn changes direction by 90 degrees.  A second such turn waits for the current
diagonal to align.  Movement left in the update can enter another turn immediately after alignment.
The walker limits requests to 255 units and uses at most five movement or direction-change stages.
This bound preserves totality without discarding normal movement at a turn boundary.

Pellet stalls, pause, ready countdowns, capture freezes, and intermissions hold the player's
physical position.  Pause and intermissions also ignore direction commands.  Death, retry, and new
levels restore zero `offset`.  Tests compare complete movement updates with one-unit steps and
exercise every legal junction in all layouts.  The [arcade rule
notes](arcade-rules.md#player-cornering) describe the directional limits and intentional
differences.

## House movement

`Ghost.housePosition` stores a separate point during pacing, departure, and entry.  It uses the same
1/256-tile units as corridor movement, but permits positions between tile centerlines.  The actor
still supplies a heading and tile for queries.  `ghostPosition` supplies the full position for
drawing.  This point is managed Idris data, not a native buffer.

A waypoint is a point where a path changes direction.  Each update follows at most four path
segments.  The walker stops each segment at its waypoint and carries remaining movement into the
next segment.  Waiting ghosts reverse at the upper and lower bounds.  Departing ghosts first reach
the center column, then cross the door and resume corridor movement without a position jump.
Departure clears `housePosition`.

`Entering` keeps returning eyes on a separate path through the door and toward their own lane.
`isReturning` includes both corridor eyes and entering eyes, so their appearance and warning sound
continue until revival.  The body appears at the lower bound of its lane, faces up, and resists the
current power pellet.  Release rules resume on the next update without changing stored counters.

House movement uses 40% of the reference speed at every level.  Eyes use two pixels per update.
Pause, ready countdowns, capture freezes, and intermissions hold the house positions.  Death, retry,
and new levels restore the starting positions and headings.

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

The last pellet starts a 120-update completion animation.  On scheduled levels, a 480-update
intermission follows before the next layout loads.  Other levels proceed directly to the next
layout, including its cells, pellets, and shortest routes to the house.  Actors and round timers
reset, followed by a 120-update ready countdown.  Score, high score, lives, and the extra-life award
status carry over.  Death keeps the current layout and collected pellets, but a retry starts at
level one.

After level five, layouts repeat while the level number continues to increase.  Speed, fruit value,
and power-pellet duration still use that level number.  This layout cycle is an intentional
difference from the arcade game.

## Intermissions

`intermissionFor` selects a scene from the completed difficulty level, not the layout number.  The
`Intermission` phase stores its `Interlude` kind and remaining updates.  Only that countdown and the
frame count advance during a scene.  Actors, pellets, scores, lives, and round timers stay unchanged
until the next level loads.

Enter or Space skips an unpaused scene through the same `nextLevel` function as normal completion.
Movement commands have no effect during a scene.  Pause and focus loss hold its countdown, and
muting changes only audio output.  The next level still waits through its ready countdown.

The renderer replaces the maze with a scene on a black background.  It derives positions, poses, and
mouth animation from the scene countdown, not elapsed wall time.  Large sprites scale existing
rectangles instead of allocating more native buffers.  The score display remains visible, and paused
frames show the usual banner.

The smoke script holds its gameplay index while each scene runs.  It records all four quarters of
each scene and adds a fifteen-frame pause.  Both native runs render 2,505 frames, including three
complete intermissions.  Later segments follow all four ghosts through entry, revival, and
departure.  They also draw early and late player turns on both axes, with pause and reversal during
a diagonal.  The [arcade rule notes](arcade-rules.md#intermissions) list the scene schedule and
intentional differences.

## Saved high scores

`Chompit.HighScore` keeps file access outside the simulation.  It selects an absolute state
directory from `XDG_STATE_HOME`, with `$HOME/.local/state` as the fallback.  It reads at most 65
bytes and accepts one nonnegative decimal integer that fits an Idris `Int`.  Files larger than 64
bytes or containing invalid data load as zero.  Unreadable storage disables persistence for the
session and prints a warning.

The loop saves new records at death, level completion, pause, or exit, not after each pellet.
Before writing, the store reads the existing score again and keeps the larger value.  It exclusively
creates a temporary file beside the score, flushes the write, then replaces the old file with one
rename.  A failed write preserves the previous file and disables further saves for that run.  The
Linux C library supplies the file operations that the Idris standard library does not expose.

Temporary names include the process ID, and exclusive creation rejects existing files and symlinks.
Simultaneous saves from different processes are not coordinated.  The store does not guarantee
recovery after a power failure.  `--no-save` and `--smoke` skip both score reads and writes.

## Audio

The title screen uses its own music loop.  Active play mixes a quiet 32-second music loop with the
normal siren, power-pellet warning, or returning-eyes warning.  The generated music uses soft tones
and leaves room for the existing effects.  This background music is an intentional addition to the
arcade rules.

`loopChanges` lists the loops to stop and start after a game update.  Shared loops keep their
playback positions, so changing a warning never restarts the music.  Gameplay music fades out over
80 milliseconds when active play ends.  The next period of play starts the music from the beginning.
Pausing holds every track at its current position, and muting changes only the mixer output level.

`huntingSpeed` supplies both ghost movement and siren selection.  The four sirens cover speed bands
up to 75%, 85%, 95%, and 105% of the reference speed.  Red's late-maze acceleration can raise the
siren, but temporary tunnel slowdowns do not.  Returning eyes override frightened audio, which
overrides the normal siren.  Once all eyes reach their own house slots and regain their bodies, the
current warning resumes.

Intermissions use one separate eight-second music loop without gameplay music or warnings.
Completion and skipping fade it out over 80 milliseconds.  Pause holds its playback position, and
the next ready countdown stays silent.

All eighteen tracks and their looping options are created before the frame loop.  Gameplay and
intermission tracks each supply their own sample rate for the fade duration, including with custom
assets.  Tracks retain their decoded audio until cleanup.

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
