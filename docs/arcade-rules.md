# Arcade rules

The speed tables, ghost release rules, and mode schedules follow Jamey Pittman's [The Pac-Man
Dossier](https://pacman.holenet.info/).  The reference sections are Chapter 2, Blinky in Chapter 4,
and Table A.1.  Chompit uses the normal difficulty table.  Pellet counts include ordinary dots and
power pellets.

`Chompit.Game` applies these rules without SDL or file access.  `test/src/Arcade.idr` tests their
boundaries, including later levels and recovery after death.  This is a rule model, not an emulator
of the original hardware.

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

A tile is an eight-pixel square of the maze.  Movement uses units of 1/256 tile at 60 updates per
second.  `speedStep` distributes fractional movement over 99 updates instead of rounding every
update to the same integer.  At a constant speed, every uninterrupted 99-update interval covers the
same distance.  This preserves the average reference speed without copying the arcade machine's
pixel movement pattern.

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

Each scatter/chase change reverses hunting ghosts.  The one-update fourth scatter therefore causes
two reversals on successive updates.  A power pellet also reverses ghosts, including on levels with
no frightened time.  Level 17 and levels 19 onward have no protection.  Level 18 restores one second
of protection.

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
returning eyes do not have this restriction.

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

- Turns occur at tile centers, without the arcade player's early cornering.
- Hunting ghosts reverse immediately rather than waiting to enter another tile.
- Collisions use distance between actors rather than tile comparisons.
- Waiting ghosts remain still, and house exits and returning eyes use fixed speeds.
- Frightened choices use Chompit's own repeatable random sequence, reset after death or a new level.
- Frightened warning flashes use a simple timer rather than the level-specific flash counts.
- Fruit lasts a fixed ten seconds.
- Five layouts repeat beyond level 256 without the arcade game's split-screen failure.

Original graphics, synthesized audio, gameplay music, and saved high scores are also intentional
choices.  [TODO.md](../TODO.md) lists the remaining work.
