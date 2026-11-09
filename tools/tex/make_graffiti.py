"""Надписи на стенах — не шрифтом, а «от руки»: каждая фраза рисуется в текстуру tex/graf_<ключ>_<ru|en>.png.

Буквы пляшут (наклон, размер, строка), штрих неровный; стиль выбирается по ключу:
  marker — маркер, сухая кисть;  spray — баллончик с ореолом и потёками;
  scratch — процарапано/карандаш, светлое и тонкое;  smear — бурый мазок пальцами, потёки.
Тексты берутся из src/autoload/texts.gd (ключи graf.*). Запуск: python tools/tex/make_graffiti.py
"""
import hashlib
import math
import os
import re
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "tex")
FONTS = r"C:\Windows\Fonts"
# Segoe Print — почерк с нормальной кириллицей и латиницей (у Ink Free «Н»/«H» похожи на «#»)
HANDS = {
    "marker": ["segoeprb.ttf"],
    "spray": ["segoeprb.ttf"],
    "scratch": ["segoepr.ttf"],
    "smear": ["segoeprb.ttf"],
}
INK = {
    "marker": [(22, 18, 16), (14, 16, 30), (40, 12, 10)],
    "spray": [(16, 14, 14), (95, 14, 10), (20, 34, 70)],
    "scratch": [(38, 35, 31), (52, 47, 40)],
    "smear": [(80, 14, 8), (62, 30, 14)],
}
SIZE = 78


def rng_for(key):
    return np.random.default_rng(int(hashlib.md5(key.encode("utf-8")).hexdigest()[:8], 16))


def load_texts():
    src = open(os.path.join(ROOT, "src", "autoload", "texts.gd"), encoding="utf-8").read()
    out = {}
    for m in re.finditer(r'"(graf\.[a-z0-9_]+)"\s*:\s*\[\s*"((?:[^"\\]|\\.)*)"\s*,\s*"((?:[^"\\]|\\.)*)"\s*\]', src, re.S):
        un = lambda s: s.replace('\\"', '"').replace("\\n", "\n")
        out[m.group(1)] = (un(m.group(2)), un(m.group(3)))
    return out


def wrap(text, width=15):
    lines = []
    for para in text.split("\n"):
        cur = ""
        for w in para.split(" "):
            if cur and len(cur) + 1 + len(w) > width:
                lines.append(cur)
                cur = w
            else:
                cur = (cur + " " + w).strip()
        lines.append(cur)
    return lines


def glyph(ch, font, stroke):
    """Один знак на прозрачном холсте (белым), с запасом под поворот."""
    bb = font.getbbox(ch, stroke_width=stroke)
    w = max(8, bb[2] - bb[0] + 24)
    h = max(8, bb[3] - bb[1] + 24)
    im = Image.new("L", (w, h), 0)
    ImageDraw.Draw(im).text((12 - bb[0], 12 - bb[1]), ch, font=font, fill=255, stroke_width=stroke, stroke_fill=255)
    return im, bb


