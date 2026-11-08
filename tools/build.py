"""Полная сборка для Windows: текстуры → звук/голоса/модели (если нет) → импорт → экспорт Godot → установщик.

    python tools/build.py            → release/BackroomsComplex_Setup.exe и release/BackroomsComplex (папка без установки)
    python tools/build.py --fast     → без перегенерации графики и звука
Нужно: Godot 4.7.2 и шаблоны экспорта (%USERPROFILE%\\tools\\godot), Python + Pillow + numpy + scipy + PyInstaller, ffmpeg.
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GODOT = os.path.expandvars(r"%USERPROFILE%\tools\godot\Godot_v4.7.2-stable_win64_console.exe")
OUT = os.path.join(ROOT, "release")
SEP = ";"


def run(cmd, **kw):
    print(">", " ".join(cmd[:4]), "…")
    r = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace", **kw)
    if r.returncode:
        print(r.stdout[-3000:], r.stderr[-3000:])
        sys.exit("Ошибка: " + cmd[0])
    return r.stdout + r.stderr


def version():
    text = open(os.path.join(ROOT, "project.godot"), encoding="utf-8").read()
    return re.search(r'config/version="([^"]+)"', text).group(1)


def main():
    fast = "--fast" in sys.argv
    env = dict(os.environ, PYTHONIOENCODING="utf-8")
    if not fast:
        run([sys.executable, "tools/tex/make_textures.py"], env=env)
        if not os.path.exists(os.path.join(ROOT, "audio", "hum_fluor.ogg")):
            run([sys.executable, "tools/audio/make_audio.py"], env=env)
        if not os.path.exists(os.path.join(ROOT, "voice", "int_i01_ru.ogg")):
            run([sys.executable, "tools/voice/make_voice.py"], env=env)
        if not os.path.exists(os.path.join(ROOT, "models", "CREDITS.txt")):
            run([sys.executable, "tools/models/fetch_models.py"], env=env)
    run([GODOT, "--headless", "--path", ROOT, "--import"])
    run([sys.executable, "tools/fix_imports.py"], env=env)
    run([GODOT, "--headless", "--path", ROOT, "--import"])
    build = os.path.join(ROOT, "build")
    shutil.rmtree(build, ignore_errors=True)
    os.makedirs(build)
    out = run([GODOT, "--headless", "--path", ROOT, "--export-release", "Windows Desktop", os.path.join(build, "BackroomsComplex.exe")])
    exe = os.path.join(build, "BackroomsComplex.exe")
    if not os.path.exists(exe):
        print(out[-3000:])
        sys.exit("Экспорт не удался")
    print(f"Игра: {os.path.getsize(exe) / 1048576:.0f} МБ")
    # папка без установки
    portable = os.path.join(OUT, "BackroomsComplex")
    shutil.rmtree(portable, ignore_errors=True)
    os.makedirs(portable)
    for f in os.listdir(build):
        shutil.copy(os.path.join(build, f), portable)
    # установщик
    work = tempfile.mkdtemp(prefix="backrooms_build_")
    try:
        payload = os.path.join(work, "payload.zip")
        with zipfile.ZipFile(payload, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as z:
            for f in os.listdir(build):
                z.write(os.path.join(build, f), os.path.join("BackroomsComplex", f))
        with open(os.path.join(work, "version.txt"), "w", encoding="utf-8") as f:
            f.write(version())
        icon = os.path.join(ROOT, "icon.ico")
        cmd = [sys.executable, "-m", "PyInstaller", "--noconfirm", "--onefile", "--windowed", "--icon", icon,
               "--name", "BackroomsComplex_Setup", "--distpath", os.path.join(work, "dist"), "--workpath", os.path.join(work, "b"),
               "--specpath", work, "--add-data", f"{payload}{SEP}.", "--add-data", f"{os.path.join(work, 'version.txt')}{SEP}.",
               "--add-data", f"{icon}{SEP}.", os.path.join(ROOT, "tools", "installer.py")]
        run(cmd)
        os.makedirs(OUT, exist_ok=True)
        dst = os.path.join(OUT, "BackroomsComplex_Setup.exe")
        shutil.copy(os.path.join(work, "dist", "BackroomsComplex_Setup.exe"), dst)
    finally:
        shutil.rmtree(work, ignore_errors=True)
    print(f"Готово: {dst} ({os.path.getsize(dst) / 1048576:.0f} МБ), версия {version()}")


if __name__ == "__main__":
    main()
