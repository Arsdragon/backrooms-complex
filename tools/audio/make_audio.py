"""Синтез всех звуков игры (numpy/scipy → ogg через ffmpeg).

    python tools/audio/make_audio.py            → audio/*.ogg
    python tools/audio/make_audio.py hum lf_    → только звуки, чьё имя начинается с этих префиксов
Зацикленные звуки перечислены в LOOPS (tools/fix_imports.py ставит им loop=true при импорте).
"""
import os
import subprocess
import sys
import tempfile

import numpy as np
from scipy import signal
from scipy.io import wavfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "audio")
SR = 44100
R = np.random.default_rng(1990)

LOOPS = {"hum_fluor", "room_tone", "null_hum", "park_ambience", "wind_trees", "water_loop", "jingle", "generator",
         "threshold_hum", "tv_static", "fridge_hum", "radio_static", "tape_whir", "sea_waves", "wind_open", "wind_fall",
         "upstairs_tv", "crickets", "death_drone", "birds_wrong", "jingle_wrong", "music_box", "engine_tick"}


# ----------------------------------------------------------------- базовые кирпичики

def T(sec):
    return np.arange(int(round(sec * SR))) / SR


def white(sec):
    return R.standard_normal(int(round(sec * SR)))


def pink(sec):
    n = int(round(sec * SR))
    w = R.standard_normal(n)
    f = np.fft.rfft(w)
    k = np.arange(len(f)).astype(float)
    k[0] = 1
    f /= np.sqrt(k)
    o = np.fft.irfft(f, n)
    return o / (np.abs(o).max() + 1e-9)


def brown(sec):
    n = int(round(sec * SR))
    w = R.standard_normal(n)
    f = np.fft.rfft(w)
    k = np.arange(len(f)).astype(float)
    k[0] = 1
    f /= k
    o = np.fft.irfft(f, n)
    return o / (np.abs(o).max() + 1e-9)


def lp(x, fc, order=2):
    b, a = signal.butter(order, min(fc, SR * 0.45) / (SR / 2), "low")
    return signal.lfilter(b, a, x)


def hp(x, fc, order=2):
    b, a = signal.butter(order, fc / (SR / 2), "high")
    return signal.lfilter(b, a, x)


def bp(x, lo, hi, order=2):
    b, a = signal.butter(order, [lo / (SR / 2), min(hi, SR * 0.45) / (SR / 2)], "band")
    return signal.lfilter(b, a, x)


def env_ad(n, a, d, curve=3.0):
    t = np.arange(n) / SR
    e = np.where(t < a, t / max(a, 1e-4), np.exp(-(t - a) / max(d, 1e-4) * curve / 3.0 * 3.0))
    return e


def adsr(n, a, d, s, r):
    t = np.arange(n) / SR
    total = n / SR
    e = np.ones(n) * s
    e[t < a] = t[t < a] / max(a, 1e-4)
    m = (t >= a) & (t < a + d)
    e[m] = 1 - (1 - s) * (t[m] - a) / max(d, 1e-4)
    m2 = t > total - r
    e[m2] *= np.clip((total - t[m2]) / max(r, 1e-4), 0, 1)
    return e


def osc(freq, sec=None, kind="sin", phase=0.0):
    """freq — число или массив по сэмплам"""
    if np.isscalar(freq):
        freq = np.full(int(round(sec * SR)), float(freq))
    ph = np.cumsum(freq) / SR + phase
    if kind == "sin":
        return np.sin(2 * np.pi * ph)
    if kind == "saw":
        return 2.0 * (ph % 1.0) - 1.0
    if kind == "sq":
        return np.sign(np.sin(2 * np.pi * ph))
    if kind == "tri":
        return 2.0 * np.abs(2.0 * (ph % 1.0) - 1.0) - 1.0
    return np.sin(2 * np.pi * ph)


def reverb(x, sec=1.6, wet=0.3, damp=4000, pre=0.0):
    n = int(sec * SR)
    ir = R.standard_normal(n) * np.exp(-np.arange(n) / SR * (6.9 / sec))
    ir = lp(ir, damp)
    if pre > 0:
        ir = np.concatenate([np.zeros(int(pre * SR)), ir])
    ir /= np.sqrt((ir ** 2).sum()) + 1e-9
    y = signal.fftconvolve(x, ir)[: len(x) + len(ir) - 1]
    out = np.zeros(len(y))
    out[: len(x)] += x * (1 - wet)
    out += y * wet * 1.2
    return out


def dist(x, k=3.0):
    return np.tanh(x * k) / np.tanh(k)


def norm(x, peak=0.9):
    m = np.abs(x).max()
    return x / m * peak if m > 0 else x


