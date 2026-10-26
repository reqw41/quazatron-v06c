# ZX0 (компрессор), Einar Saukas — BSD-3

Исходники оптимального компрессора ZX0 v2.2 (https://github.com/einar-saukas/ZX0, каталог `src/`, без изменений):
`zx0.c compress.c optimize.c memory.c zx0.h`, лицензия — `LICENSE` (BSD 3-Clause, © 2021 Einar Saukas), README автора —
`README.upstream.md`. Взяты из порта alien8-v06c. `tools/mk_splash.py` собирает `build/zx0` сам (`cc -O2`) и зовёт
`zx0 -f -c` (классический формат v1 — его понимает распаковщик i8080 в `port/splash.asm`).
