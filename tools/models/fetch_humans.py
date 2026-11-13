"""Люди: Microsoft Rocketbox (MIT, https://github.com/microsoft/Microsoft-Rocketbox).
Скачивает FBX без лицевой анимации + цвет и прозрачность, ужимает текстуры до 1024 px → humans/<id>/.
    python tools/models/fetch_humans.py [--normals] [id …]
--normals — ещё и карты нормалей <id>_<часть>_normal.tga (~3 МБ на аватар): human.gd подхватит их сам
(prop-шейдер: nmap, соглашение DirectX — как у Rocketbox).
"""
import json, os, sys, time, urllib.request, concurrent.futures as cf
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "humans")
UA = {"User-Agent": "backrooms-complex-game-build/1.0"}
RAW = "https://raw.githubusercontent.com/microsoft/Microsoft-Rocketbox/master/"
# кто в игре -> аватар
CAST = {
    "jogger": "Professions/Sports_Male_04",
    "mother": "Adults/Female_Adult_02",
    "kid": "Children/Male_Child_01",
    "oldman": "Adults/Male_Adult_03",
    "couple": "Adults/Male_Adult_06",
    "couple_b": "Adults/Female_Adult_10",
    "suit": "Professions/Business_Male_02",
    "vendor": "Professions/Chef_Female_01",
    "teen": "Adults/Male_Adult_09",
    "worker": "Professions/Business_Male_06",
    "explorer": "Professions/Fire_Male_01",
    "player": "Adults/Male_Adult_05",
    "civ_a": "Adults/Female_Adult_04",
    "civ_b": "Adults/Male_Adult_01",
    "civ_c": "Adults/Female_Adult_12",
    "civ_d": "Adults/Male_Adult_01",
    # другие пропавшие (разнообразие копий)
    "civ_e": "Professions/Business_Female_01",
    "civ_f": "Adults/Female_Adult_01",
    "civ_g": "Adults/Female_Adult_06",
    "civ_h": "Adults/Male_Adult_13",
    "civ_i": "Adults/Male_Adult_16",
    "civ_j": "Professions/Medical_Male_01",
    "civ_k": "Professions/Police_Male_01",
    "civ_l": "Children/Female_Child_01",
    "civ_m": "Children/Male_Child_02",
    "civ_n": "Professions/Gardener_Male_01",
    "civ_o": "Professions/Security_Male_01",
    "civ_p": "Adults/Male_Adult_14",
}


def get(url):
    for a in range(6):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=120) as r:
                return r.read()
        except Exception as e:
            print("    повтор", a + 1, type(e).__name__, flush=True)
            time.sleep(2 + a * 3)
    raise RuntimeError("не скачать " + url)


def tree():
    return json.loads(get("https://api.github.com/repos/microsoft/Microsoft-Rocketbox/git/trees/master?recursive=1"))["tree"]


def fetch(av, files):
    name = av.split("/")[-1]
    d = os.path.join(OUT, name)
    os.makedirs(os.path.join(d, "Export"), exist_ok=True)
    os.makedirs(os.path.join(d, "Textures"), exist_ok=True)
    total = 0
    for f in files:
        rel = f[len("Assets/Avatars/" + av) + 1:]
        dst = os.path.join(d, rel.replace("/", os.sep))
        if os.path.exists(dst):
            continue
        b = get(RAW + f)
        total += len(b)
        if dst.lower().endswith(".tga"):
            tmp = dst + ".part"
            open(tmp, "wb").write(b)
            im = Image.open(tmp)
            im.load()
            if im.width > 1024:
                im = im.resize((1024, 1024), Image.LANCZOS)
            im.save(dst)
            os.remove(tmp)
        else:
            open(dst, "wb").write(b)
    return name, total


def main():
    args = sys.argv[1:]
    normals = "--normals" in args
    only = [a for a in args if not a.startswith("--")]
    t = tree()
    jobs = []
    for role, av in CAST.items():
        if only and role not in only:
            continue
        pre = "Assets/Avatars/" + av + "/"
        files = [x["path"] for x in t if x["path"].startswith(pre) and x["type"] == "blob" and (
            x["path"].endswith(av.split("/")[-1] + ".fbx") or (("_color" in x["path"].rsplit("/", 1)[-1]
            or (normals and "_normal" in x["path"].rsplit("/", 1)[-1])) and x["path"].endswith(".tga")))]
        jobs.append((av, files))
    done = 0
    with cf.ThreadPoolExecutor(3) as ex:
        for name, total in ex.map(lambda j: fetch(*j), jobs):
            done += total
            print(f"  {name}: {total / 1048576:.0f} МБ скачано", flush=True)
    json.dump({k: v.split("/")[-1] for k, v in CAST.items()}, open(os.path.join(OUT, "cast.json"), "w"), indent=1)
    open(os.path.join(OUT, "CREDITS.txt"), "w", encoding="utf-8").write(
        "Люди: Microsoft Rocketbox Avatar Library (https://github.com/microsoft/Microsoft-Rocketbox), лицензия MIT.\n"
        "Copyright (c) Microsoft Corporation. Текстуры уменьшены до 1024 px.\n")
    print(f"Всего: {done / 1048576:.0f} МБ")


if __name__ == "__main__":
    main()