def fade(x, fi=0.005, fo=0.02):
    n = len(x)
    a = min(int(fi * SR), n // 2)
    b = min(int(fo * SR), n // 2)
    y = x.copy()
    if a > 0:
        y[:a] *= np.linspace(0, 1, a)
    if b > 0:
        y[-b:] *= np.linspace(1, 0, b)
    return y


def loopify(x, xf=0.5):
    """Бесшовная петля: конец перетекает в начало"""
    n = int(xf * SR)
    head = x[:n].copy()
    tail = x[-n:].copy()
    w = np.linspace(0, 1, n)
    y = x[:-n].copy()
    y[:n] = head * w + tail * (1 - w)
    return y


def place(dst, src, at):
    i = int(at * SR)
    if i >= len(dst):
        return dst
    m = min(len(src), len(dst) - i)
    dst[i:i + m] += src[:m]
    return dst


def resonator(x, f, bw):
    """Резонатор с меняющейся частотой (f, bw — массивы или числа)"""
    n = len(x)
    f = np.broadcast_to(np.asarray(f, float), (n,)) if np.ndim(f) else np.full(n, float(f))
    bw = np.broadcast_to(np.asarray(bw, float), (n,)) if np.ndim(bw) else np.full(n, float(bw))
    r = np.exp(-np.pi * bw / SR)
    c = 2 * r * np.cos(2 * np.pi * f / SR)
    d = -r * r
    g = 1 - r
    y = np.zeros(n)
    y1 = y2 = 0.0
    xs = x.tolist()
    cs = c.tolist()
    ds = d.tolist()
    gs = g.tolist()
    out = [0.0] * n
    for i in range(n):
        v = gs[i] * xs[i] + cs[i] * y1 + ds[i] * y2
        out[i] = v
        y2 = y1
        y1 = v
    return np.array(out)


VOWELS = {"a": (800, 1200, 2500), "o": (500, 900, 2400), "u": (330, 800, 2300), "e": (450, 1900, 2600),
          "i": (300, 2300, 3000), "y": (400, 1600, 2500)}


def voice(f0, vowel_path, breath=0.2, jitter=0.01, rough=0.0):
    """Формантный голос. f0 — массив высоты тона; vowel_path — список (время_доля, гласная)"""
    n = len(f0)
    f0 = f0 * (1 + jitter * lp(R.standard_normal(n), 30) * 3)
    src = osc(f0, kind="saw")
    src = lp(src, 3500, 1)
    if rough > 0:
        src *= 1 + rough * osc(f0 * 0.5, kind="sin")
    src = src + breath * hp(R.standard_normal(n), 800) * 0.5
    frac = np.linspace(0, 1, n)
    keys = [p[0] for p in vowel_path]
    out = np.zeros(n)
    for fi, bwv in zip(range(3), (90, 120, 180)):
        vals = [VOWELS[p[1]][fi] for p in vowel_path]
        fcurve = np.interp(frac, keys, vals)
        out += resonator(src, fcurve, bwv) * (1.0, 0.6, 0.3)[fi]
    return out


def save(name, x, stereo=False):
    x = np.asarray(x, dtype=float)
    x = np.clip(x, -1, 1)
    tmp = os.path.join(tempfile.gettempdir(), "bk_" + name + ".wav")
    wavfile.write(tmp, SR, (x * 32767).astype(np.int16))
    dst = os.path.join(OUT, name + ".ogg")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp, "-c:a", "libvorbis", "-q:a", "5", dst], check=True)
    os.remove(tmp)
    print("  ", name, f"{len(x) / SR:.1f}s")


# ----------------------------------------------------------------- Комплекс

def hum_fluor():
    """Главный звук Комплекса: гудение дросселей люминесцентных ламп (120 Гц и гармоники), дрожание, треск"""
    sec = 12.0
    t = T(sec)
    base = 120.0
    x = np.zeros(len(t))
    for h, a in [(1, 1.0), (2, 0.55), (3, 0.42), (4, 0.3), (5, 0.18), (6, 0.12), (8, 0.08), (10, 0.05), (12, 0.04)]:
        drift = 1 + 0.0015 * np.sin(2 * np.pi * (0.05 + h * 0.01) * t + h)
        x += a * np.sin(2 * np.pi * base * h * drift * t + R.random() * 6)
    x = dist(x * 0.8, 1.8)
    am = 1 + 0.08 * lp(R.standard_normal(len(t)), 3) * 6 + 0.03 * np.sin(2 * np.pi * 0.31 * t)
    x *= am
    whine = 0.012 * np.sin(2 * np.pi * 9800 * t) * (1 + 0.5 * np.sin(2 * np.pi * 0.2 * t))
    crackle = np.zeros(len(t))
    for k in range(40):
        place(crackle, hp(white(0.004), 2000) * R.uniform(0.02, 0.08), R.uniform(0, sec - 0.01))
    hiss = hp(white(sec), 3000) * 0.012
    y = lp(x, 3200) * 0.5 + whine + crackle + hiss
    save("hum_fluor", norm(loopify(y, 1.0), 0.6))


def room_tone():
    sec = 14.0
    x = lp(brown(sec), 180) * 0.8 + lp(pink(sec), 900) * 0.15
    x *= 1 + 0.2 * np.sin(2 * np.pi * 0.07 * T(sec))
    save("room_tone", norm(loopify(x, 1.5), 0.5))


def null_hum():
    """Нулевая зона: глубокая вибрация, биения, электрические искры"""
    sec = 10.0
    t = T(sec)
    x = np.sin(2 * np.pi * 29 * t) * 0.8 + np.sin(2 * np.pi * 31.3 * t) * 0.6 + np.sin(2 * np.pi * 58.7 * t) * 0.4
    x = dist(x, 2.0)
    x += 0.25 * np.sin(2 * np.pi * (3100 + 300 * np.sin(2 * np.pi * 0.17 * t)) * t) * (0.5 + 0.5 * np.sin(2 * np.pi * 0.5 * t))
    for k in range(70):
        z = hp(white(R.uniform(0.003, 0.03)), 1500) * R.uniform(0.2, 0.6)
        place(x, z, R.uniform(0, sec - 0.05))
    x = reverb(x, 1.2, 0.25)[: len(t)]
    save("null_hum", norm(loopify(x, 1.0), 0.75))


def null_burst():
    sec = 2.6
    t = T(sec)
    zap = hp(white(sec), 1200) * np.exp(-t * 5) * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 37 * t)))
    sweep = np.sin(2 * np.pi * np.cumsum(np.linspace(1800, 40, len(t))) / SR) * np.exp(-t * 1.5)
    rumble = lp(brown(sec), 120) * np.exp(-t * 1.2) * 1.5
    save("null_burst", norm(reverb(zap * 0.7 + sweep * 0.6 + rumble, 2.0, 0.4), 0.95))


def threshold_hum():
    sec = 10.0
    t = T(sec)
    x = np.zeros(len(t))
    for h, a in [(1, 1.0), (2, 0.6), (3, 0.4), (5, 0.2), (7, 0.12)]:
        x += a * np.sin(2 * np.pi * 50 * h * t)
    x = dist(x * 0.7, 2.0)
    x += lp(pink(sec), 500) * 0.4 * (1 + 0.5 * np.sin(2 * np.pi * 0.13 * t))
    x += 0.08 * np.sin(2 * np.pi * (1500 + 200 * np.sin(2 * np.pi * 0.3 * t)) * t)
    for k in range(25):
        place(x, hp(white(0.02), 2500) * 0.4, R.uniform(0, sec - 0.05))
    save("threshold_hum", norm(loopify(x, 1.0), 0.7))


