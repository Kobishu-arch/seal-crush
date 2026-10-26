"""Synthesise the game's sound effects and loop music as 16-bit mono WAVs.

Pure stdlib: no sample libraries, no external deps. Everything is mixed into a
float buffer and clipped once at the end.
"""
import math, os, random, struct, sys, wave

SR = 22050
OUT = sys.argv[1] if len(sys.argv) > 1 else '.'
random.seed(7)


def buf(seconds):
    return [0.0] * int(seconds * SR)


def osc(wave_name, phase):
    p = phase % 1.0
    if wave_name == 'square':
        return 1.0 if p < 0.5 else -1.0
    if wave_name == 'pulse':
        return 1.0 if p < 0.25 else -1.0
    if wave_name == 'tri':
        return 4.0 * abs(p - 0.5) - 1.0
    if wave_name == 'sine':
        return math.sin(2.0 * math.pi * p)
    return 0.0


def tone(b, at, dur, f0, f1=None, kind='square', amp=0.2, decay=0.35, attack=0.004,
         vib=0.0, vib_hz=6.0):
    """One note. f1 sweeps the pitch, decay is a fraction of dur."""
    n = int(dur * SR)
    start = int(at * SR)
    phase = 0.0
    tau = max(dur * decay, 1e-4)
    for i in range(n):
        j = start + i
        if j < 0 or j >= len(b):
            continue
        t = i / SR
        f = f0 if f1 is None else f0 + (f1 - f0) * (i / max(n - 1, 1))
        if vib:
            f *= 1.0 + vib * math.sin(2.0 * math.pi * vib_hz * t)
        phase += f / SR
        env = math.exp(-t / tau)
        if t < attack:
            env *= t / attack
        b[j] += osc(kind, phase) * amp * env


def hit(b, at, dur, amp=0.1, decay=0.25, tilt=0.5):
    """Noise transient - the click in a pop, or a hat."""
    n = int(dur * SR)
    start = int(at * SR)
    prev = 0.0
    tau = max(dur * decay, 1e-4)
    for i in range(n):
        j = start + i
        if j < 0 or j >= len(b):
            continue
        white = random.uniform(-1.0, 1.0)
        prev = prev + (white - prev) * tilt        # one-pole lowpass
        b[j] += prev * amp * math.exp(-(i / SR) / tau)


def midi(n):
    return 440.0 * (2.0 ** ((n - 69) / 12.0))


def save(name, b, target_rms=0.14, ceiling=0.9):
    """Normalise by RMS, not peak.

    Perceived loudness tracks energy, so peak-normalising makes a clicky
    transient and a sustained tone with the same peak sound nothing alike.
    Level to a target RMS instead, then soft-clip with tanh so transients
    stay put instead of dragging the whole file's level down.
    """
    rms = math.sqrt(sum(v * v for v in b) / max(len(b), 1)) or 1e-9
    gain = target_rms / rms
    out = [math.tanh(v * gain / ceiling) * ceiling for v in b]
    frames = bytearray()
    for v in out:
        frames += struct.pack('<h', int(max(-1.0, min(1.0, v)) * 32767))
    path = os.path.join(OUT, name)
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(bytes(frames))
    peak = max(abs(v) for v in out)
    final = math.sqrt(sum(v * v for v in out) / max(len(out), 1))
    print('%-18s %5.2fs  peak %.2f  rms %.3f  %7d bytes'
          % (name, len(b) / SR, peak, final, os.path.getsize(path)))


# --- sound effects --------------------------------------------------------

def sfx_move():
    b = buf(0.10)
    tone(b, 0.0,  0.045, midi(76), kind='pulse', amp=0.22, decay=0.5)
    tone(b, 0.04, 0.055, midi(83), kind='pulse', amp=0.22, decay=0.45)
    save('move.wav', b)


def sfx_pop():
    b = buf(0.16)
    hit(b, 0.0, 0.03, amp=0.18, decay=0.2, tilt=0.7)
    tone(b, 0.0, 0.13, midi(72), midi(91), kind='sine', amp=0.5, decay=0.3)
    tone(b, 0.0, 0.07, midi(84), midi(96), kind='tri', amp=0.18, decay=0.25)
    save('pop.wav', b)


def sfx_invalid():
    b = buf(0.18)
    tone(b, 0.0, 0.16, midi(45), midi(38), kind='square', amp=0.3, decay=0.6)
    save('invalid.wav', b)


