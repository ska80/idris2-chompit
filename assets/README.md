# Assets

Chompit draws its sprites, wall outlines, and bitmap font in Idris.  The palette uses black, blue,
yellow, red, pink, cyan, orange, green, white, and pale pink pellets.  The graphics do not require
external image or font files.  `menu.png` shows the starting menu, and `screenshot.png` shows
gameplay.  Both images show actual software-rendered frames.

Each bonus tier has an original 16 × 16 icon in `src/Chompit/Fruit.idr`.  The maze bonus and the
icon below the maze use the same artwork for the current level.

| Levels | Bonus | Points |
| --- | --- | --- |
| 1 | Cherries | 100 |
| 2 | Strawberry | 300 |
| 3–4 | Orange | 500 |
| 5–6 | Apple | 700 |
| 7–8 | Melon | 1,000 |
| 9–10 | Galaxian ship | 2,000 |
| 11–12 | Bell | 3,000 |
| 13 onward | Key | 5,000 |

The seventeen original audio files in `assets/sounds/` are tracked in Git.
`tools/generate_audio.py` recreates them with only the Python standard library.  Each file contains
mono, signed 16-bit PCM at 22,050 Hz.  PCM stores the waveform as a sequence of samples.  The
synthesis uses tones, pitch sweeps, and short melodies, with quiet endpoints to reduce clicks.

| Filename | Use |
| --- | --- |
| `title.wav` | Looping title music |
| `gameplay.wav` | Quiet gameplay music, alongside the warning loops |
| `begin.wav` | Start jingle |
| `chomp-low.wav`, `chomp-high.wav` | Alternating pellet sounds |
| `power.wav` | Power-pellet cue |
| `eat-ghost.wav` | Ghost capture |
| `death.wav` | Player death |
| `clear.wav` | Level completion |
| `fruit.wav` | Fruit pickup |
| `extra-life.wav` | Extra life |
| `siren.wav` | Lowest hunting-speed warning |
| `siren-fast.wav`, `siren-faster.wav`, `siren-fastest.wav` | Higher hunting-speed warnings |
| `frightened.wav` | Power-pellet warning |
| `eyes.wav` | Returning-eyes warning |

`gameplay.wav` contains a 32-second loop at 120 beats per minute.  It combines a soft melody, bass
notes, and quiet chords without drums.  The mix stays below the existing warning loops and sound
effects.  Both endpoints are zero, with gradual note attacks and releases to avoid sudden changes
where the loop repeats.

The siren rises in pitch and repeats faster as the red ghost's hunting speed increases.  Tunnel
slowdowns do not change it.  Returning eyes take priority over the other warnings, so only one
warning loop plays alongside the music.

Run `make assets` from the repository root to regenerate the files.  This command overwrites the
tracked WAV files in `assets/sounds/`.  Normal builds use the bundled files without regeneration,
and `make clean` preserves them.  Commit changed sounds with their generator changes.  Their source
and output use the project's MIT license.  These sounds are not samples or transcriptions of Pac-Man
audio.
