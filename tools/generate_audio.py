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


def siren(base, depth, seconds, cycles, gain=0.18):
    samples = []
    phase = 0.0
    count = round(seconds * RATE)
    for index in range(count):
        t = index / RATE
        frequency = base + depth * math.sin(TAU * cycles * t / seconds)
        phase += frequency / RATE
        edge = min(1.0, t / 0.004, (seconds - t) / 0.004)
        samples.append(gain * math.sin(TAU * phase) * max(0.0, edge))
    return samples


def music_note(midi, seconds, gain, voice):
    """Soft attacks and releases keep the background parts clear of the effects."""
    count = round(seconds * RATE)
    frequency = 440 * 2 ** ((midi - 69) / 12)
    attack, release = (0.18, 0.25) if voice == "chord" else (0.02, 0.10)
    samples = []
    for index in range(count):
        phase = (index * frequency / RATE) % 1.0
        sine = math.sin(TAU * phase)
        if voice == "lead":
            value = 0.7 * (1 - 4 * abs(phase - 0.5)) + 0.3 * sine
        else:
            value = sine
        edge = min(1.0, index / (attack * RATE), (count - 1 - index) / (release * RATE))
        decay = 1.0 if voice == "chord" else 0.25 + 0.75 * math.exp(-3 * index / count)
        samples.append(value * gain * max(0.0, edge) * decay)
    return samples


def gameplay_music():
    """Original 16-bar, 120 BPM loop in C major, with no percussion."""
    beat = 0.5
    samples = [0.0] * (32 * RATE)

    def place(pitch, onset, duration, gain, voice):
        # Position each note on the full timeline, not after rounded note lengths.
        start = round(onset * beat * RATE)
        part = music_note(pitch, duration * beat, gain, voice)
        assert 0 <= start and start + len(part) <= len(samples)
        for index, value in enumerate(part, start):
            samples[index] += value

    harmony = [
        (48, (60, 64, 67)), (45, (60, 64, 69)),
        (41, (60, 65, 69)), (43, (59, 62, 67)),
    ]
    # Each entry is (beat within the bar, pitch, duration in beats).
    # Short phrases leave room for the pellet sounds and the siren.
    phrases = [
        [(0.5, 76, 0.5), (1.5, 79, 0.5), (2.5, 76, 0.75)],
        [(0.0, 72, 0.75), (2.0, 76, 0.75), (3.25, 69, 0.5)],
        [(0.5, 69, 0.5), (1.5, 72, 0.5), (3.0, 74, 0.75)],
        [(0.0, 67, 0.75), (2.0, 74, 0.75), (3.25, 71, 0.5)],
        [(1.0, 76, 0.75), (2.5, 79, 0.5), (3.25, 81, 0.5)],
        [(0.0, 79, 0.75), (1.5, 76, 0.5), (3.0, 72, 0.75)],
        [(0.5, 74, 0.5), (1.5, 72, 0.75), (3.0, 69, 0.75)],
        [(0.5, 71, 0.5), (1.5, 74, 0.5), (3.0, 67, 0.75)],
        [(0.5, 76, 0.75), (2.0, 79, 0.5), (3.0, 72, 0.75)],
        [(0.0, 69, 0.75), (1.5, 72, 0.5), (3.0, 76, 0.75)],
        [(1.0, 72, 0.75), (2.5, 74, 0.5), (3.25, 76, 0.5)],
        [(0.0, 74, 0.75), (2.0, 71, 0.75)],
        [(0.5, 79, 0.5), (1.5, 76, 0.75), (3.0, 74, 0.75)],
        [(0.0, 72, 0.75), (2.0, 69, 0.75), (3.25, 72, 0.5)],
        [(0.5, 69, 0.5), (1.5, 72, 0.75), (3.0, 74, 0.75)],
        [(0.0, 71, 0.75), (1.5, 74, 0.5), (3.0, 71, 0.75)],
    ]
    for bar, phrase in enumerate(phrases):
        root, chord = harmony[bar % len(harmony)]
        start = bar * 4
        place(root, start, 1.5, 0.12, "bass")
        place(root + 7, start + 2, 1.5, 0.10, "bass")
        for pitch in chord:
            place(pitch, start, 4, 0.018, "chord")
        for onset, pitch, duration in phrase:
            place(pitch, start + onset, duration, 0.16, "lead")

    # Bake the quiet mix into the asset. Effects retain their existing levels.
    # Every part releases before the loop boundary, so both endpoints are zero.
    return [sample * 0.65 for sample in samples]


def intermission_music():
    """Original four-bar, eight-second comic chase tune at 120 BPM."""
    samples = [0.0] * (8 * RATE)

    def place(pitch, onset, duration, gain, voice):
        start = round(onset * 0.5 * RATE)
        part = music_note(pitch, duration * 0.5, gain, voice)
        assert 0 <= start and start + len(part) <= len(samples)
        for index, value in enumerate(part, start):
            samples[index] += value

    phrases = [
        [(0, 72, 0.5), (0.5, 76, 0.5), (1, 79, 1), (2, 76, 0.5), (2.5, 72, 0.5), (3, 67, 0.75)],
        [(0, 74, 0.5), (0.5, 77, 0.5), (1, 81, 1), (2, 79, 0.5), (2.5, 77, 0.5), (3, 74, 0.75)],
        [(0, 76, 0.5), (0.5, 79, 0.5), (1, 84, 1), (2, 83, 0.5), (2.5, 79, 0.5), (3, 76, 0.75)],
        [(0, 74, 0.5), (0.5, 71, 0.5), (1, 67, 0.5), (1.5, 74, 0.5), (2, 72, 1.5)],
    ]
    for bar, (phrase, root) in enumerate(zip(phrases, [48, 50, 52, 48])):
        place(root, bar * 4, 1.5, 0.16, "bass")
        place(root + 7, bar * 4 + 2, 1.5, 0.14, "bass")
        for onset, pitch, duration in phrase:
            place(pitch, bar * 4 + onset, duration, 0.30, "lead")
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
        "gameplay": gameplay_music(),
        "intermission": intermission_music(),
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
        "siren-fast": siren(420, 110, 0.8, 2),
        "siren-faster": siren(480, 110, 2 / 3, 2),
        "siren-fastest": siren(540, 110, 0.5, 2),
        "frightened": siren(145, 65, 0.8, 6),
        "eyes": siren(880, 260, 0.6, 6, 0.14),
    }


def generate(output):
    output.mkdir(parents=True, exist_ok=True)
    generated = sounds()
    for name, samples in generated.items():
        # Fail rather than silently clip a future change to the synthesizer.
        assert samples and max(abs(value) for value in samples) < 1.0, name
        pcm = b"".join(struct.pack("<h", round(value * 32767)) for value in samples)
        with wave.open(str(output / f"{name}.wav"), "wb") as stream:
            stream.setnchannels(1)
            stream.setsampwidth(2)
            stream.setframerate(RATE)
            stream.writeframes(pcm)
    return len(generated)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    count = generate(args.output)
    print(f"Generated {count} original sounds in {args.output}")
