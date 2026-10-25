"""Generates the bundled synthesized sound sets (mono 16-bit WAV, capture quieter than paste).

Usage: python3 scripts/sounds.py Sources/Encore/Resources/Sounds   (requires numpy)
"""
import numpy as np, wave, sys, os

SR = 44100
out = sys.argv[1]
os.makedirs(out, exist_ok=True)
rng = np.random.default_rng(7)

def t(d): return np.arange(int(SR * d)) / SR

def env(n, attack, tau):
    x = np.arange(n) / SR
    a = np.clip(x / attack, 0, 1) if attack > 0 else 1
    return a * np.exp(-x / tau)

def lowpass(x, cutoff):
    # one-pole low-pass, applied twice for a softer slope
    k = np.exp(-2 * np.pi * cutoff / SR)
    for _ in range(2):
        y = np.zeros_like(x); p = 0.0
        for i, v in enumerate(x):
            p = (1 - k) * v + k * p; y[i] = p
        x = y
    return x

def bandnoise(d, lo, hi):
    n = rng.standard_normal(int(SR * d))
    return lowpass(n, hi) - lowpass(n, lo)

def tone(freq, d, attack, tau, partials=((1, 1),)):
    x = t(d); s = np.zeros_like(x)
    for ratio, amp in partials:
        s += amp * np.sin(2 * np.pi * freq * ratio * x) * np.exp(-x / (tau / max(1, ratio ** 0.5)))
    return s * np.clip(x / attack, 0, 1)

def glide(f0, f1, d, attack, tau):
    x = t(d)
    f = f0 * (f1 / f0) ** np.clip(x / (d * 0.5), 0, 1)
    phase = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(phase) * env(len(x), attack, tau)

def place(*parts):
    total = max(int(SR * off) + len(p) for off, p in parts)
    s = np.zeros(total)
    for off, p in parts:
        i = int(SR * off); s[i:i + len(p)] += p
    return s

def fade(s, ms=4):
    n = int(SR * ms / 1000); s[-n:] *= np.linspace(1, 0, n); return s

def write(name, s, peak_db):
    s = fade(s / np.max(np.abs(s)) * 10 ** (peak_db / 20))
    with wave.open(os.path.join(out, name + '.wav'), 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((s * 32767).astype('<i2').tobytes())

CAP, PASTE = -16, -11  # capture stays clearly quieter than paste

# Drop: very short upward glide
write('drop-capture', glide(620, 1180, 0.09, 0.002, 0.028), CAP)
write('drop-paste', place((0, glide(700, 1250, 0.1, 0.002, 0.03)), (0.07, glide(950, 1700, 0.12, 0.002, 0.035))), PASTE)

# Glass: inharmonic partials, gentle decay
glass = ((1, 1), (2.76, 0.18), (5.4, 0.05))
write('glass-capture', tone(2093, 0.18, 0.003, 0.045, glass), CAP)
write('glass-paste', place((0, tone(1318.5, 0.32, 0.003, 0.09, glass)), (0.055, tone(1975.5, 0.32, 0.003, 0.09, glass) * 0.8)), PASTE)

# Marimba: wooden bar (3.9 partial)
marimba = ((1, 1), (3.9, 0.35), (9.2, 0.06))
write('marimba-capture', lowpass(tone(523.25, 0.14, 0.002, 0.03, marimba), 5000), CAP)
write('marimba-paste', lowpass(place((0, tone(440, 0.22, 0.002, 0.05, marimba)), (0.075, tone(659.25, 0.24, 0.002, 0.06, marimba))), 5000), PASTE)

# Paper: filtered swish for capture, muted knock for paste
x = t(0.085); swish = bandnoise(0.085, 1800, 6500) * np.sin(np.pi * x / 0.085) ** 2
write('paper-capture', swish, CAP - 2)
thock = place((0, lowpass(rng.standard_normal(int(SR * 0.012)), 2500) * env(int(SR * 0.012), 0.0005, 0.003)), (0, tone(185, 0.09, 0.001, 0.018)))
write('paper-paste', thock, PASTE)

# Bubble: rounded pop
write('bubble-capture', glide(280, 640, 0.07, 0.001, 0.016), CAP)
write('bubble-paste', place((0, glide(320, 760, 0.08, 0.001, 0.02)), (0.06, glide(480, 1100, 0.09, 0.001, 0.024))), PASTE)

# Piano: muted felt piano note
felt = ((1, 1), (2, 0.25), (3, 0.08))
write('piano-capture', lowpass(tone(784, 0.2, 0.008, 0.05, felt), 2500), CAP)
write('piano-paste', lowpass(place((0, tone(523.25, 0.36, 0.008, 0.11, felt)), (0.0, tone(784, 0.36, 0.008, 0.11, felt) * 0.6)), 2600), PASTE)
print('ok')
