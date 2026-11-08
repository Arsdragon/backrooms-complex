#!/bin/sh
# Отладка: tools/dev.sh import | shot <файл.png> [wait] [аргументы игры…] | run [аргументы]
cd "$(dirname "$0")/.."
GD="$USERPROFILE/tools/godot/Godot_v4.7.2-stable_win64_console.exe"
case "$1" in
  import) "$GD" --headless --path . --import 2>&1 | grep -E "ERROR|SCRIPT|Parse|error" | head -40 ;;
  shot) shift; out="$1"; w="${2:-3}"; shift 2 2>/dev/null
        timeout 120 "$GD" --path . --windowed --resolution 1280x720 -- --shot="$out" --wait="$w" "$@" 2>&1 | grep -v "MSAA" | grep -E "ERROR|SCRIPT|WARN|at:|Parse|SHOT|Комплекс" | head -40 ;;
  run) shift; "$GD" --path . "$@" ;;
esac