def threshold_pass():
    sec = 3.5
    t = T(sec)
    w = bp(white(sec), 200, 3000) * np.sin(np.pi * t / sec) ** 2
    hum = np.sin(2 * np.pi * 50 * t) * np.exp(-t * 0.8) * 0.6
    save("threshold_pass", norm(reverb(w + hum, 2.5, 0.4), 0.9))


def steps():
    # ковёр: глухой мягкий удар + влажный шорох
    for i in range(6):
        sec = 0.35
        t = T(sec)
        thump = np.sin(2 * np.pi * R.uniform(60, 90) * t) * np.exp(-t * 35)
        scuff = bp(white(sec), 500, 2200) * np.exp(-t * R.uniform(18, 28)) * 0.35
        squish = bp(white(sec), 1500, 4000) * np.exp(-((t - 0.05) ** 2) / 0.0008) * 0.18
        save(f"step_carpet_{i + 1}", fade(norm(lp(thump * 0.9 + scuff + squish, 4000), 0.7)))
    for i in range(4):
        sec = 0.45
        t = T(sec)
        thump = np.sin(2 * np.pi * R.uniform(55, 80) * t) * np.exp(-t * 30)
        squelch = resonator(white(sec) * np.exp(-t * 14), np.linspace(1800, 500, len(t)), 300) * 0.25
        save(f"step_wet_{i + 1}", fade(norm(thump + squelch, 0.75)))
    for i in range(5):
        sec = 0.6
        t = T(sec)
        click = hp(white(sec), 1500) * np.exp(-t * 90) * 0.6
        thump = np.sin(2 * np.pi * R.uniform(90, 130) * t) * np.exp(-t * 45)
        grit = bp(white(sec), 2000, 6000) * np.exp(-t * 40) * 0.2
        save(f"step_concrete_{i + 1}", fade(norm(reverb(click + thump + grit, 0.8, 0.22), 0.75)))
    for i in range(4):
        sec = 0.6
        t = T(sec)
        click = hp(white(sec), 2500) * np.exp(-t * 120)
        ring = np.sin(2 * np.pi * R.uniform(1800, 2600) * t) * np.exp(-t * 60) * 0.25
        save(f"step_tile_{i + 1}", fade(norm(reverb(click + ring + np.sin(2 * np.pi * 110 * t) * np.exp(-t * 50) * 0.5, 0.9, 0.25), 0.7)))
    for i in range(4):
        sec = 0.5
        t = T(sec)
        body = np.sin(2 * np.pi * R.uniform(140, 190) * t) * np.exp(-t * 25) + np.sin(2 * np.pi * R.uniform(320, 420) * t) * np.exp(-t * 40) * 0.4
        creak = np.sin(2 * np.pi * np.cumsum(np.full(len(t), R.uniform(500, 800))) / SR) * np.exp(-((t - 0.12) ** 2) / 0.002) * 0.12
        save(f"step_wood_{i + 1}", fade(norm(body + hp(white(sec), 2000) * np.exp(-t * 80) * 0.3 + creak, 0.7)))
    for i in range(5):
        sec = 0.4
        t = T(sec)
        rust = hp(white(sec), 2500) * np.exp(-t * 18) * (0.5 + 0.5 * (R.random(len(t)) > 0.7))
        save(f"step_grass_{i + 1}", fade(norm(lp(rust, 9000) + np.sin(2 * np.pi * 70 * t) * np.exp(-t * 40) * 0.5, 0.6)))
    for i in range(5):
        sec = 0.35
        t = T(sec)
        grit = bp(white(sec), 1500, 7000) * np.exp(-t * 30) * (0.6 + 0.4 * (R.random(len(t)) > 0.6))
        save(f"step_path_{i + 1}", fade(norm(grit + np.sin(2 * np.pi * 85 * t) * np.exp(-t * 45) * 0.6, 0.65)))


def breath_heavy():
    for i in range(4):
        sec = 1.3
        t = T(sec)
        inh = bp(white(sec), 600, 2500) * np.clip(np.sin(np.pi * t / 0.55), 0, 1) * (t < 0.55)
        exh = bp(white(sec), 300, 1800) * np.clip(np.sin(np.pi * (t - 0.6) / 0.6), 0, 1) * (t > 0.6) * 1.3
        v = voice(np.full(len(t), R.uniform(110, 140)), [(0, "a"), (1, "a")], breath=1.0) * 0.08 * ((t > 0.6) & (t < 1.1))
        save(f"breath_heavy_{i + 1}", fade(norm(inh + exh + v, 0.55)))


