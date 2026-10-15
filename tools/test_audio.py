#!/usr/bin/env python3
"""Test generated audio without a sound device or third-party packages."""

from pathlib import Path
import struct
import tempfile
import wave

from generate_audio import DEFAULT_OUTPUT, RATE, generate, sounds


def main():
    with tempfile.TemporaryDirectory(prefix="chompit-audio-") as directory:
        output = Path(directory)
        generate(output)
        for name, samples in sounds().items():
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
    print("Audio tests passed: 12 reproducible WAV files, valid format, no clipping, quiet endpoints.")


if __name__ == "__main__":
    main()
