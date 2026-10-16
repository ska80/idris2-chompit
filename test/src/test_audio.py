#!/usr/bin/env python3
"""Test generated audio without a sound device or third-party packages."""

import math
from pathlib import Path
import struct
import sys
import tempfile
import wave

# Find the generator from this file's location, not the working directory.
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
from generate_audio import DEFAULT_OUTPUT, RATE, generate, sounds


def rms(samples):
    return math.sqrt(sum(value * value for value in samples) / len(samples))


def test_gameplay_music(bank):
    music = bank["gameplay"]
    music_rms = rms(music)
    warning_rms = min(rms(bank[name]) for name in
                      ["siren", "siren-fast", "siren-faster", "siren-fastest", "frightened", "eyes"])
    assert len(music) == 32 * RATE, "The gameplay loop must contain sixteen bars at 120 beats per minute."
    assert 0.01 < music_rms < 0.35 * warning_rms, "Music must stay below all warning loops."
    assert music_rms < 0.5 * rms(bank["title"]), "Gameplay music must be quieter than the title tune."
    assert max(abs(value) for value in music) < 0.20, "Leave room for sound effects."
    assert music[0] == music[-1] == 0.0, "The loop must join at zero amplitude."
    assert abs(music[1] - music[0]) < 0.0001 and abs(music[-1] - music[-2]) < 0.0001
    assert max(abs(b - a) for a, b in zip(music, music[1:])) < 0.04, "Avoid sudden waveform jumps."
    # Notes leave room for effects without inserting a long silent loop tail.
    for start in range(0, len(music), RATE // 2):
        assert rms(music[start:start + RATE // 2]) > 0.001, "The music has an unexpected silent gap."
    return 20 * math.log10(rms(bank["siren"]) / music_rms)


def test_intermission_music(bank):
    music = bank["intermission"]
    assert len(music) == 8 * RATE, "The intermission loop must match the eight-second scenes."
    assert rms(bank["gameplay"]) < rms(music) < 0.15, "Keep the tune audible without overpowering effects."
    assert music[0] == music[-1] == 0.0, "The intermission loop must join at zero amplitude."
    assert max(abs(b - a) for a, b in zip(music, music[1:])) < 0.10
    for start in range(0, len(music), RATE // 2):
        assert rms(music[start:start + RATE // 2]) > 0.001, "The intermission tune has an unexpected silent gap."


def test_warning_loops(bank):
    names = ["siren", "siren-fast", "siren-faster", "siren-fastest"]
    assert [len(bank[name]) for name in names] == [22050, 17640, 14700, 11025]
    pitches = []
    for name in names:
        samples = bank[name]
        crossings = sum(a <= 0 < b for a, b in zip(samples, samples[1:]))
        pitches.append(crossings * RATE / len(samples))
    assert all(a < b for a, b in zip(pitches, pitches[1:])), "Faster sirens must rise in pitch."
    assert len(bank["eyes"]) == round(0.6 * RATE)
    assert rms(bank["eyes"]) < rms(bank["siren"]), "Returning eyes must leave room for capture sounds."


def main():
    bank = sounds()
    assert set(bank) == {"title", "gameplay", "begin", "chomp-low", "chomp-high", "power",
                         "eat-ghost", "death", "clear", "fruit", "extra-life", "siren", "frightened",
                         "siren-fast", "siren-faster", "siren-fastest", "eyes", "intermission"}
    music_level = test_gameplay_music(bank)
    test_warning_loops(bank)
    test_intermission_music(bank)
    with tempfile.TemporaryDirectory(prefix="chompit-audio-") as directory:
        output = Path(directory)
        generate(output)
        for name, samples in bank.items():
            path = DEFAULT_OUTPUT / f"{name}.wav"
            assert path.read_bytes() == (output / path.name).read_bytes(), name
            with wave.open(str(path), "rb") as stream:
                assert stream.getframerate() == RATE, name
                assert stream.getnchannels() == 1, name
                assert stream.getsampwidth() == 2, name
                assert stream.getnframes() == len(samples), name
                pcm = struct.unpack(f"<{len(samples)}h", stream.readframes(len(samples)))
                assert 1000 < max(abs(value) for value in pcm) < 32767, name
                assert abs(pcm[0]) < 100 and abs(pcm[-1]) < 100, name
    print(f"Audio tests passed: {len(bank)} reproducible WAV files, valid format, no clipping, quiet endpoints.")
    print(f"Gameplay music: 32-second loop, smooth boundary, {music_level:.1f} dB below the siren (RMS).")
    print("Intermission music: eight-second loop, smooth boundary, audible signal throughout each bar.")


if __name__ == "__main__":
    main()