def lifeform():
    """Крики Сущности — визгливые, «обезьяньи», с хрипом и рваной высотой"""
    for i in range(4):
        n_calls = R.integers(2, 5)
        sec = 0.25 + n_calls * 0.42 + 1.2
        x = np.zeros(int(sec * SR))
        at = 0.05
        for c in range(n_calls):
            d = R.uniform(0.25, 0.5)
            t = T(d)
            f0 = np.interp(t / d, [0, 0.3, 0.7, 1.0], [R.uniform(380, 520), R.uniform(1100, 1500), R.uniform(900, 1300), R.uniform(500, 700)])
            v = voice(f0, [(0, "u"), (0.35, "a"), (1, "a")], breath=0.6, jitter=0.03, rough=0.8)
            v = dist(v * 4.0, 3.0) * adsr(len(t), 0.02, 0.1, 0.8, 0.12)
            place(x, v, at)
            at += d * R.uniform(0.75, 1.0)
        growl = voice(np.full(len(x), R.uniform(70, 95)), [(0, "o"), (1, "a")], breath=0.8, rough=1.0)
        x += dist(growl * 2.0, 2.0) * 0.25 * env_ad(len(x), 0.05, 1.0)
        x = hp(x, 180)
        save(f"lf_scream_{i + 1}", norm(reverb(x, 1.8, 0.35, 5000), 0.95))
        far = lp(reverb(x, 3.5, 0.75, 1800), 1600)
        save(f"lf_far_{i + 1}", norm(far, 0.8))
    # зовёт человеческим голосом — бессловесные «помогите» с провалами
    for i in range(4):
        sec = R.uniform(1.6, 2.6)
        t = T(sec)
        f0 = np.interp(t / sec, [0, 0.25, 0.5, 0.8, 1.0], [R.uniform(230, 290), R.uniform(300, 360), R.uniform(250, 300), R.uniform(280, 330), R.uniform(180, 220)])
        path = [(0, "e"), (0.3, "e"), (0.45, "o"), (0.7, "o"), (1.0, "u")] if i % 2 == 0 else [(0, "a"), (0.4, "a"), (0.55, "o"), (1.0, "o")]
        v = voice(f0, path, breath=0.5, jitter=0.02) * adsr(len(t), 0.08, 0.2, 0.8, 0.4)
        # «запись»: обрывы и повтор кусочка
        cut = (np.sin(2 * np.pi * 3.3 * t + i) > -0.85).astype(float)
        v *= lp(cut, 40)
        v = np.concatenate([v, v[int(len(v) * 0.55):int(len(v) * 0.75)] * 0.7])
        save(f"lf_lure_{i + 1}", norm(reverb(bp(v, 250, 3500), 2.6, 0.55, 3000), 0.85))
    for i in range(4):
        sec = 0.5
        t = T(sec)
        thud = np.sin(2 * np.pi * R.uniform(45, 65) * t) * np.exp(-t * 18)
        crack = np.zeros(len(t))
        for k in range(6):
            place(crack, hp(white(0.006), 1500) * R.uniform(0.2, 0.5), R.uniform(0.0, 0.2))
        wet = bp(white(sec), 400, 1500) * np.exp(-t * 20) * 0.4
        save(f"lf_step_{i + 1}", fade(norm(thud + crack + wet, 0.85)))
    for i in range(3):
        sec = 2.2
        t = T(sec)
        rasp = bp(white(sec), 200, 1600) * (np.sin(np.pi * t / sec) ** 2)
        rasp *= 1 + 0.7 * np.sin(2 * np.pi * 23 * t)
        clicks = np.zeros(len(t))
        for k in range(12):
            place(clicks, hp(white(0.003), 1200) * 0.3, R.uniform(0, sec - 0.01))
        save(f"lf_breath_{i + 1}", norm(reverb(rasp + clicks, 1.2, 0.3), 0.6))


def stalker():
    for i in range(4):
        sec = R.uniform(2.0, 3.2)
        t = T(sec)
        sob = 0.5 + 0.5 * np.abs(np.sin(2 * np.pi * R.uniform(4.5, 6.0) * t))
        f0 = np.interp(t / sec, [0, 0.2, 0.6, 1.0], [R.uniform(380, 450), R.uniform(520, 620), R.uniform(430, 500), R.uniform(250, 320)])
        f0 *= 1 + 0.04 * np.sin(2 * np.pi * 6 * t)
        v = voice(f0, [(0, "u"), (0.3, "a"), (0.7, "u"), (1.0, "y")], breath=0.7, jitter=0.03, rough=0.3) * sob
        squeal = np.sin(2 * np.pi * np.cumsum(f0 * 2.02) / SR) * 0.08 * env_ad(len(t), 0.4, 1.5)
        x = (v + squeal) * adsr(len(t), 0.1, 0.3, 0.8, 0.6)
        save(f"st_wail_{i + 1}", norm(reverb(hp(x, 200), 2.2, 0.45), 0.85))
    for i in range(3):
        sec = 0.5
        t = T(sec)
        drag = bp(white(sec), 300, 1500) * np.exp(-t * 9) * 0.5
        thud = np.sin(2 * np.pi * 75 * t) * np.exp(-t * 30)
        save(f"st_step_{i + 1}", fade(norm(drag + thud, 0.6)))


def copies():
    for i in range(4):
        sec = R.uniform(1.5, 2.6)
        t = T(sec)
        syl = (np.sin(2 * np.pi * R.uniform(3.5, 5.5) * t) > 0.1).astype(float)
        syl = lp(syl, 25)
        n = hp(white(sec), 1500)
        f = 1200 + 900 * np.sin(2 * np.pi * 2.3 * t + i)
        w = resonator(n, f, 400) * syl
        save(f"copy_whisper_{i + 1}", norm(reverb(w, 1.4, 0.4), 0.5))
    for i in range(3):
        sec = 3.5
        t = T(sec)
        br = bp(white(sec), 300, 1400) * (np.sin(np.pi * (t % 1.75) / 1.75) ** 2)
        save(f"copy_breath_{i + 1}", norm(br, 0.4))
    for i in range(3):
        sec = 2.4
        t = T(sec)
        v = voice(np.linspace(R.uniform(140, 180), R.uniform(100, 120), len(t)), [(0, "o"), (1, "u")], breath=0.4) * adsr(len(t), 0.4, 0.3, 0.7, 0.8)
        save(f"copy_moan_{i + 1}", norm(reverb(v, 2.0, 0.5), 0.5))


