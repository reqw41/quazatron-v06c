#!/bin/sh
# Готовые образы i8080 -> rom/: quazatron.r0m (русский, заставка), quazatron-nosplash.r0m, quazatron-en.r0m, quazatron-en-nosplash.r0m.
# Нужны orig/zx/quazatron_ram.bin (tools/prepare_orig.sh) и ПЗУ ZX 48K (ZXROM=файл или zx-stand/spectrum.zip).
set -e
cd "$(dirname "$0")/.."
[ -f orig/zx/quazatron_ram.bin ] || tools/prepare_orig.sh
mkdir -p rom
port/build.sh --i8080 --ru --splash
cp build/port8080/quaz_8080_ru_splash.r0m rom/quazatron.r0m
cp build/port8080/quaz_8080_ru.r0m rom/quazatron-nosplash.r0m
port/build.sh --i8080 --splash
cp build/port8080/quaz_8080_splash.r0m rom/quazatron-en.r0m
cp build/port8080/quaz_8080.r0m rom/quazatron-en-nosplash.r0m
ls -l rom/*.r0m
