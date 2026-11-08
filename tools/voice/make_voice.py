"""Голоса: рация Async, динамик изолятора, человек за стеной. Windows TTS → обработка → voice/<ключ>_<ru|en>.ogg
    python tools/voice/make_voice.py
"""
import json, os, re, subprocess, sys, tempfile
import numpy as np
from scipy import signal
from scipy.io import wavfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "voice")
SR = 44100
R = np.random.default_rng(7)

src = open(os.path.join(ROOT, "src", "autoload", "texts.gd"), encoding="utf-8").read()
BS = chr(92)
STR = '"((?:[^"' + BS + BS + ']|' + BS + BS + '.)*)"'
pat = re.compile('"((?:radio|int|sub)' + BS + '.[a-z0-9_]+)":' + BS + 's*' + BS + '[' + BS + 's*' + STR + ',' + BS + 's*' + STR + BS + 's*' + BS + ']', re.S)
lines = {m.group(1): (m.group(2), m.group(3)) for m in pat.finditer(src)}
WANT = [k for k in lines if k.startswith("radio.") or k.startswith("int.") or k.startswith("sub.wall")]

def voice_for(key, lang):
    if lang == "en":
        return "Zira"
    if key.startswith("radio."):
        return "Irina"
    return "Pavel"

def rate_for(key):
    if key.startswith("sub.wall"):
        return 1.15
    if key.startswith("int."):
        return 0.92
    return 1.0

tmp = tempfile.mkdtemp(prefix="bkvoice_")
items = []
for k in WANT:
    for li, lang in enumerate(("ru", "en")):
        text = lines[k][li].replace("\n", " ").replace('\\"', '"').strip(". ")
        items.append({"key": k, "lang": lang, "text": text, "voice": voice_for(k, lang), "rate": rate_for(k),
                      "out": os.path.join(tmp, f"{k.replace('.', '_')}_{lang}.wav")})
jp = os.path.join(tmp, "lines.json")
json.dump(items, open(jp, "w", encoding="utf-8"), ensure_ascii=False)
ps = os.path.join(ROOT, "tools", "voice", "tts.ps1")
r = subprocess.run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", ps, "-Json", jp], capture_output=True, text=True, encoding="utf-8", errors="replace")
print(r.stdout[-2000:], r.stderr[-2000:])

def bp(x, lo, hi):
    b, a = signal.butter(2, [lo / (SR / 2), hi / (SR / 2)], "band")
    return signal.lfilter(b, a, x)

def lp(x, fc):
    b, a = signal.butter(2, fc / (SR / 2), "low")
    return signal.lfilter(b, a, x)

def reverb(x, sec, wet, damp=3000):
    n = int(sec * SR)
    ir = R.standard_normal(n) * np.exp(-np.arange(n) / SR * (6.9 / sec))
    ir = lp(ir, damp)
    ir /= np.sqrt((ir ** 2).sum())
    y = signal.fftconvolve(x, ir)
    out = np.zeros(len(y))
    out[:len(x)] += x * (1 - wet)
    out += y * wet
    return out

def load(path):
    sr, d = wavfile.read(path)
    d = d.astype(float)
    if d.ndim > 1:
        d = d.mean(axis=1)
    d /= (np.abs(d).max() + 1e-9)
    if sr != SR:
        d = signal.resample_poly(d, SR, sr)
    return d

os.makedirs(OUT, exist_ok=True)
for it in items:
    if not os.path.exists(it["out"]):
        print("нет", it["out"])
        continue
    x = load(it["out"])
    k = it["key"]
    pad = np.zeros(int(0.25 * SR))
    if k.startswith("radio."):
        y = bp(x, 350, 2800)
        y = np.tanh(y * 3.0)
        y = np.concatenate([pad, y, pad])
        stat = bp(R.standard_normal(len(y)), 400, 5000) * 0.12
        y = y * 0.8 + stat
        click = R.standard_normal(int(0.04 * SR)) * 0.5
        y[:len(click)] += click
        y[-len(click):] += click
    elif k.startswith("int."):
        y = bp(x, 250, 4200)
        y = np.tanh(y * 1.6)
        y = reverb(np.concatenate([pad, y, pad]), 0.5, 0.25, 4000)
        y += np.sin(2 * np.pi * 60 * np.arange(len(y)) / SR) * 0.015
    else:
        y = lp(x, 800) * 1.3
        y = reverb(np.concatenate([pad, y, pad]), 0.9, 0.35, 1500)
    y = y / (np.abs(y).max() + 1e-9) * 0.9
    tw = os.path.join(tmp, "p_" + os.path.basename(it["out"]))
    wavfile.write(tw, SR, (y * 32767).astype(np.int16))
    dst = os.path.join(OUT, f"{k.replace('.', '_')}_{it['lang']}.ogg")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tw, "-c:a", "libvorbis", "-q:a", "4", dst], check=True)
    print("  ", os.path.basename(dst), f"{len(y)/SR:.1f}s")