def misc_complex():
    sec = 2.5
    t = T(sec)
    f = np.interp(t / sec, [0, 0.2, 1], [2500, 3200, 1800])
    scr = np.sin(2 * np.pi * np.cumsum(f * (1 + 0.02 * R.standard_normal(len(t)))) / SR)
    scr = dist(scr, 2) * adsr(len(t), 0.05, 0.4, 0.6, 1.0)
    save("screech_far", norm(lp(reverb(scr, 3.5, 0.7, 2500), 3000), 0.6))
    for i in range(3):
        sec = 1.8
        t = T(sec)
        cr = np.zeros(len(t))
        for k in range(30):
            place(cr, bp(white(0.02), 300, 2000) * R.uniform(0.1, 0.5), R.uniform(0, sec - 0.05))
        cr += resonator(white(sec) * 0.05, np.linspace(200, 120, len(t)), 30) * 0.5
        save(f"nest_creak_{i + 1}", norm(reverb(cr, 1.5, 0.35), 0.5))
    # стук в стену
    for i in range(2):
        sec = 1.6
        x = np.zeros(int(sec * SR))
        for k in range(3 + i):
            tt = T(0.25)
            hit = np.sin(2 * np.pi * R.uniform(110, 150) * tt) * np.exp(-tt * 30) + bp(white(0.25), 200, 900) * np.exp(-tt * 40) * 0.5
            place(x, hit, 0.05 + k * R.uniform(0.25, 0.35))
        save(f"knock_{i + 1}", norm(lp(reverb(x, 0.6, 0.2), 1600), 0.8))
    sec = 2.2
    t = T(sec)
    rush = dist(white(sec) * 2.0 + lp(brown(sec), 200) * 2, 3) * np.clip(t / 0.05, 0, 1) * (t < 1.7)
    save("noise_rush", norm(rush, 0.95))
    # тиканье остывающего мотора
    sec = 8.0
    x = np.zeros(int(sec * SR))
    for k in range(18):
        tt = T(0.05)
        place(x, np.sin(2 * np.pi * R.uniform(2500, 4000) * tt) * np.exp(-tt * 200) * R.uniform(0.3, 1), R.uniform(0, sec - 0.1))
    save("engine_tick", norm(reverb(x, 0.5, 0.2), 0.5))


def melody(notes, bpm, wave="box", detune=0.0, wobble=0.0, drop=0.0):
    """notes: [(midi|None, beats)] — музыкальная шкатулка"""
    beat = 60.0 / bpm
    total = sum(b for _, b in notes) * beat + 1.5
    x = np.zeros(int(total * SR))
    at = 0.0
    for m, b in notes:
        if m is not None and R.random() >= drop:
            f = 440.0 * 2 ** ((m - 69) / 12.0) * (1 + detune * R.uniform(-1, 1))
            d = 1.4
            t = T(d)
            fw = f * (1 + wobble * np.sin(2 * np.pi * 0.7 * (t + at)))
            tone = osc(fw, kind="sin") + 0.35 * osc(fw * 2.01, kind="sin") * np.exp(-t * 6) + 0.15 * osc(fw * 3.98, kind="sin") * np.exp(-t * 9)
            place(x, tone * np.exp(-t * 3.5) * 0.5, at)
        at += b * beat
    return x


JINGLE = [(72, 0.5), (76, 0.5), (79, 0.5), (76, 0.5), (77, 0.5), (81, 0.5), (79, 1.0), (76, 0.5), (79, 0.5), (84, 0.5), (83, 0.5),
          (81, 0.5), (79, 0.5), (77, 1.0), (74, 0.5), (77, 0.5), (81, 0.5), (79, 0.5), (77, 0.5), (76, 0.5), (74, 0.5), (72, 1.5), (None, 1.0)]
LULLABY = [(69, 1.0), (72, 0.5), (71, 0.5), (69, 1.0), (64, 1.0), (65, 1.0), (64, 0.5), (62, 0.5), (60, 2.0), (64, 1.0), (65, 0.5),
           (67, 0.5), (69, 1.0), (72, 1.0), (71, 1.0), (68, 0.5), (66, 0.5), (69, 2.0), (None, 1.0)]


def music():
    j = melody(JINGLE, 150)
    j = reverb(j, 0.8, 0.15)
    save("jingle", norm(loopify(j[: int(len(j) * 0.97)], 0.3), 0.6))
    jw = melody(JINGLE, 92, detune=0.025, wobble=0.012, drop=0.15)
    jw = lp(reverb(jw, 3.0, 0.6), 2500)
    save("jingle_wrong", norm(loopify(jw, 0.6), 0.55))
    mb = melody(LULLABY, 70, detune=0.012, wobble=0.008, drop=0.08)
    save("music_box", norm(loopify(reverb(mb, 2.5, 0.5), 0.6), 0.5))


def chirp(f0, f1, d):
    t = T(d)
    f = np.linspace(f0, f1, len(t)) * (1 + 0.1 * np.sin(2 * np.pi * 40 * t))
    return osc(f) * np.sin(np.pi * t / d) ** 2


def birds():
    for i in range(6):
        sec = 1.4
        x = np.zeros(int(sec * SR))
        n = R.integers(2, 6)
        at = 0.02
        base = R.uniform(2500, 4500)
        for k in range(n):
            d = R.uniform(0.05, 0.14)
            place(x, chirp(base * R.uniform(0.9, 1.2), base * R.uniform(0.7, 1.4), d), at)
            at += d + R.uniform(0.02, 0.12)
        save(f"bird_{i + 1}", norm(reverb(x, 0.9, 0.15), 0.6))
    # «неправильные» птицы в комнате с деревом: ниже, задом наперёд, с эхом
    sec = 12.0
    x = np.zeros(int(sec * SR))
    for k in range(14):
        d = R.uniform(0.15, 0.4)
        c = chirp(R.uniform(900, 1600), R.uniform(600, 1300), d)[::-1]
        place(x, c * 0.6, R.uniform(0, sec - 0.5))
    save("birds_wrong", norm(loopify(reverb(x, 2.5, 0.6), 1.0), 0.45))


