"""
Synthesises the game's audio (music, footsteps, machine loops, alerts).

    python tools/build_audio.py

Writes assets/audio/*.wav (22050 Hz, 16-bit mono). Everything is generated
from maths, so no outside samples or licences are needed. Loops are built
"circularly" (every frequency fits a whole number of cycles in the loop and
event tails wrap around), so they repeat without a click.

To use real recordings / AI-generated tracks instead, just drop a file with
the same name (.wav or .ogg) into assets/audio/ - src/audio.lua loads by name.

Needs numpy (pip install numpy).
"""
import os
import wave

import numpy as np

SR = 22050
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "assets", "audio")
rng = np.random.default_rng(7)


# ---------------------------------------------------------------- helpers
def t_axis(seconds):
    return np.arange(int(SR * seconds)) / SR


def fit(f, length):
    """Nearest frequency with a whole number of cycles in the loop."""
    n = len(length) if hasattr(length, "__len__") else length
    cycles = max(1, round(f * n / SR))
    return cycles * SR / n


def sine(f, t, loop=True):
    if loop:
        f = fit(f, t)
    return np.sin(2 * np.pi * f * t)


def band(x, lo, hi, soft=0.15):
    """Circular FFT band-pass (keeps loops seamless)."""
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    m = np.ones_like(f)
    if lo > 0:
        m *= 1 / (1 + np.exp(-(f - lo) / max(1.0, lo * soft)))
    if hi < SR / 2:
        m *= 1 / (1 + np.exp((f - hi) / max(1.0, hi * soft)))
    return np.fft.irfft(X * m, len(x))


def noise(n):
    return rng.standard_normal(n)


def env(n, attack, decay):
    """Attack (s) + exponential decay (time constant, s) envelope of n samples."""
    t = np.arange(n) / SR
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    return a * np.exp(-t / max(decay, 1e-4))


def place(buf, sound, at, wrap=True):
    """Adds `sound` into `buf` starting at time `at` (wraps for loops)."""
    i = int(at * SR)
    n = len(sound)
    if wrap:
        idx = (np.arange(n) + i) % len(buf)
        np.add.at(buf, idx, sound)
    else:
        end = min(len(buf), i + n)
        buf[i:end] += sound[: end - i]


def norm(x, peak=0.8):
    m = np.max(np.abs(x))
    return x * (peak / m) if m > 0 else x


def save(name, x, peak=0.8):
    x = norm(x, peak)
    data = (np.clip(x, -1, 1) * 32767).astype("<i2")
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    print(f"{name:16s} {len(x) / SR:5.2f} s")


def note(midi):
    return 440.0 * 2 ** ((midi - 69) / 12)


def tone(f, seconds, attack=0.005, decay=0.2, harmonics=(1.0,)):
    t = np.arange(int(SR * seconds)) / SR
    s = sum(a * np.sin(2 * np.pi * f * (k + 1) * t) for k, a in enumerate(harmonics))
    return s * env(len(t), attack, decay)


# ---------------------------------------------------------------- music
def music_ambient():
    """State A: deep drone, slow pads, wind, soft life-support heartbeat."""
    L = 16.0
    t = t_axis(L)
    x = 0.45 * sine(55, t) + 0.25 * sine(82.5, t) + 0.12 * sine(110, t)
    x *= 0.8 + 0.2 * sine(1 / 8, t)
    pad = np.zeros_like(t)
    for i, m in enumerate([57, 60, 64, 67]):           # A minor 7 pad
        lfo = 0.5 + 0.5 * sine(1 / 16, t + i * 3)
        pad += lfo * (sine(note(m), t) + 0.3 * sine(note(m) * 2.01, t))
    x += 0.10 * pad
    x += 0.18 * band(noise(len(t)), 150, 700) * (0.6 + 0.4 * sine(1 / 4, t))
    beat = tone(48, 0.35, 0.004, 0.09) + 0.4 * band(noise(int(SR * 0.35)), 1500, 5000) * env(int(SR * 0.35), 0.001, 0.01)
    for k in range(int(L / 2)):                        # lub-dub every 2 s
        place(x, 0.5 * beat, k * 2.0)
        place(x, 0.32 * beat, k * 2.0 + 0.28)
    tick = band(noise(int(SR * 0.05)), 2500, 7000) * env(int(SR * 0.05), 0.001, 0.006)
    for k in range(int(L)):
        place(x, 0.12 * tick, k + 1.0)
    return x