def render(text, style, r):
    hands = HANDS[style]
    # у Ink Free странная кириллица («Н» похожа на «#») — для русского только Segoe Print
    if re.search("[а-яёА-ЯЁ]", text):
        hands = ["segoepr.ttf"] if style == "scratch" else ["segoeprb.ttf"]
    font = ImageFont.truetype(os.path.join(FONTS, hands[r.integers(0, len(hands))]), SIZE)
    stroke = {"marker": 3, "spray": 3, "scratch": 1, "smear": 3}[style]
    lines = wrap(text, 14 if style in ("spray", "smear") else 16)
    W, H = 1400, 140 + 118 * len(lines)
    mask = Image.new("L", (W, H), 0)
    y0 = 60
    max_x = 0
    for li, line in enumerate(lines):
        x = 50 + int(r.integers(-10, 30))
        drift = r.uniform(-0.025, 0.025)        # строка чуть уходит вверх/вниз
        size_drift = r.uniform(-0.06, 0.06)     # и чуть мельчает/растёт к концу
        for ci, ch in enumerate(line):
            if ch == " ":
                x += int(SIZE * r.uniform(0.32, 0.5))
                continue
            g, bb = glyph(ch, font, stroke)
            k = 1.0 + size_drift * ci / max(1, len(line)) + r.uniform(-0.05, 0.06)
            g = g.resize((max(4, int(g.width * k)), max(4, int(g.height * k))), Image.BILINEAR)
            g = g.rotate(r.uniform(-4, 4), resample=Image.BILINEAR, expand=True)
            gy = y0 + li * 118 + int(bb[1] * k) + int(r.normal(0, 2.5)) + int(drift * x)
            mask.paste(255, (x, gy), g)
            x += int((bb[2] - bb[0]) * k * r.uniform(0.86, 1.0)) + int(r.integers(-2, 6))
            max_x = max(max_x, x)
    a = np.asarray(mask).astype(np.float32) / 255.0
    H2, W2 = a.shape
    # неровный штрих: шум «сухой кисти» / шероховатость
    nz = np.asarray(Image.fromarray((r.random((H2 // 4 + 1, W2 // 4 + 1)) * 255).astype(np.uint8)).resize((W2, H2), Image.BILINEAR)).astype(np.float32) / 255.0
    fine = r.random((H2, W2)).astype(np.float32)
    if style == "marker":
        a = a * np.clip(0.55 + nz * 0.7, 0, 1) * np.where(fine < 0.06, 0.4, 1.0)
        a = np.asarray(Image.fromarray((a * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.8))).astype(np.float32) / 255.0
    elif style == "spray":
        soft = np.asarray(Image.fromarray((a * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(6))).astype(np.float32) / 255.0
        core = np.asarray(Image.fromarray((a * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.6))).astype(np.float32) / 255.0
        spk = (fine < soft * 0.35).astype(np.float32) * 0.7   # мелкие брызги вокруг
        a = np.clip(core * 0.95 + soft * 0.25 + spk * 0.5, 0, 1)
    elif style == "scratch":
        a = a * np.clip(0.55 + fine * 0.7, 0, 1) * 0.95
        a = np.asarray(Image.fromarray((a * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.5))).astype(np.float32) / 255.0
    else:  # smear
        sm = Image.fromarray((a * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(2.2))
        a = np.asarray(sm).astype(np.float32) / 255.0
        a = np.clip(a * (0.65 + nz * 0.55), 0, 1)
    # потёки вниз от нижних краёв букв
    if style in ("spray", "smear"):
        # немного неровных потёков: у основания шире, книзу тоньше, чуть виляют; часть совсем короткие
        cols = np.where(a.max(axis=0) > 0.6)[0]
        for _ in range(int(len(cols) / 220) + 1 + int(r.integers(0, 2))):
            if len(cols) == 0:
                break
            cx = float(r.choice(cols))
            ys = np.where(a[:, int(cx)] > 0.6)[0]
            if len(ys) == 0:
                continue
            yb = int(ys.max())
            ln = int(r.uniform(8, 26) if r.random() < 0.55 else r.uniform(26, 62))
            wdt = r.uniform(2.0, 3.6)
            wob = r.uniform(-0.04, 0.04)
            for yy in range(yb, min(H2 - 2, yb + ln)):
                t = (yy - yb) / ln
                cx += wob + r.normal(0, 0.12)
                half = wdt * (1.0 - t * 0.6) + (1.6 if t < 0.12 else 0.0)
                x0, x1 = int(cx - half), int(cx + half + 1)
                a[yy, max(0, x0):min(W2, x1)] = np.maximum(a[yy, max(0, x0):min(W2, x1)], 0.8 * (1.0 - t * 0.5))
            # капля на конце
            yy = min(H2 - 4, yb + ln)
            xi = int(cx)
            a[yy - 2:yy + 3, max(0, xi - 2):xi + 3] = np.maximum(a[yy - 2:yy + 3, max(0, xi - 2):xi + 3], 0.7)
    # обрезка по содержимому
    ys, xs = np.where(a > 0.02)
    if len(xs) == 0:
        return None
    pad = 14
    x0, x1 = max(0, xs.min() - pad), min(W2, xs.max() + pad)
    y0b, y1 = max(0, ys.min() - pad), min(H2, ys.max() + pad)
    a = a[y0b:y1, x0:x1]
    ink = INK[style][r.integers(0, len(INK[style]))]
    rgb = np.zeros((a.shape[0], a.shape[1], 3), np.float32)
    for i in range(3):
        rgb[..., i] = ink[i] * (0.85 + 0.3 * r.random())
    out = np.dstack([np.clip(rgb, 0, 255), np.clip(a * 255, 0, 255)]).astype(np.uint8)
    im = Image.fromarray(out)
    # не больше 1024 по ширине (VRAM и мип-карты)
    if im.width > 1024:
        im = im.resize((1024, int(im.height * 1024 / im.width)), Image.LANCZOS)
    return im


def style_for(key):
    r = rng_for(key + "#style")
    if key.startswith("graf.u"):
        return ["smear", "spray", "marker", "smear"][r.integers(0, 4)]
    if key in ("graf.g10", "graf.g11", "graf.tally2"):
        return "scratch"
    return ["marker", "marker", "spray", "scratch", "smear"][r.integers(0, 5)]


def main():
    os.makedirs(OUT, exist_ok=True)
    texts = load_texts()
    only = sys.argv[1:]
    n = 0
    for key, pair in sorted(texts.items()):
        if only and key not in only:
            continue
        st = style_for(key)
        for li, lang in enumerate(("ru", "en")):
            r = rng_for(key + lang)
            im = render(pair[li], st, r)
            if im is None:
                continue
            name = "graf_%s_%s.png" % (key.split(".", 1)[1], lang)
            im.save(os.path.join(OUT, name))
            n += 1
    # стрелка от руки
    for lang in ("ru", "en"):
        r = rng_for("arrow" + lang)
        im = render("--->", "marker", r)
        im.save(os.path.join(OUT, "graf_arrow_%s.png" % lang))
        n += 1
    print("надписей:", n)


if __name__ == "__main__":
    main()