def park():
    sec = 24.0
    t = T(sec)
    traffic = lp(brown(sec), 350) * (0.6 + 0.4 * np.sin(2 * np.pi * 0.05 * t)) * 0.6
    leaves = hp(pink(sec), 2000) * 0.06 * (1 + 0.6 * lp(R.standard_normal(len(t)), 0.5) * 30)
    kids = np.zeros(len(t))
    for k in range(18):
        d = R.uniform(0.3, 0.9)
        tt = T(d)
        f0 = np.interp(tt / d, [0, 0.5, 1], [R.uniform(300, 450), R.uniform(450, 650), R.uniform(300, 400)])
        v = voice(f0, [(0, R.choice(list("aeo"))), (1, R.choice(list("aeiou")))], breath=0.3) * adsr(len(tt), 0.05, 0.1, 0.7, 0.2)
        place(kids, v * R.uniform(0.2, 0.6), R.uniform(0, sec - 1))
    kids = lp(reverb(kids, 1.5, 0.5), 2500)[: len(t)] * 0.25
    x = traffic + leaves + kids
    for k in range(10):
        b = np.zeros(int(1.0 * SR))
        at = 0.0
        for c in range(R.integers(2, 5)):
            d = R.uniform(0.05, 0.12)
            place(b, chirp(R.uniform(2800, 4500), R.uniform(2500, 5000), d), at)
            at += d + 0.06
        place(x, b * R.uniform(0.05, 0.15), R.uniform(0, sec - 1.2))
    save("park_ambience", norm(loopify(x, 1.5), 0.55))
    sec = 16.0
    t = T(sec)
    w = bp(pink(sec), 200, 3000) * (0.5 + 0.5 * np.abs(lp(R.standard_normal(len(t)), 0.3)) * 40)
    save("wind_trees", norm(loopify(hp(w, 150), 1.5), 0.5))
    sec = 8.0
    t = T(sec)
    wat = bp(white(sec), 500, 6000) * (0.7 + 0.3 * lp(R.standard_normal(len(t)), 8) * 4)
    bub = np.zeros(len(t))
    for k in range(160):
        d = 0.03
        place(bub, chirp(R.uniform(600, 1800), R.uniform(900, 2600), d) * 0.2, R.uniform(0, sec - 0.05))
    save("water_loop", norm(loopify(wat * 0.5 + bub, 0.8), 0.5))


def machines():
    sec = 6.0
    t = T(sec)
    pulses = np.zeros(len(t))
    period = 1 / 26.0
    k = 0
    while k * period < sec - 0.05:
        tt = T(0.04)
        place(pulses, np.sin(2 * np.pi * 70 * tt) * np.exp(-tt * 60), k * period)
        k += 1
    gen = dist(pulses * 1.5, 2) + lp(pink(sec), 1200) * 0.2
    save("generator", norm(loopify(gen, 0.5), 0.6))
    sec = 6.0
    t = T(sec)
    tv = bp(white(sec), 500, 8000) * 0.7 + 0.04 * np.sin(2 * np.pi * 15734 * t)
    save("tv_static", norm(loopify(tv, 0.5), 0.45))
    fr = np.sin(2 * np.pi * 60 * t) * 0.6 + np.sin(2 * np.pi * 120 * t) * 0.3 + lp(pink(sec), 300) * 0.3
    save("fridge_hum", norm(loopify(fr, 0.5), 0.4))
    rs = bp(white(sec), 300, 4000) * (0.6 + 0.4 * np.abs(np.sin(2 * np.pi * 0.7 * t)))
    rs += np.sin(2 * np.pi * 1000 * t) * 0.03 * (np.sin(2 * np.pi * 0.2 * t) > 0.95)
    save("radio_static", norm(loopify(rs, 0.4), 0.45))
    sec = 5.0
    t = T(sec)
    whir = np.sin(2 * np.pi * 180 * t) * 0.3 * (1 + 0.1 * np.sin(2 * np.pi * 3 * t)) + bp(white(sec), 1000, 3000) * 0.1
    save("tape_whir", norm(loopify(whir, 0.4), 0.3))


def outdoors():
    sec = 16.0
    t = T(sec)
    swell = 0.5 + 0.5 * np.sin(2 * np.pi * t / 8.0) ** 2
    sea = lp(pink(sec), 1500) * swell + hp(white(sec), 3000) * 0.15 * swell ** 3
    save("sea_waves", norm(loopify(sea, 2.0), 0.6))
    wind = bp(pink(sec), 150, 1500) * (0.6 + 0.4 * np.sin(2 * np.pi * 0.1 * t) ** 2)
    save("wind_open", norm(loopify(wind, 1.5), 0.5))
    wf = dist(lp(white(sec), 1200) * (1 + 0.6 * lp(R.standard_normal(len(t)), 4) * 10), 1.5) + lp(brown(sec), 200)
    save("wind_fall", norm(loopify(wf, 1.0), 0.85))
    sec = 10.0
    t = T(sec)
    cr = np.zeros(len(t))
    for k in range(60):
        tt = T(0.25)
        c = np.sin(2 * np.pi * 4300 * tt) * (np.sin(2 * np.pi * 30 * tt) > 0) * np.exp(-tt * 8)
        place(cr, c * R.uniform(0.05, 0.2), R.uniform(0, sec - 0.3))
    save("crickets", norm(loopify(cr, 1.0), 0.4))
    sec = 14.0
    t = T(sec)
    tvv = np.zeros(len(t))
    at = 0.2
    while at < sec - 1.5:
        d = R.uniform(0.4, 1.4)
        tt = T(d)
        f0 = np.full(len(tt), R.uniform(110, 210)) * (1 + 0.15 * np.sin(2 * np.pi * 3 * tt))
        v = voice(f0, [(0, R.choice(list("aeo"))), (0.5, R.choice(list("iuy"))), (1, R.choice(list("aeo")))], breath=0.2)
        place(tvv, v * adsr(len(tt), 0.03, 0.1, 0.8, 0.1), at)
        at += d + R.uniform(0.1, 0.6)
    tvv = lp(tvv, 500) + lp(pink(sec), 300) * 0.15
    save("upstairs_tv", norm(loopify(tvv, 1.0), 0.45))
    for i in range(3):
        sec = 2.5
        x = np.zeros(int(sec * SR))
        for k in range(R.integers(3, 6)):
            tt = T(0.3)
            place(x, np.sin(2 * np.pi * 60 * tt) * np.exp(-tt * 25), 0.1 + k * R.uniform(0.4, 0.6))
        save(f"footsteps_above_{i + 1}", norm(lp(x, 300), 0.6))


