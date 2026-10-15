# Project guidance

Use the Chez backend only.  Run `make test` before you submit changes.  Use `make run` from the
repository root to set native library paths and find bundled assets.  Keep the local dependencies in
`pack.toml` aligned with `../idris2-sdl3`.

Keep game rules in the pure modules `Chompit.Types`, `Chompit.Maze`, and `Chompit.Game`.  Keep SDL
handles and I/O out of those modules.  Preserve their totality requirements and add tests for rule
changes.  Keep native buffers and audio tracks outside the frame loop.  Follow the sibling library's
scoped resource contract.  Keep test sources in `test/src/`.

Regenerate audio with `make assets` rather than adding downloaded sounds.  Track the WAV files in
`assets/sounds/` with their generator, `tools/generate_audio.py`.  Do not regenerate or remove
tracked sounds during normal builds or cleanup.  Keep build output out of Git.  Document intentional
differences from the arcade rules.  Remove completed work from `TODO.md`.
