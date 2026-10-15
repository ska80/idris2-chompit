# Assets

Chompit draws its sprites, wall outlines, and bitmap font in Idris.  The palette uses black, blue,
yellow, red, pink, cyan, orange, white, and pale pink pellets.  The graphics do not require external
image or font files.  `screenshot.png` shows an actual software-rendered game frame.

The twelve original audio files in `assets/sounds/` are tracked in Git.  `tools/generate_audio.py`
recreates them with only the Python standard library.  Each file contains mono, signed 16-bit PCM at
22,050 Hz.  PCM stores the waveform as a sequence of samples.  The synthesis uses tones, pitch
sweeps, and short melodies, with quiet endpoints to reduce clicks.

| Filename | Use |
| --- | --- |
| `title.wav` | Looping title music |
| `begin.wav` | Start jingle |
| `chomp-low.wav`, `chomp-high.wav` | Alternating pellet sounds |
| `power.wav` | Power-pellet cue |
| `eat-ghost.wav` | Ghost capture |
| `death.wav` | Player death |
| `clear.wav` | Level completion |
| `fruit.wav` | Fruit pickup |
| `extra-life.wav` | Extra life |
| `siren.wav` | Normal play loop |
| `frightened.wav` | Power-pellet loop |

Run `make assets` from the repository root to regenerate the files.  This command overwrites the
tracked WAV files in `assets/sounds/`.  Normal builds use the bundled files without regeneration,
and `make clean` preserves them.  Commit changed sounds with their generator changes.  Their source
and output use the project's MIT license.  These sounds are not samples or transcriptions of Pac-Man
audio.
