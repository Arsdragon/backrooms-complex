"""Скачивает CC0-модели с Poly Haven (polyhaven.com) в models/<id>/ (glTF + текстуры 1k).
    python tools/models/fetch_models.py
"""
import json, os, sys, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "models")
UA = {"User-Agent": "backrooms-complex-game-build/1.0"}
RES = "1k"
IDS = [
    # Комплекс: офис и «кривые» предметы
    "plastic_monobloc_chair_01", "metal_office_desk", "SchoolChair_01", "modern_arm_chair_01", "steel_frame_shelves_01",
    "cardboard_box_01", "WetFloorSign_01", "television_02", "wheelchair_01", "fire_hydrant", "trashbag", "old_tyre",
    "utility_box_01", "covered_car", "plastic_crate_01",
    # Async
    "portable_generator", "portable_searchlight", "security_camera_01", "wooden_military_crate", "old_military_crate",
    "metal_toolbox", "industrial_pastic_container", "clipboard", "vintage_radio_transceiver", "old_gas_mask",
    "concrete_road_barrier",
    # парк
    "metal_trash_can", "street_lamp_02", "wooden_picnic_table", "modular_street_seating",
    # встроенный дом
    "Sofa_01", "ArmChair_01", "CoffeeTable_01", "dining_chair_02", "WoodenTable_01", "vintage_microwave", "electric_stove",
    "wall_clock", "hanging_picture_frame_01", "Television_01",
    # подвал и изолятор
    "lightbulb_01", "metal_stool_01",
]


def get(url):
    import time
    for attempt in range(5):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60) as r:
                return r.read()
        except Exception as e:
            print("    повтор:", type(e).__name__)
            time.sleep(2 + attempt * 2)
    raise RuntimeError("не скачать: " + url)


def main():
    os.makedirs(OUT, exist_ok=True)
    total = 0
    credits = ["3D-модели: Poly Haven (https://polyhaven.com), лицензия CC0 (общественное достояние).", ""]
    only = sys.argv[1:]
    for mid in IDS:
        if only and mid not in only:
            continue
        info = json.loads(get(f"https://api.polyhaven.com/files/{mid}"))
        g = info.get("gltf", {}).get(RES) or info.get("gltf", {}).get("2k")
        if not g:
            print("нет glTF:", mid)
            continue
        g = g["gltf"]
        d = os.path.join(OUT, mid)
        os.makedirs(d, exist_ok=True)
        main_name = os.path.basename(g["url"])
        size = 0
        data = get(g["url"])
        open(os.path.join(d, main_name), "wb").write(data)
        size += len(data)
        for rel, f in g.get("include", {}).items():
            p = os.path.join(d, rel.replace("/", os.sep))
            os.makedirs(os.path.dirname(p), exist_ok=True)
            if os.path.exists(p) and os.path.getsize(p) == f.get("size", -1):
                size += os.path.getsize(p)
                continue
            b = get(f["url"])
            open(p, "wb").write(b)
            size += len(b)
        total += size
        credits.append(f"{mid} — https://polyhaven.com/a/{mid}")
        print(f"  {mid}: {main_name} {size / 1048576:.1f} МБ")
    if not only:
        open(os.path.join(OUT, "CREDITS.txt"), "w", encoding="utf-8").write("\n".join(credits) + "\n")
    print(f"Всего: {total / 1048576:.1f} МБ")


if __name__ == "__main__":
    main()