def sfx_special():
    b = buf(0.40)
    for i, n in enumerate([72, 76, 79, 84]):
        tone(b, i * 0.055, 0.22, midi(n), kind='pulse', amp=0.2, decay=0.3)
    save('special.wav', b)


def sfx_combo():
    b = buf(0.70)
    for i, n in enumerate([72, 76, 79, 84, 88, 91]):
        tone(b, i * 0.05, 0.34, midi(n), kind='pulse', amp=0.18, decay=0.35)
    for i, n in enumerate([48, 55, 60]):
        tone(b, i * 0.05, 0.45, midi(n), kind='tri', amp=0.2, decay=0.5)
    save('combo.wav', b)


def sfx_shuffle():
    b = buf(0.55)
    n = int(0.5 * SR)
    phase = 0.0
    for i in range(n):
        t = i / SR
        f = midi(69) * (1.0 + 0.35 * math.sin(2 * math.pi * 6.0 * t))
        phase += f / SR
        b[i] += osc('tri', phase) * 0.22 * math.exp(-t / 0.28)
    save('shuffle.wav', b)


# --- music ----------------------------------------------------------------
# 24 bars at 96 BPM (~60s) in an A / B / A' shape, so it does not fold back on
# itself every few seconds. Triangle lead rather than pulse, a soft sine pad
# under it, and no hats - a repeating tick is the first thing that grates on a
# long loop.

BPM = 96.0
BEAT = 60.0 / BPM
R = None

CHORDS = {
    'C':   {'bass': 48, 'pad': [60, 64, 67]},
    'G/B': {'bass': 47, 'pad': [59, 62, 67]},
    'Am':  {'bass': 45, 'pad': [57, 60, 64]},
    'Em':  {'bass': 40, 'pad': [59, 64, 67]},
    'F':   {'bass': 41, 'pad': [57, 60, 65]},
    'Dm':  {'bass': 50, 'pad': [57, 62, 65]},
    'G':   {'bass': 43, 'pad': [59, 62, 67]},
}

# (chord, [(note, beats), ...]) - phrases of two bars, each closing on a rest
SONG = [
    # A
    ('C',   [(67, 1.5), (69, 0.5), (72, 1.0), (76, 1.0)]),
    ('G/B', [(74, 2.0), (71, 2.0)]),
    ('Am',  [(72, 1.0), (76, 1.0), (81, 1.5), (79, 0.5)]),
    ('Em',  [(76, 2.0), (R, 2.0)]),
    ('F',   [(77, 1.0), (76, 1.0), (74, 1.0), (72, 1.0)]),
    ('C',   [(76, 2.0), (67, 1.0), (69, 1.0)]),
    ('Dm',  [(74, 1.5), (77, 0.5), (81, 1.0), (77, 1.0)]),
    ('G',   [(79, 2.0), (R, 2.0)]),
    # B - sits a little higher, moves a little more
    ('C',   [(84, 1.0), (83, 1.0), (79, 2.0)]),
    ('Em',  [(76, 1.0), (79, 1.0), (83, 2.0)]),
    ('F',   [(81, 1.5), (79, 0.5), (77, 1.0), (76, 1.0)]),
    ('G',   [(74, 2.0), (79, 2.0)]),
    ('Am',  [(81, 1.0), (79, 1.0), (76, 1.0), (72, 1.0)]),
    ('Em',  [(71, 2.0), (76, 2.0)]),
    ('F',   [(77, 1.0), (81, 1.0), (84, 1.5), (81, 0.5)]),
    ('G',   [(83, 2.0), (79, 2.0)]),
    # A' - the opening again, resolving home
    ('C',   [(67, 1.5), (69, 0.5), (72, 1.0), (76, 1.0)]),
    ('G/B', [(74, 2.0), (71, 2.0)]),
    ('Am',  [(72, 1.0), (76, 1.0), (81, 1.5), (79, 0.5)]),
    ('Em',  [(76, 2.0), (R, 2.0)]),
    ('F',   [(77, 1.0), (76, 1.0), (74, 1.0), (72, 1.0)]),
    ('G',   [(74, 2.0), (71, 1.0), (74, 1.0)]),
    ('C',   [(72, 2.0), (76, 1.0), (79, 1.0)]),
    ('C',   [(72, 4.0)]),
]


