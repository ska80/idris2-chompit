# Arcade rules

The speed tables, ghost release rules, mode schedules, frightened flash counts, and player corner
limits follow Jamey Pittman's [The Pac-Man Dossier](https://pacman.holenet.info/).  The reference
sections are Chapter 2, Blinky in Chapter 4, and Table A.1.  Chompit uses the normal difficulty
table.  Pellet counts include ordinary dots and power pellets.

`Chompit.Game` applies these rules without SDL or file access.  `test/src/Arcade.idr` tests their
boundaries, including later levels and recovery after death.  `test/src/GhostTiming.idr` tests
delayed reversals and warning colors.  `test/src/House.idr` tests house paths, position continuity,
and revival.  `test/src/Cornering.idr` tests player turns, diagonal paths, and collisions in every
layout.  This is a rule model, not an emulator of the original hardware.

## Movement speeds

The reference speed of 100% is approximately 75.757576 pixels per second.  These percentages apply
while an actor moves freely.  Frightened columns apply only while power-pellet protection is active.

| Levels | Player | Powered player | Ghost | Frightened ghost | Tunnel ghost |
| --- | --- | --- | --- | --- | --- |
| 1 | 80% | 90% | 75% | 50% | 40% |
| 2–4 | 90% | 95% | 85% | 55% | 45% |
| 5–20 | 100% | 100% | 95% | 60% | 50% |
| 21 onward | 90% | None | 95% | None | 50% |

A dot stops the player for one update, and a power pellet stops it for three updates.  These stops
produce the lower average speed while eating.  The game does not also apply a separate dot-speed
multiplier.  Tunnel speed takes priority over frightened speed for ghosts.

A tile is an eight-pixel square of the maze.  Coordinates start at `(0, 0)` in the maze's upper-left
corner.  Movement uses units of 1/256 tile at 60 updates per second.  `speedStep` distributes
fractional movement over 99 updates instead of rounding every update to the same integer.  At a
constant speed, every uninterrupted 99-update interval covers the same distance.  This preserves the
average reference speed without copying the arcade machine's pixel movement pattern.

## Player cornering

