#!/bin/sh
# Запуск сборки i8080 в Emu80 (платформа vector, порт MCP 19787).
#   tools/emu80_run.sh [ru]   — build/port8080/quaz_8080[_ru].r0m
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP=~/projects/emu80v4/Emu80qt-mcp.app/Contents/MacOS
TMP="${TMPDIR:-/tmp}/qz_emu80"; mkdir -p "$TMP"
pkill -f "Emu80qt-mcp.*quaz_8080" 2>/dev/null || true
IMG=quaz_8080${1:+_$1}.r0m
cp "$ROOT/build/port8080/$IMG" "$TMP/$IMG"
cd "$APP"
QT_PLUGIN_PATH=/opt/homebrew/share/qt/plugins EMU80_MCP_PORT=19787 nohup ./Emu80qt-mcp --platform vector --run "$TMP/$IMG" >"$TMP/emu80.log" 2>&1 &
echo "Emu80 запущен: vector $IMG (MCP порт 19787)"
