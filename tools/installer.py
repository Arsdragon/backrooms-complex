"""Установщик «Backrooms: Комплекс» для Windows (собирается в BackroomsComplex_Setup.exe скриптом tools/build.py).

Внутри — payload.zip с папкой BackroomsComplex (BackroomsComplex.exe). Установщик:
  * распаковывает игру в %LOCALAPPDATA%\\Programs\\BackroomsComplex (права администратора не нужны);
  * создаёт ярлыки на рабочем столе и в меню «Пуск»;
  * регистрирует игру в «Параметры → Приложения» (удаление — скриптом uninstall.ps1 рядом с игрой);
  * при обновлении ставится поверх; сохранения лежат отдельно (%APPDATA%\\Godot\\app_userdata) и не теряются.
Тихая установка: BackroomsComplex_Setup.exe /S [/D=папка] [/nolaunch] [/nodesktop]
"""
import base64
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import zipfile

APP = "Backrooms - Комплекс"
EXE = "BackroomsComplex.exe"
BASE = getattr(sys, "_MEIPASS", os.path.dirname(os.path.abspath(__file__)))
PAYLOAD = os.path.join(BASE, "payload.zip")
VERSION_FILE = os.path.join(BASE, "version.txt")
DEFAULT_DIR = os.path.join(os.environ.get("LOCALAPPDATA", os.path.expanduser("~")), "Programs", "BackroomsComplex")
UNINSTALL_KEY = r"Software\Microsoft\Windows\CurrentVersion\Uninstall\BackroomsComplex"
NO_WINDOW = 0x08000000


def version():
    try:
        with open(VERSION_FILE, encoding="utf-8") as f:
            return f.read().strip()
    except OSError:
        return ""


def run_ps(script):
    enc = base64.b64encode(script.encode("utf-16-le")).decode()
    r = subprocess.run(["powershell", "-NoProfile", "-NonInteractive", "-EncodedCommand", enc],
                       creationflags=NO_WINDOW, capture_output=True, text=True, encoding="utf-8", errors="replace")
    return r.returncode == 0


def ps_str(s):
    return "'" + s.replace("'", "''") + "'"


def make_shortcuts(target, desktop=True):
    folders = ["[Environment]::GetFolderPath('Programs')"] + (["[Environment]::GetFolderPath('Desktop')"] if desktop else [])
    lines = ["$w = New-Object -ComObject WScript.Shell"]
    for f in folders:
        lines.append(
            f"$s = $w.CreateShortcut((Join-Path ({f}) {ps_str(APP + '.lnk')})); $s.TargetPath = {ps_str(target)}; "
            f"$s.WorkingDirectory = {ps_str(os.path.dirname(target))}; $s.IconLocation = {ps_str(target + ',0')}; "
            f"$s.Description = {ps_str('Backrooms: Комплекс — found footage, Сан-Хосе, 1990')}; $s.Save()")
    return run_ps("\n".join(lines))


UNINSTALL_PS1 = r"""# Удаление «Backrooms: Комплекс» (настройки в %APPDATA%\BackroomsComplex остаются)
$ErrorActionPreference = 'SilentlyContinue'
Add-Type -AssemblyName PresentationFramework
$r = [System.Windows.MessageBox]::Show('Удалить «Backrooms: Комплекс»?', 'Удаление', 'YesNo', 'Question')
if ($r -ne 'Yes') { exit }
Stop-Process -Name 'BackroomsComplex' -Force
Start-Sleep -Milliseconds 500
$name = 'Backrooms - Комплекс.lnk'
Remove-Item (Join-Path ([Environment]::GetFolderPath('Programs')) $name) -Force
Remove-Item (Join-Path ([Environment]::GetFolderPath('Desktop')) $name) -Force
Remove-Item 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\BackroomsComplex' -Recurse -Force
$dir = $PSScriptRoot
Start-Process -WindowStyle Hidden cmd.exe -ArgumentList "/c timeout /t 2 >nul & rmdir /s /q `"$dir`""
[System.Windows.MessageBox]::Show('Игра удалена. Ваши сохранения остались на компьютере.', 'Удаление') | Out-Null
"""


def register(folder, size_kb):
    import winreg
    exe = os.path.join(folder, EXE)
    ps1 = os.path.join(folder, "uninstall.ps1")
    with winreg.CreateKey(winreg.HKEY_CURRENT_USER, UNINSTALL_KEY) as k:
        for name, val in (("DisplayName", APP), ("DisplayVersion", version()), ("Publisher", "Arsdrakon"),
                          ("DisplayIcon", exe + ",0"), ("InstallLocation", folder),
                          ("UninstallString", f'powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{ps1}"')):
            winreg.SetValueEx(k, name, 0, winreg.REG_SZ, val)
        for name, val in (("NoModify", 1), ("NoRepair", 1), ("EstimatedSize", int(size_kb))):
            winreg.SetValueEx(k, name, 0, winreg.REG_DWORD, val)


def stop_running():
    subprocess.run(["taskkill", "/IM", EXE, "/F"], creationflags=NO_WINDOW, capture_output=True)