def music():
    bar = 4 * BEAT
    b = buf(len(SONG) * bar)
    t = 0.0
    for chord, mel in SONG:
        ch = CHORDS[chord]
        for n in ch['pad']:
            tone(b, t, bar * 0.98, midi(n), kind='sine', amp=0.05,
                 decay=0.85, attack=0.09)
        tone(b, t, BEAT * 1.7, midi(ch['bass']), kind='tri', amp=0.17,
             decay=0.5, attack=0.012)
        tone(b, t + 2 * BEAT, BEAT * 1.7, midi(ch['bass']), kind='tri',
             amp=0.13, decay=0.5, attack=0.012)
        mt = t
        for note, beats in mel:
            if note is not None:
                tone(b, mt, beats * BEAT * 0.92, midi(note), kind='tri',
                     amp=0.15, decay=0.6, attack=0.015)
                tone(b, mt, beats * BEAT * 0.7, midi(note + 12), kind='sine',
                     amp=0.035, decay=0.5, attack=0.02)
            mt += beats * BEAT
        t += bar
    # taper the last few ms so the loop seam cannot click
    tail = int(0.015 * SR)
    for i in range(tail):
        b[len(b) - tail + i] *= 1.0 - i / tail
    save('music.wav', b, target_rms=0.075)


# --- per-species voices ---------------------------------------------------
# One short call per animal, each in its own pitch register so they stay
# distinguishable: penguin highest, otter high trill, narwhal mid sweep,
# seal mid bark, bear low huff, walrus lowest rumble.

def voice_seal():
    b = buf(0.22)
    hit(b, 0.0, 0.02, amp=0.10, decay=0.2, tilt=0.6)
    tone(b, 0.0,  0.09, midi(72), midi(67), kind='pulse', amp=0.26, decay=0.4)
    tone(b, 0.10, 0.10, midi(69), midi(64), kind='pulse', amp=0.22, decay=0.4)
    save('voice_seal.wav', b)


def voice_penguin():
    b = buf(0.18)
    tone(b, 0.0,  0.05, midi(93), midi(96), kind='square', amp=0.22, decay=0.35)
    tone(b, 0.07, 0.06, midi(96), midi(99), kind='square', amp=0.20, decay=0.3)
    save('voice_penguin.wav', b)


def voice_otter():
    b = buf(0.26)
    for i in range(5):
        n = 88 if i % 2 == 0 else 91
        tone(b, i * 0.038, 0.05, midi(n), kind='pulse', amp=0.18, decay=0.3)
    save('voice_otter.wav', b)


def voice_walrus():
    # Lowest of the six, but E2/C2 was inaudible mush on small speakers.
    # Up a fifth, with a quiet octave layer so the pitch reads without
    # losing the rumble. Still well below the bear's E3 start.
    b = buf(0.32)
    tone(b, 0.0, 0.28, midi(47), midi(43), kind='tri', amp=0.30, decay=0.55,
         vib=0.045, vib_hz=9.0)
    tone(b, 0.0, 0.24, midi(59), midi(55), kind='tri', amp=0.10, decay=0.5,
         vib=0.045, vib_hz=9.0)
    hit(b, 0.0, 0.05, amp=0.07, decay=0.3, tilt=0.35)
    save('voice_walrus.wav', b)


def voice_narwhal():
    b = buf(0.30)
    tone(b, 0.0,  0.26, midi(69), midi(84), kind='sine', amp=0.30, decay=0.45)
    tone(b, 0.03, 0.20, midi(81), midi(96), kind='sine', amp=0.10, decay=0.4)
    save('voice_narwhal.wav', b)


def voice_bear():
    b = buf(0.26)
    tone(b, 0.0, 0.22, midi(52), midi(47), kind='square', amp=0.24, decay=0.5,
         vib=0.03, vib_hz=8.0)
    hit(b, 0.0, 0.07, amp=0.11, decay=0.35, tilt=0.4)
    save('voice_bear.wav', b)


VOICES = (voice_seal, voice_penguin, voice_otter,
          voice_walrus, voice_narwhal, voice_bear)


# voices are generated last so the shared RNG stream keeps the earlier files
# byte-identical between runs
for fn in (sfx_move, sfx_pop, sfx_invalid, sfx_special, sfx_combo, sfx_shuffle, music) + VOICES:
    fn()
