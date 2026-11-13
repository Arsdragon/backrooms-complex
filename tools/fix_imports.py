"""Настройки импорта: текстуры, звуки, модели. Запускать после первого импорта, затем импортировать снова.
Скрипт идемпотентен: файл переписывается, только если что-то поменялось.

Текстуры tex/*.png:
- цветные — VRAM BC7 (compress/mode=2, high_quality=true): у BC1 блоки 4×4 крупнее мелкого рисунка обоев;
- карты нормалей *_n — compress/normal_map=1 (RGTC/BC5, z восстанавливается в шейдере);
- данные (noise, *_grime, *_stains, *_damp) — без потерь (compress/mode=0): это маски, сжатие их портит;
- fixture — fix_alpha_border=false (альфа = маска свечения, рамку не трогать);
- везде мип-карты.
"""
import glob, os, re, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

DATA = {"noise"}                          # служебные маски (плюс всё на _grime, _stains, _damp)
DATA_SUFFIX = ("_grime", "_stains", "_damp")
NOT_NORMAL = {"water_n"}                  # «_n», но не карта нормалей (шум воды в концовке)
NO_ALPHA_FIX = {"fixture"}


def setp(s, key, val):
    """Задать параметр импорта (добавить в [params], если его нет)"""
    pat = r"(?m)^" + re.escape(key) + r"=.*$"
    if re.search(pat, s):
        return re.sub(pat, key + "=" + val, s)
    return s.rstrip("\n") + "\n" + key + "=" + val + "\n"


changed = 0
for f in glob.glob(os.path.join(ROOT, "tex", "*.png.import")):
    name = os.path.basename(f)[:-len(".png.import")]
    s = open(f, encoding="utf-8").read()
    o = s
    data = name in DATA or name.endswith(DATA_SUFFIX)
    normal = name.endswith("_n") and name not in NOT_NORMAL
    s = setp(s, "compress/mode", "0" if data else "2")
    s = setp(s, "compress/high_quality", "false" if (data or normal) else "true")
    s = setp(s, "compress/normal_map", "1" if normal else "0")
    s = setp(s, "mipmaps/generate", "true")
    s = setp(s, "detect_3d/compress_to", "0")
    if name in NO_ALPHA_FIX:
        s = setp(s, "process/fix_alpha_border", "false")
    if s != o:
        open(f, "w", encoding="utf-8", newline="\n").write(s)
        changed += 1
print("patched", changed)

# зацикленные звуки
sys.path.insert(0, os.path.join(ROOT, "tools", "audio"))
LOOPS = {"hum_fluor", "room_tone", "null_hum", "park_ambience", "wind_trees", "water_loop", "jingle", "generator",
         "threshold_hum", "tv_static", "fridge_hum", "radio_static", "tape_whir", "sea_waves", "wind_open", "wind_fall",
         "upstairs_tv", "crickets", "death_drone", "birds_wrong", "jingle_wrong", "music_box", "engine_tick",
         "vending_hum", "speaker_hiss", "tv_news", "tv_jingle", "tv_home", "clock_tick", "vent_air", "store_muzak", "water_amb",
         "heartbeat", "under_rumble", "space_tone", "washer", "fan_big", "rain_room"}
na = 0
for f in glob.glob(os.path.join(ROOT, "audio", "*.ogg.import")):
    name = os.path.basename(f)[:-len(".ogg.import")]
    s = open(f, encoding="utf-8").read()
    o = s
    want = "true" if name in LOOPS else "false"
    s = re.sub(r"\nloop=\w+", "\nloop=" + want, s)
    if s != o:
        open(f, "w", encoding="utf-8").write(s)
        na += 1
print("audio patched", na)

# текстуры моделей: мип-карты, VRAM-сжатие, карты нормалей
nm = 0
for f in [x for ext in ("jpg", "png", "tga") for d in ("models", "humans") for x in glob.glob(os.path.join(ROOT, d, "**", "*." + ext + ".import"), recursive=True)]:
    s = open(f, encoding="utf-8").read()
    o = s
    s = re.sub(r"compress/mode=\d", "compress/mode=2", s)
    s = re.sub(r"mipmaps/generate=\w+", "mipmaps/generate=true", s)
    if "_nor" in os.path.basename(f):
        s = re.sub(r"compress/normal_map=\d", "compress/normal_map=1", s)
    if s != o:
        open(f, "w", encoding="utf-8").write(s)
        nm += 1
print("model textures patched", nm)