def music_tension():
    """State B: pulsing bass, rising arpeggios, soft klaxon undertone."""
    L = 8.0                                            # 120 bpm, 4 bars of 4/4 at 2 s
    t = t_axis(L)
    x = np.zeros_like(t)
    eighth = 0.25
    roots = [45, 45, 41, 43]                           # A A F G
    for k in range(int(L / eighth)):
        root = roots[(k // 8) % 4]
        b = tone(note(root - 12), 0.24, 0.004, 0.09, harmonics=(1, 0.6, 0.35, 0.2))
        place(x, 0.55 * b, k * eighth)
    arp = [0, 3, 7, 12, 15, 19, 24, 19]
    for k in range(int(L / 0.125)):
        root = roots[(k // 16) % 4]
        a = tone(note(root + 12 + arp[k % 8]), 0.12, 0.002, 0.05, harmonics=(1, 0.3))
        place(x, 0.16 * a * (0.5 + 0.5 * (k % 16) / 16), k * 0.125)
    pad = sum(sine(note(m), t) for m in (57, 60, 64)) * (0.5 + 0.5 * sine(1 / 8, t))
    x += 0.07 * pad
    klax = np.zeros(int(SR * 0.6))
    tt = np.arange(len(klax)) / SR
    klax = np.sign(np.sin(2 * np.pi * 440 * tt)) * 0.3 + np.sin(2 * np.pi * 554 * tt) * 0.7
    klax = band(np.concatenate([klax, np.zeros(SR // 5)]), 200, 1600) * np.concatenate([env(len(klax), 0.08, 0.25), np.zeros(SR // 5)])
    place(x, 0.12 * klax, 3.0)
    place(x, 0.12 * klax, 7.0)
    return x


def music_crisis():
    """State C: fast beat, relentless synths, sirens and radar beeps."""
    L = 6.4                                            # 150 bpm: 16 beats
    t = t_axis(L)
    x = np.zeros_like(t)
    beat = 0.4
    kick = tone(55, 0.3, 0.001, 0.08) * np.exp(-np.arange(int(SR * 0.3)) / SR * 4)
    kick += tone(110, 0.3, 0.001, 0.02)
    for k in range(16):
        place(x, 0.7 * kick, k * beat)
    hat = band(noise(int(SR * 0.06)), 6000, 10000) * env(int(SR * 0.06), 0.001, 0.012)
    for k in range(32):
        place(x, 0.18 * hat, k * beat / 2 + beat / 4)
    seq = [45, 45, 57, 45, 48, 45, 55, 52]
    for k in range(64):
        s = tone(note(seq[k % 8]), 0.09, 0.002, 0.035, harmonics=(1, 0.7, 0.5, 0.3))
        place(x, 0.22 * s, k * beat / 4)
    # siren wail (pitch sweeps up and down every 1.6 s)
    phase = 2 * np.pi * np.cumsum(700 + 220 * np.sin(2 * np.pi * fit(1 / 1.6, t) * t)) / SR
    x += 0.07 * np.sin(phase)
    blip = tone(1760, 0.08, 0.001, 0.03)
    for k in range(4):
        place(x, 0.25 * blip, k * 1.6 + 0.8)
    return x


# ---------------------------------------------------------------- footsteps
def step_metal(seed):
    r = np.random.default_rng(seed)
    n = int(SR * 0.5)
    x = band(r.standard_normal(n), 1500, 6000) * env(n, 0.001, 0.012) * 0.8
    for f, a, d in ((1180 + r.integers(-60, 60), 0.6, 0.06), (2650, 0.35, 0.04), (4170, 0.25, 0.03)):
        x += a * np.sin(2 * np.pi * f * np.arange(n) / SR) * env(n, 0.001, d)
    x += 0.25 * tone(140, 0.5, 0.002, 0.03)[:n]
    echo = np.zeros(n)
    d = int(SR * 0.07)
    echo[d:] = x[:-d] * 0.25
    return x + echo


def step_rubber(seed):
    r = np.random.default_rng(seed)
    n = int(SR * 0.3)
    x = tone(75 + r.integers(-8, 8), 0.3, 0.004, 0.05) + 0.5 * tone(150, 0.3, 0.004, 0.025)
    x += 0.35 * band(r.standard_normal(n), 80, 600) * env(n, 0.003, 0.03)
    return x


def step_regolith(seed):
    r = np.random.default_rng(seed)
    n = int(SR * 0.4)
    grains = np.zeros(n)
    for _ in range(70):                                # crunchy grains
        i = int(abs(r.normal(0.06, 0.05)) * SR)
        if i < n - 200:
            grains[i:i + 200] += r.standard_normal(200) * np.exp(-np.arange(200) / 40) * r.uniform(0.3, 1)
    x = band(grains, 700, 5000) * 0.9 + 0.4 * band(r.standard_normal(n), 100, 900) * env(n, 0.01, 0.06)
    tt = np.arange(n) / SR                              # suit servo whirr
    x += 0.06 * np.sin(2 * np.pi * (380 + 300 * tt) * tt) * env(n, 0.05, 0.12)
    return x


# ---------------------------------------------------------------- machine loops
def loop_air():
    L = 4.0
    t = t_axis(L)
    fan = band(noise(len(t)), 80, 900) * (0.7 + 0.3 * sine(24, t))
    hiss = band(noise(len(t)), 3000, 9000) * 0.35
    hum = 0.25 * sine(98, t) + 0.1 * sine(196, t)
    return fan + hiss + hum


def loop_air_broken():
    L = 4.0
    t = t_axis(L)
    x = np.zeros_like(t)
    hiss = band(noise(len(t)), 2500, 9000)
    gate = np.zeros_like(t)
    for at, dur in ((0.1, 0.5), (0.8, 0.15), (1.2, 0.9), (2.5, 0.2), (2.9, 0.6), (3.7, 0.15)):
        i, n = int(at * SR), int(dur * SR)
        gate[i:i + n] = np.hanning(n) if n > 1 else 0
    x += hiss * gate * 0.8
    cough = band(noise(int(SR * 0.25)), 150, 1200) * env(int(SR * 0.25), 0.01, 0.06)
    for at in (0.65, 2.3, 3.45):
        place(x, 1.1 * cough, at)
    x += 0.15 * band(noise(len(t)), 80, 500) * (0.5 + 0.5 * sine(3, t))
    return x


def loop_water():
    L = 4.0
    t = t_axis(L)
    x = 0.3 * sine(100, t) + 0.12 * sine(200, t) + 0.06 * sine(300, t)
    x += 0.35 * band(noise(len(t)), 120, 700) * (0.6 + 0.4 * sine(0.5, t))
    for _ in range(46):                                # bubbles: quick rising blips
        f0 = rng.uniform(350, 900)
        n = int(SR * rng.uniform(0.03, 0.07))
        tt = np.arange(n) / SR
        b = np.sin(2 * np.pi * (f0 * tt + f0 * 6 * tt * tt)) * np.hanning(n)
        place(x, 0.35 * b, rng.uniform(0, L))
    return x


def loop_water_broken():
    L = 4.0
    t = t_axis(L)
    grind = band(noise(len(t)), 40, 400) * (0.5 + 0.5 * np.abs(sine(7, t))) * 0.6
    x = grind + 0.2 * sine(55, t)
    for at in (0.3, 1.1, 1.7, 2.6, 3.3):               # drips
        d = tone(rng.uniform(1300, 1700), 0.25, 0.001, 0.05)
        place(x, 0.7 * d, at)
    return x


def loop_power():
    L = 4.0
    t = t_axis(L)
    x = 0.55 * sine(60, t) + 0.35 * sine(120, t) + 0.2 * sine(180, t) + 0.08 * sine(240, t)
    x += 0.08 * band(noise(len(t)), 2000, 8000)
    for _ in range(9):                                 # static crackles
        n = int(SR * rng.uniform(0.02, 0.08))
        c = band(noise(n), 1500, 9000) * env(n, 0.001, 0.015)
        place(x, 0.9 * c, rng.uniform(0, L))
    return x


def loop_hopper():
    L = 4.0
    t = t_axis(L)
    x = 0.45 * sine(45, t) + 0.2 * sine(90, t)
    x += 0.5 * band(noise(len(t)), 300, 3000) * (0.4 + 0.6 * np.abs(sine(6, t)))
    return x


def loop_siren():
    L = 2.0
    t = t_axis(L)
    hi = (t % 1.0) < 0.5
    f = np.where(hi, 880.0, 660.0)
    phase = 2 * np.pi * np.cumsum(f) / SR
    x = np.sign(np.sin(phase)) * 0.4 + np.sin(phase) * 0.6
    x = band(x, 300, 3000)
    x *= 0.75 + 0.25 * sine(2, t)
    return x


# ---------------------------------------------------------------- one-shots
def sfx_ok():
    x = np.concatenate([tone(note(76), 0.09, 0.002, 0.06, (1, 0.3)), tone(note(83), 0.25, 0.002, 0.1, (1, 0.3))])
    return x


def sfx_error():
    n = int(SR * 0.3)
    tt = np.arange(n) / SR
    return band(np.sign(np.sin(2 * np.pi * 150 * tt)), 100, 2000) * env(n, 0.005, 0.12)


def sfx_unlock():
    parts = [tone(note(m), 0.16, 0.003, 0.12, (1, 0.4, 0.2)) for m in (72, 76, 79)]
    parts.append(tone(note(84), 0.8, 0.003, 0.35, (1, 0.4, 0.2)))
    return np.concatenate(parts)


def sfx_door():
    n = int(SR * 0.6)
    tt = np.arange(n) / SR
    x = band(noise(n), 300, 3000) * np.sin(np.pi * tt / tt[-1]) ** 2
    return x + 0.3 * np.sin(2 * np.pi * (200 - 120 * tt) * tt) * env(n, 0.05, 0.2)


def main():
    os.makedirs(OUT, exist_ok=True)
    save("music_ambient", music_ambient(), 0.6)
    save("music_tension", music_tension(), 0.6)
    save("music_crisis", music_crisis(), 0.6)
    for i in range(3):
        save(f"step_metal{i + 1}", step_metal(10 + i), 0.7)
        save(f"step_rubber{i + 1}", step_rubber(20 + i), 0.7)
        save(f"step_regolith{i + 1}", step_regolith(30 + i), 0.6)
    save("loop_air", loop_air(), 0.6)
    save("loop_air_broken", loop_air_broken(), 0.6)
    save("loop_water", loop_water(), 0.6)
    save("loop_water_broken", loop_water_broken(), 0.6)
    save("loop_power", loop_power(), 0.6)
    save("loop_hopper", loop_hopper(), 0.6)
    save("loop_siren", loop_siren(), 0.6)
    save("sfx_ok", sfx_ok(), 0.6)
    save("sfx_error", sfx_error(), 0.5)
    save("sfx_unlock", sfx_unlock(), 0.6)
    save("sfx_door", sfx_door(), 0.6)


if __name__ == "__main__":
    main()
