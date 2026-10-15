#!/usr/bin/env python3
"""Synthesize Chompit's original audio with the Python standard library."""

import argparse
import math
from pathlib import Path
import struct
import wave

RATE = 22050
TAU = 2 * math.pi
DEFAULT_OUTPUT = Path(__file__).resolve().parents[1] / "assets" / "sounds"


def tone(frequency, seconds, gain=0.3, end=None, kind="triangle"):
    samples = []
    count = round(seconds * RATE)
    phase = 0.0
    for index in range(count):
        t = index / RATE
        f = frequency if end is None else frequency + (end - frequency) * index / count
        phase = (phase + f / RATE) % 1.0
        # A sine/triangle blend avoids the harsh edge of an unfiltered square.
        triangle = 1 - 4 * abs(phase - 0.5)
        value = math.sin(TAU * phase) if kind == "sine" else 0.7 * triangle + 0.3 * math.sin(TAU * phase)
        envelope = min(1.0, t / 0.006, (seconds - t) / 0.018)
        samples.append(value * gain * max(0.0, envelope))
    return samples


def note(midi, seconds, gain=0.3):
    return tone(440 * 2 ** ((midi - 69) / 12), seconds, gain)


def melody(notes, beat, gain=0.3):
    samples = []
    for pitch, duration in notes:
        seconds = duration * beat
        if pitch is None:
            samples.extend([0.0] * round(seconds * RATE))
        else:
            samples.extend(note(pitch, seconds, gain))
    return samples


def mix(first, second):
    result = first[:] + [0.0] * max(0, len(second) - len(first))
    for index, value in enumerate(second):
        result[index] += value
    return result


def siren(base, depth, seconds, cycles):
    samples = []
    phase = 0.0
    count = round(seconds * RATE)
    for index in range(count):
        t = index / RATE
        frequency = base + depth * math.sin(TAU * cycles * t / seconds)
        phase += frequency / RATE
        edge = min(1.0, t / 0.004, (seconds - t) / 0.004)
        samples.append(0.18 * math.sin(TAU * phase) * max(0.0, edge))
    return samples


def sounds():
    # This tune is original. It is not a transcription of the arcade melody.
    lead = [(72, 1), (79, 1), (76, 1), (81, 1), (79, 2), (74, 1), (76, 1),
            (77, 1), (81, 1), (84, 1), (83, 1), (79, 2), (76, 1), (74, 1),
            (72, 1), (76, 1), (79, 1), (86, 1), (84, 2), (81, 1), (79, 1),
            (77, 1), (74, 1), (71, 1), (74, 1), (72, 3), (None, 1)]
    bass = [(48, 2), (55, 2), (52, 2), (55, 2), (53, 2), (60, 2), (55, 2), (59, 2),
            (48, 2), (55, 2), (57, 2), (60, 2), (53, 2), (55, 2), (48, 3), (None, 1)]
    return {
        "title": mix(melody(lead, 0.22, 0.22), melody(bass, 0.22, 0.15)),
        "begin": melody([(60, 1), (67, 1), (72, 1), (76, 1), (74, 1), (79, 1),
                          (84, 2), (79, 1), (76, 1), (72, 3), (None, 2)], 0.18),
        "chomp-low": tone(520, 0.075, 0.3, 160),
        "chomp-high": tone(180, 0.075, 0.3, 620),
        "power": tone(220, 0.25, 0.32, 980),
        "eat-ghost": tone(300, 0.32, 0.32, 1700),
        "death": melody([(84, 1), (83, 1), (79, 1), (77, 1), (76, 1), (72, 1),
                          (71, 1), (67, 1)], 0.08) + tone(400, 0.6, 0.32, 45),
        "clear": melody([(72, 1), (76, 1), (79, 1), (84, 1), (88, 1), (91, 1), (96, 3)], 0.13),
        "fruit": melody([(79, 1), (84, 1), (88, 2)], 0.07),
        "extra-life": melody([(76, 1), (79, 1), (84, 1), (88, 1), (84, 2)], 0.1),
        "siren": siren(360, 110, 1.0, 2),
        "frightened": siren(145, 65, 0.8, 6),
    }


def generate(output):
    output.mkdir(parents=True, exist_ok=True)
    for name, samples in sounds().items():
        # Fail rather than silently clip a future change to the synthesizer.
        assert samples and max(abs(value) for value in samples) < 1.0, name
        pcm = b"".join(struct.pack("<h", round(value * 32767)) for value in samples)
        with wave.open(str(output / f"{name}.wav"), "wb") as stream:
            stream.setnchannels(1)
            stream.setsampwidth(2)
            stream.setframerate(RATE)
            stream.writeframes(pcm)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    generate(args.output)
    print(f"Generated 12 original sounds in {args.output}")