def sfx():
    # видеокамера, плёнка, интерфейс
    t = T(0.12)
    save("rec_beep", fade(norm(np.sin(2 * np.pi * 2400 * t) * (t < 0.08), 0.5)))
    t = T(0.06)
    save("ui_move", fade(norm(np.sin(2 * np.pi * 1800 * t) * np.exp(-t * 60), 0.4)))
    t = T(0.15)
    save("ui_click", fade(norm(np.sin(2 * np.pi * 1200 * t) * np.exp(-t * 40) + hp(white(0.15), 3000) * np.exp(-t * 200) * 0.3, 0.5)))
    sec = 2.2
    t = T(sec)
    clunk = (np.sin(2 * np.pi * 90 * t) * np.exp(-t * 20) + hp(white(sec), 1200) * np.exp(-t * 60) * 0.5)
    motor = np.sin(2 * np.pi * np.cumsum(np.interp(t, [0, 0.4, 2.2], [40, 160, 160])) / SR) * 0.25 * (t > 0.3)
    save("tape_insert", norm(clunk + motor, 0.7))
    sec = 1.6
    t = T(sec)
    wind = np.sin(2 * np.pi * np.cumsum(np.interp(t, [0, 1.2], [180, 20])) / SR) * 0.4 * np.exp(-t * 1.5)
    save("tape_stop", norm(np.sin(2 * np.pi * 80 * t) * np.exp(-t * 25) + hp(white(sec), 1500) * np.exp(-t * 50) * 0.5 + wind, 0.8))
    sec = 3.0
    t = T(sec)
    save("card_hum", norm(lp(pink(sec), 300) * adsr(len(t), 0.5, 0.5, 0.8, 1.2), 0.4))
    sec = 0.9
    t = T(sec)
    g = white(sec) * (np.sin(2 * np.pi * 7 * t) > 0) * np.exp(-t * 3)
    g += np.sin(2 * np.pi * np.cumsum(R.uniform(200, 3000, len(t)) * 0 + 1000 + 800 * np.sign(np.sin(2 * np.pi * 13 * t))) / SR) * 0.3 * np.exp(-t * 4)
    save("glitch", norm(g, 0.8))
    save("cam_switch", norm(np.concatenate([hp(white(0.03), 2000) * 0.8, bp(white(0.4), 500, 6000) * np.exp(-T(0.4) * 8) * 0.5]), 0.6))
    sec = 2.0
    t = T(sec)
    save("fall_whoosh", norm(bp(white(sec), 200, 2500) * (t / sec) ** 2 + lp(brown(sec), 150) * (t / sec), 0.85))
    sec = 0.8
    t = T(sec)
    body = np.sin(2 * np.pi * 55 * t) * np.exp(-t * 12) + bp(white(sec), 100, 900) * np.exp(-t * 18) * 0.7
    save("body_fall", norm(body, 0.9))
    save("thud_land", norm(np.sin(2 * np.pi * 50 * t) * np.exp(-t * 10) + lp(white(sec), 400) * np.exp(-t * 20) * 0.5, 0.9))
    sec = 0.7
    t = T(sec)
    cl = np.zeros(len(t))
    for k in range(5):
        tt = T(0.08)
        place(cl, (hp(white(0.08), 1500) + np.sin(2 * np.pi * R.uniform(800, 1500) * tt) * 0.5) * np.exp(-tt * 70), k * 0.07 + R.uniform(0, 0.03))
    save("camera_drop", norm(cl, 0.7))
    sec = 0.9
    t = T(sec)
    save("cloth", norm(bp(white(sec), 800, 5000) * np.sin(np.pi * t / sec) * (0.5 + 0.5 * (R.random(len(t)) > 0.5)), 0.4))
    sec = 0.6
    t = T(sec)
    save("paper", norm(hp(white(sec), 2000) * np.sin(np.pi * t / sec) ** 2 * (0.4 + 0.6 * np.abs(np.sin(2 * np.pi * 15 * t))), 0.45))
    sec = 3.0
    x = np.zeros(int(sec * SR))
    for k in range(6):
        tt = T(0.4)
        cr = resonator(white(0.4) * 0.3, np.linspace(R.uniform(300, 500), R.uniform(200, 300), len(tt)), 40) * np.exp(-tt * 6)
        place(x, cr + np.sin(2 * np.pi * 120 * tt) * np.exp(-tt * 30) * 0.4, k * 0.45)
    save("ladder", norm(x, 0.7))
    t = T(0.2)
    save("radio_click", fade(norm(hp(white(0.2), 1000) * np.exp(-t * 30) + np.sin(2 * np.pi * 1000 * t) * (t < 0.08) * 0.3, 0.6)))
    # стингеры
    sec = 4.0
    t = T(sec)
    s = sum(osc(f * (1 + 0.003 * k), sec, "saw") for k, f in enumerate([55, 58.3, 82.4, 87.3]))
    save("sting_low", norm(lp(s, 600) * adsr(len(t), 1.2, 1.0, 0.7, 1.5), 0.7))
    sec = 2.0
    t = T(sec)
    s2 = dist(sum(osc(f, sec, "saw") for f in [220, 233, 311, 466]) * 0.5, 3) * np.exp(-t * 1.5)
    save("sting_chase", norm(reverb(hp(s2, 200) + white(sec) * np.exp(-t * 6) * 0.4, 1.5, 0.3), 0.85))
    sec = 1.5
    t = T(sec)
    save("death_hit", norm(dist(white(sec) * 3 + osc(70, sec, "saw") * 2, 4) * np.exp(-t * 2.5), 0.98))
    sec = 10.0
    t = T(sec)
    dr = osc(41.2, sec, "saw") * 0.5 + osc(43.65, sec, "saw") * 0.4 + osc(1760, sec, "sin") * 0.03 * (1 + np.sin(2 * np.pi * 0.3 * t))
    save("death_drone", norm(loopify(lp(dr, 400) + lp(pink(sec), 200) * 0.2, 1.0), 0.6))
    # концовки
    sec = 2.5
    t = T(sec)
    sp = lp(white(sec), 3000) * np.exp(-t * 2.5) + lp(brown(sec), 200) * np.exp(-t * 1.5) * 2
    bubbles = np.zeros(len(t))
    for k in range(80):
        place(bubbles, chirp(R.uniform(400, 1200), R.uniform(800, 2000), 0.03) * 0.3, R.uniform(0.2, sec - 0.1))
    save("splash", norm(sp + bubbles, 0.9))
    sec = 1.0
    t = T(sec)
    save("splash_small", norm(bp(white(sec), 600, 5000) * np.exp(-t * 6), 0.5))
    sec = 1.2
    t = T(sec)
    gasp = bp(white(sec), 500, 3000) * np.clip(np.sin(np.pi * t / 0.6), 0, 1) * (t < 0.6) + voice(np.full(len(t), 160.0), [(0, "a"), (1, "a")], breath=1.0) * 0.1 * (t < 0.5)
    save("gasp", norm(gasp, 0.7))
    sec = 2.0
    t = T(sec)
    save("impact_far", norm(lp(white(sec), 800) * np.exp(-t * 4) + np.sin(2 * np.pi * 40 * t) * np.exp(-t * 3), 0.9))
    sec = 2.6
    t = T(sec)
    horn = (osc(277, sec, "saw") + osc(349, sec, "saw") * 0.8 + osc(415, sec, "saw") * 0.5) * adsr(len(t), 0.05, 0.1, 0.9, 0.3)
    save("horn", norm(lp(horn, 2500), 0.85))
    sec = 6.0
    t = T(sec)
    roar = lp(brown(sec), 400) * 2 + osc(np.interp(t, [0, 3, 6], [70, 75, 55]), kind="saw") * 0.4
    roar *= np.exp(-((t - 3.0) ** 2) / 2.0)
    save("truck_pass", norm(roar + bp(white(sec), 300, 3000) * np.exp(-((t - 3.0) ** 2) / 0.5) * 0.8, 0.9))
    sec = 3.0
    t = T(sec)
    save("brakes", norm(osc(np.interp(t, [0, 3], [2200, 1900]), kind="saw") * 0.2 * adsr(len(t), 0.2, 0.2, 0.8, 0.5) + lp(brown(sec), 300) * np.exp(-t), 0.6))
    sec = 3.5
    t = T(sec)
    save("gas_hiss", norm(hp(white(sec), 2500) * adsr(len(t), 0.05, 0.2, 0.8, 1.0), 0.8))
    x = np.zeros(int(2.0 * SR))
    for k in range(4):
        tt = T(0.25)
        place(x, osc(880, 0.25, "sq") * 0.3 * (tt < 0.2), k * 0.45)
    save("alarm_short", norm(reverb(x, 1.0, 0.3), 0.6))
    sec = 4.0
    t = T(sec)
    mv = np.zeros(len(t))
    at = 0.1
    while at < sec - 0.8:
        d = R.uniform(0.3, 0.8)
        tt = T(d)
        v = voice(np.full(len(tt), R.uniform(100, 140)) * (1 + 0.1 * np.sin(2 * np.pi * 2 * tt)), [(0, R.choice(list("aeo"))), (1, R.choice(list("uiy")))], breath=0.3)
        place(mv, v * adsr(len(tt), 0.03, 0.1, 0.8, 0.1), at)
        at += d + R.uniform(0.1, 0.4)
    save("muffled_voices", norm(lp(reverb(mv, 0.8, 0.3), 700), 0.6))
    sec = 4.0
    x = np.zeros(int(sec * SR))
    for k in range(8):
        tt = T(0.3)
        place(x, np.sin(2 * np.pi * 100 * tt) * np.exp(-tt * 35) + bp(white(0.3), 1000, 4000) * np.exp(-tt * 12) * 0.4, 0.2 + k * 0.45)
    save("hazmat_steps", norm(reverb(x, 0.9, 0.25), 0.6))
    sec = 1.6
    t = T(sec)
    lock = np.sin(2 * np.pi * 70 * t) * np.exp(-t * 8) + hp(white(sec), 800) * np.exp(-t * 30) * 0.6 + np.sin(2 * np.pi * 620 * t) * np.exp(-t * 6) * 0.2
    save("door_lock", norm(reverb(lock, 1.0, 0.3), 0.9))
    sec = 1.0
    x = np.zeros(int(sec * SR))
    for k in range(4):
        tt = T(0.12)
        place(x, (np.sin(2 * np.pi * 300 * tt) + hp(white(0.12), 1500) * 0.5) * np.exp(-tt * 35), k * 0.17)
    save("door_rattle", norm(x, 0.7))


