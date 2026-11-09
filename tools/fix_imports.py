"""Текстуры 3D: мип-карты и VRAM-сжатие. Запускать после первого импорта, затем импортировать снова."""
import glob, os, re, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
changed = 0
for f in glob.glob(os.path.join(ROOT, "tex", "*.png.import")):
    s = open(f, encoding="utf-8").read()
    o = s
    s = re.sub(r"compress/mode=\d", "compress/mode=2", s)
    s = re.sub(r"mipmaps/generate=\w+", "mipmaps/generate=true", s)
    s = re.sub(r"detect_3d/compress_to=\d", "detect_3d/compress_to=0", s)
    if s != o:
        open(f, "w", encoding="utf-8").write(s)
        changed += 1
print("patched", changed)

# зацикленные звуки
sys.path.insert(0, os.path.join(ROOT, "tools", "audio"))
LOOPS = {"hum_fluor", "room_tone", "null_hum", "park_ambience", "wind_trees", "water_loop", "jingle", "generator",
         "threshold_hum", "tv_static", "fridge_hum", "radio_static", "tape_whir", "sea_waves", "wind_open", "wind_fall",
         "upstairs_tv", "crickets", "death_drone", "birds_wrong", "jingle_wrong", "music_box", "engine_tick",
         "vending_hum", "speaker_hiss", "tv_news", "tv_jingle", "tv_home", "clock_tick", "vent_air", "store_muzak", "water_amb",
         "heartbeat", "under_rumble", "space_tone"}
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