A pre-turn starts before a junction's center.  A post-turn starts after it.  The limits follow the
[cornering section](https://pacman.holenet.info/#CH2_Cornering) and its directional pixel diagram.
Both limits include their boundary position.

| Incoming direction | Early limit in pixels | Late limit in pixels |
| --- | --- | --- |
| Right (east) | 3 | 4 |
| Left (west) | 4 | 3 |
| Down (south) | 4 | 3 |
| Up (north) | 3 | 4 |

A queued turn starts at the early limit.  Movement left in the update continues along the diagonal.
The player faces the new direction without a position jump.  Ghosts still turn at tile centers.

The centerline runs through the middle of a corridor.  During a turn, both axes use the scheduled
movement distance until the player reaches the new centerline.  Early turns drift forward toward
that line, while late turns drift back toward it.  Remaining movement follows the new centerline.
An earliest possible pre-turn gains three or four pixels along the exit.

Starting a corner selects the junction tile for pellet collection.  Pellet stalls, pause, and
capture freezes hold both coordinates.  Drawing, ghost collisions, and fruit pickup use the full
position.  Blocked exits stay blocked, including the ghost house door.

A perpendicular turn changes direction by 90 degrees.  Chompit finishes the current diagonal before
accepting another such turn.  Reversals remain immediate and retain the correction toward the
centerline.  If a reversal meets a wall, the player finishes that correction without entering the
wall.  These input rules and fractional distances are intentional differences from pixel-step
emulation.

## Scatter and chase

Scatter targets the ghosts' home corners, and chase uses their individual player targets.  All
intervals in this table are seconds.  Frightened time, capture freezes, and pause stop the mode
clock.  Death and level completion reset it.

| Period | Level 1 | Levels 2–4 | Levels 5 onward |
| --- | --- | --- | --- |
| Scatter 1 | 7 | 7 | 5 |
| Chase 1 | 20 | 20 | 20 |
| Scatter 2 | 7 | 7 | 5 |
| Chase 2 | 20 | 20 | 20 |
| Scatter 3 | 5 | 5 | 5 |
| Chase 3 | 20 | 1,033 | 1,037 |
| Scatter 4 | 5 | 1/60 | 1/60 |
| Chase 4 | Permanent | Permanent | Permanent |

Each scatter/chase change requests a reversal.  A power pellet also requests one, even on levels
with no frightened time.  Frightened expiry does not request another reversal.

A hunting ghost keeps its heading until the next tile center.  There it reverses the incoming
direction before choosing any junction turn.  It spends the remaining movement for that update in
the new direction.  The chosen heading stays fixed until the following center.

The one-update fourth scatter sends requests on successive updates.  Multiple requests before the
same arrival cause only one reversal.  Ghosts at different positions can reverse on different
updates.  Capture clears a pending request, and returning eyes ignore new requests.

## Frightened warning flashes

Frightened ghosts alternate between blue and white before protection ends.  The white flash count
follows the level number, not the maze layout.  Protection durations include these flashes.

| Levels | Protection in seconds | White flashes |
| --- | --- | --- |
| 1 | 6 | 5 |
| 2, 6, 10 | 5 | 5 |
| 3 | 4 | 5 |
| 4, 14 | 3 | 5 |
| 5, 7, 8, 11 | 2 | 5 |
| 9, 12, 13, 15, 16, 18 | 1 | 3 |
| 17, 19 onward | 0 | 0 |

Each color interval lasts fourteen updates.  The [masonicGIT
implementation](https://github.com/masonicGIT/pacman/blob/master/src/energizer.js) also uses this
interval.  Chompit places the last white interval in the final fourteen protected updates.  Short
durations truncate the first white interval instead of extending protection.  One-second protection
starts with four white updates, and two-second protection starts with eight.

The remaining protection time determines the color, not the global animation frame.  Pause and
capture freezes therefore hold the current color.  A new power pellet restarts the level's sequence.
Waiting and leaving bodies use the same colors as hunting ghosts.  Returning eyes never flash.
Revived bodies resist the current power pellet but can flash after another one.

## Leaving the house

Only the preferred waiting ghost counts each new pellet.  Priority is pink, then cyan, then orange.
Personal counts start at zero on each level and remain stored after a ghost leaves.  The limits are:

| Levels | Pink | Cyan | Orange |
| --- | --- | --- | --- |
| 1 | 0 | 30 | 60 |
| 2 | 0 | 0 | 50 |
| 3 onward | 0 | 0 | 0 |

At level one, cyan counts the first 30 pellets after pink leaves.  Orange then starts its own count
of 60.  Red starts outside the house and never waits for pellets after returning as eyes.

After death, one shared count replaces the personal counts without erasing them.  Pink leaves at
seven pellets, and cyan leaves at seventeen.  At 32, the shared count turns off if orange is still
inside.  Personal counts then resume, including orange's stored count and limit.

The original shared-counter trap is retained.  If orange leaves before the count reaches 32, the
shared count stays active.  Returned ghosts can then miss their release values.  The idle timer
still frees them if the player stops eating long enough.

The idle timer forces the preferred waiting ghost out after four seconds without a pellet.  From
level five, the limit is three seconds.  Eating a pellet or forcing a release resets this timer.  It
continues to count while the house is empty.  A pellet eaten on the timeout update prevents a forced
release.

Ghosts normally turn left after leaving the house.  A mode reversal or power pellet while inside
changes their eventual exit direction to the right.  Their release counts do not control the time
needed to move through the door.

## House paths

Waiting ghosts move up and down between rows 13.5 and 14.5.  Cyan uses column 11.5, pink uses 13.5,
and orange uses 15.5.  Pink initially faces down, while cyan and orange face up.  Red starts
outside, centered above the door, and shares pink's lane when it returns.

Release first moves a ghost sideways at its current height to column 13.5.  It then moves straight
up through the center of the door at `(13.5, 11)`.  The ghost turns in its remembered exit direction
without jumping to a tile center.

Eyes follow the maze route to the entrance, align with the door, and descend to row 14.5.  They then
move sideways to their own lane.  The body returns only at that point, and pellet release rules
resume on the next update.  Entering eyes remain invulnerable and ignore reversal signals and power
pellets.  The returning-eyes sound continues until all captured ghosts regain their bodies.

Pacing and departure use 40% of the reference speed on every level.  Eyes move two pixels per
update, including inside the house.  These rates and paths follow the [masonicGIT ghost
implementation](https://github.com/masonicGIT/pacman/blob/master/src/Ghost.js) and its [house
geometry](https://github.com/masonicGIT/pacman/blob/master/src/Map.js).  Chompit uses fractional
movement rather than the original pixel-step pattern.  Remaining movement continues around bends,
but revival ends the current movement update at the slot.

## Red's late-maze acceleration

Cruise Elroy is Red's two-stage speed increase near maze completion.  The thresholds count pellets
still on the board.  The first stage adds five percentage points to Red's normal speed, and the
second adds ten.  The other three ghosts keep their normal speeds.

| Levels | First stage | Second stage |
| --- | --- | --- |
| 1 | 20 | 10 |
| 2 | 30 | 15 |
| 3–5 | 40 | 20 |
| 6–8 | 50 | 25 |
| 9–11 | 60 | 30 |
| 12–14 | 80 | 40 |
| 15–18 | 100 | 50 |
| 19 onward | 120 | 60 |

While accelerated, Red targets the player during scatter but still reverses at mode changes.  Death
disables both the speed increase and the scatter override until orange starts leaving the house.  A
new level restores normal threshold handling.  All layouts use these absolute pellet counts, even
when their initial pellet totals differ.

## Restricted upward turns

Maze coordinates start at `(0, 0)` in the upper-left corner.  Normal ghosts cannot choose an upward
exit at `(12, 11)`, `(15, 11)`, `(12, 23)`, or `(15, 23)`.  The player, frightened ghosts, and
returning eyes do not have this restriction.  Forced reversals also bypass it.

In the four original layouts, this rule applies only where both horizontal exits exist.  A corner
cannot become a dead end because of the restriction.  Tests cover every valid incoming direction at
every passage tile in all five layouts.

## Intermissions

Intermissions are short animations between levels.  Three arcade-inspired scenes follow this
schedule.  Each lasts eight seconds, with the completed round held unchanged in memory.

| Completed level | Scene | Action |
| --- | --- | --- |
| 2 | Turnabout | A giant player chases the frightened red ghost back across the screen |
| 5 | Loose Thread | Red catches its costume on a nail and tears it free |
| 9, 13, 17 | Quick Change | Red returns without its costume and drags it away |

The scenes use original pixel art, motion, and music rather than copies of the arcade presentation.
Their timing and controls are intentional differences.  Enter or Space skips an unpaused scene, P
pauses it, and M mutes it.  The next level loads after completion or skipping, with score and lives
preserved.  No intermissions occur after level 17.

## Remaining differences

Chompit deliberately keeps several simpler rules and presentation choices:

- The player finishes a diagonal before starting another perpendicular turn.
- Ghosts choose junction exits on arrival instead of looking one tile ahead.
- Collisions use distance between actors rather than tile comparisons.
- Frightened choices use Chompit's own repeatable random sequence, reset after death or a new level.
- Fruit lasts a fixed ten seconds.
- Five layouts repeat beyond level 256 without the arcade game's split-screen failure.

Original graphics, synthesized audio, gameplay music, and saved high scores are also intentional
choices.  [TODO.md](../TODO.md) lists the remaining work.