def install(folder, desktop=True, progress=lambda p, t: None):
    folder = os.path.normpath(folder)
    if os.path.isdir(folder) and os.listdir(folder) and not os.path.isfile(os.path.join(folder, EXE)):
        raise RuntimeError("Эта папка не пуста и в ней нет игры. Выберите пустую папку или оставьте папку по умолчанию.")
    progress(5, "Закрываем запущенную игру…")
    stop_running()
    progress(10, "Распаковка…")
    tmp = tempfile.mkdtemp(prefix="backrooms_setup_")
    try:
        with zipfile.ZipFile(PAYLOAD) as z:
            names = z.infolist()
            total = sum(i.file_size for i in names) or 1
            done = 0
            for i in names:
                z.extract(i, tmp)
                done += i.file_size
                progress(10 + 70 * done / total, "Распаковка…")
        src = os.path.join(tmp, "BackroomsComplex")
        progress(82, "Копирование…")
        if os.path.isdir(folder):
            for _ in range(5):
                try:
                    shutil.rmtree(folder)
                    break
                except OSError:
                    time.sleep(0.6)
        os.makedirs(os.path.dirname(folder), exist_ok=True)
        shutil.copytree(src, folder, dirs_exist_ok=True)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    with open(os.path.join(folder, "uninstall.ps1"), "w", encoding="utf-8-sig") as f:
        f.write(UNINSTALL_PS1)
    progress(92, "Ярлыки…")
    exe = os.path.join(folder, EXE)
    make_shortcuts(exe, desktop)
    size = sum(os.path.getsize(os.path.join(d, f)) for d, _, fs in os.walk(folder) for f in fs) // 1024
    register(folder, size)
    progress(100, "Готово")
    return exe


def launch(exe):
    subprocess.Popen([exe], cwd=os.path.dirname(exe), creationflags=0x00000008)


def gui():
    import tkinter as tk
    from tkinter import filedialog, messagebox, ttk

    root = tk.Tk()
    root.title(f"Установка «{APP}»")
    root.resizable(False, False)
    try:
        root.iconbitmap(os.path.join(BASE, "icon.ico"))
    except tk.TclError:
        pass
    bg, fg, acc = "#1c1a10", "#efe6c0", "#d4bf5a"
    root.configure(bg=bg)
    style = ttk.Style(root)
    style.theme_use("clam")
    style.configure("TCheckbutton", background=bg, foreground=fg)
    style.configure("G.Horizontal.TProgressbar", troughcolor="#0e0d08", background=acc)
    pad = dict(padx=22)
    tk.Label(root, text="BACKROOMS", font=("Consolas", 34, "bold"), fg=acc, bg=bg).pack(pady=(16, 0), **pad)
    tk.Label(root, text="КОМПЛЕКС", font=("Consolas", 18, "bold"), fg="#b8a868", bg=bg).pack(**pad)
    if version():
        tk.Label(root, text=f"версия {version()}", fg="#9a9070", bg=bg).pack(**pad)
    tk.Label(root, text="Папка установки:", fg=fg, bg=bg, anchor="w").pack(fill="x", pady=(14, 2), **pad)
    row = tk.Frame(root, bg=bg)
    row.pack(fill="x", **pad)
    folder = tk.StringVar(value=DEFAULT_DIR)
    tk.Entry(row, textvariable=folder, width=52, bg="#0e0d08", fg=fg, insertbackground=fg, relief="flat").pack(side="left", ipady=5)

    def browse():
        d = filedialog.askdirectory(initialdir=os.path.dirname(folder.get()))
        if d:
            folder.set(os.path.join(os.path.normpath(d), "BackroomsComplex"))
    tk.Button(row, text="Обзор…", command=browse, bg="#4a4426", fg=fg, relief="flat", activebackground="#6a6236").pack(side="left", padx=6)
    desk = tk.BooleanVar(value=True)
    run_after = tk.BooleanVar(value=True)
    ttk.Checkbutton(root, text="Ярлык на рабочем столе", variable=desk).pack(anchor="w", pady=(12, 0), **pad)
    ttk.Checkbutton(root, text="Запустить игру после установки", variable=run_after).pack(anchor="w", **pad)
    status = tk.Label(root, text="", fg="#9a9070", bg=bg, anchor="w")
    status.pack(fill="x", pady=(12, 2), **pad)
    bar = ttk.Progressbar(root, length=460, mode="determinate", style="G.Horizontal.TProgressbar")
    bar.pack(**pad)
    btn = tk.Button(root, text="Установить", font=("Segoe UI", 12, "bold"), bg=acc, fg="#0e0d08", relief="flat",
                    activebackground="#f0dc78", padx=30, pady=6)
    btn.pack(pady=18)
    tk.Label(root, text="Права администратора не нужны. Обновление ставится поверх, настройки сохраняются.",
             fg="#9a9070", bg=bg, wraplength=470, justify="left").pack(pady=(0, 16), **pad)

    def progress(p, t):
        root.after(0, lambda: (bar.configure(value=p), status.configure(text=t)))

    def work():
        try:
            exe = install(folder.get(), desk.get(), progress)
        except Exception as e:  # noqa: BLE001
            err = str(e)
            root.after(0, lambda: (messagebox.showerror(APP, f"Не удалось установить игру:\n{err}"),
                                   btn.configure(state="normal", text="Установить")))
            return

        def done():
            status.configure(text="Готово! Ярлык «Backrooms - Комплекс» — на рабочем столе и в меню «Пуск».")
            btn.configure(state="normal", text="Закрыть", command=root.destroy)
            if run_after.get():
                launch(exe)
                root.after(1200, root.destroy)
        root.after(0, done)

    def start():
        btn.configure(state="disabled", text="Установка…")
        threading.Thread(target=work, daemon=True).start()
    btn.configure(command=start)
    root.update_idletasks()
    w, hgt = root.winfo_width(), root.winfo_height()
    root.geometry(f"+{(root.winfo_screenwidth() - w) // 2}+{(root.winfo_screenheight() - hgt) // 3}")
    root.mainloop()


def main():
    args = sys.argv[1:]
    if "/S" in args or "--silent" in args:
        d = next((a[3:] for a in args if a.startswith("/D=")), DEFAULT_DIR)
        exe = install(d, desktop="/nodesktop" not in args)
        if "/nolaunch" not in args:
            launch(exe)
        return 0
    gui()
    return 0


if __name__ == "__main__":
    sys.exit(main())