def hatch():
    for i in range(3):
        sec = 0.9
        t = T(sec)
        thud = np.sin(2 * np.pi * R.uniform(60, 80) * t) * np.exp(-t * 14) + bp(white(sec), 150, 900) * np.exp(-t * 18) * 0.6
        creak = resonator(white(sec) * 0.25 * np.exp(-((t - 0.25) ** 2) / 0.02), np.linspace(R.uniform(380, 520), R.uniform(250, 330), len(t)), 25)
        rattle = np.zeros(len(t))
        for k in range(5):
            place(rattle, hp(white(0.02), 1500) * R.uniform(0.1, 0.3), R.uniform(0.02, 0.3))
        save(f"hatch_strain_{i + 1}", norm(reverb(thud + creak * 0.8 + rattle, 0.6, 0.25), 0.9))
    for i in range(3):
        sec = 0.8
        t = T(sec)
        f0 = np.interp(t / sec, [0, 0.3, 1], [R.uniform(120, 150), R.uniform(170, 210), R.uniform(110, 130)])
        g = voice(f0, [(0, "y"), (0.4, "a"), (1, "u")], breath=0.7, rough=0.5) * adsr(len(t), 0.05, 0.1, 0.8, 0.25)
        save(f"grunt_{i + 1}", norm(lp(g, 2500), 0.6))


def main():
    os.makedirs(OUT, exist_ok=True)
    only = sys.argv[1:]
    jobs = [("hum_fluor", hum_fluor), ("room_tone", room_tone), ("null_hum", null_hum), ("null_burst", null_burst),
            ("threshold", threshold_hum), ("threshold_pass", threshold_pass), ("step", steps), ("breath", breath_heavy),
            ("lf_", lifeform), ("st_", stalker), ("copy_", copies), ("misc", misc_complex), ("music", music), ("bird", birds),
            ("park", park), ("machines", machines), ("outdoors", outdoors), ("sfx", sfx), ("hatch", hatch)]
    for name, fn in jobs:
        if only and not any(name.startswith(o) or o.startswith(name) for o in only):
            continue
        fn()


if __name__ == "__main__":
    main()
