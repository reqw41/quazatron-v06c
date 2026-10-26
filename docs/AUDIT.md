# Аудит кода оригинала для перевода на i8080

Сгенерировано `tools/audit.py` из анализа Ghidra (`tools/ghidra.sh`) и `docs/symbols.txt`. Обращения к памяти — только явные (адрес в команде); косвенные через HL/DE здесь не видны.

| раздел | мест |
|---|---|
| Порты ввода-вывода | 17 |
| Экран ZX (0x4000-0x57FF) | 7 |
| Атрибуты ZX (0x5800-0x5AFF) | 27 |
| Прерывания и IM | 9 |
| Самомодификация (запись в байты кода) | 18 |
| ld a,r / ld a,i (R нет на i8080) | 1 |
| IX / IY | 0 |
| exx / ex af,af' | 16 |
| Флаги P/V (на i8080 — только чётность) | 0 |
| daa | 2 |
| ld sp / ex (sp) | 0 |
| Block-команды (ldir и др.) | 32 |
| Сдвиги и биты CB (на i8080 нет) | 56 |

## Порты ввода-вывода (17)

- `B2FD` dbg_monitor: `IN A,(C)`
- `B35E` dbg_monitor: `IN A,(C)`
- `B366` dbg_monitor: `IN A,(C)`
- `B630` input_read: `IN A,(C)`
- `B648` input_read: `IN A,(C)`
- `B6B4` pause_check: `IN A,(C)`
- `B732` play_tune: `OUT (0xfe),A`
- `B83E` bonus_count: `OUT (0xfe),A`
- `B87E` game_reset: `OUT (0xfe),A`
- `B92C` menu_controls: `OUT (0xfe),A`
- `B97A` menu_controls: `IN A,(C)`
- `B985` menu_controls: `IN A,(C)`
- `BD75` isr: `OUT (0xfe),A`
- `BD93` isr: `OUT (0xfe),A`
- `C9D6` xfer_game: `OUT (0xfe),A`
- `CA4E` xfer_game: `OUT (0xfe),A`
- `E220` start: `IN A,(C)`

## Экран ZX (0x4000-0x57FF) (7)

- `B2D2` cls_bitmap -> `4000` (WRITE): `LD (HL),A`
- `B2D3` cls_bitmap -> `4000` (READ): `LDIR`
- `B2D3` cls_bitmap -> `4001` (READ_WRITE): `LDIR`
- `B2D3` cls_bitmap -> `4002` (WRITE): `LDIR`
- `C069` scr_copy -> `4000` (WRITE): `LDIR`
- `C069` scr_copy -> `4001` (WRITE): `LDIR`
- `C8B0` xfer_game -> `4867` (WRITE): `LD (DE),A`

## Атрибуты ZX (0x5800-0x5AFF) (27)

- `B2EA` cls_attr -> `5800` (WRITE): `LD (HL),A`
- `B2F1` cls_attr -> `5800` (READ): `LDIR`
- `B2F1` cls_attr -> `5801` (READ_WRITE): `LDIR`
- `B2F1` cls_attr -> `5802` (WRITE): `LDIR`
- `B343` dbg_monitor -> `5800` (WRITE): `LD (HL),0xf`
- `B343` dbg_monitor -> `5801` (WRITE): `LD (HL),0xf`
- `B359` dbg_monitor -> `5802` (DATA): `LD (HL),0x30`
- `B359` dbg_monitor -> `5801` (DATA): `LD (HL),0x30`
- `B359` dbg_monitor -> `5800` (DATA): `LD (HL),0x30`
- `B96F` menu_controls -> `58A3` (WRITE): `LD (HL),C`
- `B96F` menu_controls -> `58E3` (WRITE): `LD (HL),C`
- `CE22` xf_update -> `58CF` (WRITE): `LD (HL),A`
- `CE22` xf_update -> `58EF` (WRITE): `LD (HL),A`
- `CE24` xf_update -> `58D0` (WRITE): `LD (HL),A`
- `CE24` xf_update -> `58F0` (WRITE): `LD (HL),A`
- `CE28` xf_update -> `58CF` (READ): `LD A,(HL)`
- `CE28` xf_update -> `58EF` (READ): `LD A,(HL)`
- `D073` console -> `5926` (WRITE): `LD (HL),A`
- `D073` console -> `5946` (WRITE): `LD (HL),A`
- `D075` console -> `5927` (WRITE): `LD (HL),A`
- `D075` console -> `5947` (WRITE): `LD (HL),A`
- `D4AE` lift_list -> `586C` (WRITE): `LD (DE),A`
- `D4AE` lift_list -> `586D` (WRITE): `LD (DE),A`
- `D4D7` lift_list -> `58C6` (WRITE): `LD (HL),A`
- `D4D7` lift_list -> `58E6` (WRITE): `LD (HL),A`
- `DE55` xfer_off -> `5AAE` (WRITE): `LD (HL),A`
- `DE6A` panel_ind -> `5AB1` (WRITE): `LD (HL),A`

## Прерывания и IM (9)

- `B370` dbg_monitor: `IM 1`
- `B372` dbg_monitor: `EI`
- `B6E9` play_tune: `DI`
- `B73E` play_tune: `EI`
- `BD2D` isr: `DI`
- `BDFB` isr: `EI`
- `DE7C` start: `DI`
- `DE81` start: `IM 2`
- `DE90` start: `EI`

## Самомодификация (запись в байты кода) (18)

- `B0A0` blit_tile -> `B154` (WRITE): `LD (0xb154),A` — в коде blit_tile
- `B0A3` blit_tile -> `B192` (WRITE): `LD (0xb192),A` — в коде blit_tile
- `B0A6` blit_tile -> `B1B6` (WRITE): `LD (0xb1b6),A` — в коде blit_tile
- `B0C9` blit_tile -> `B15F` (WRITE): `LD (0xb15f),A` — в коде blit_tile
- `B0CC` blit_tile -> `B164` (WRITE): `LD (0xb164),A` — в коде blit_tile
- `B0CF` blit_tile -> `B1DA` (WRITE): `LD (0xb1da),A` — в коде blit_tile
- `B0D2` blit_tile -> `B1C2` (WRITE): `LD (0xb1c2),A` — в коде blit_tile
- `B0D5` blit_tile -> `B19D` (WRITE): `LD (0xb19d),A` — в коде blit_tile
- `B0D9` blit_tile -> `B15E` (WRITE): `LD (0xb15e),A` — в коде blit_tile
- `B0DC` blit_tile -> `B163` (WRITE): `LD (0xb163),A` — в коде blit_tile
- `B0DF` blit_tile -> `B19C` (WRITE): `LD (0xb19c),A` — в коде blit_tile
- `B0E2` blit_tile -> `B1C1` (WRITE): `LD (0xb1c1),A` — в коде blit_tile
- `B0E5` blit_tile -> `B1D9` (WRITE): `LD (0xb1d9),A` — в коде blit_tile
- `B493` spr_flush -> `B4D3` (WRITE): `LD (0xb4d3),A` — в коде spr_flush
- `B49C` spr_flush -> `B4C1` (WRITE): `LD (0xb4c1),A` — в коде spr_flush
- `DE73` start -> `E6E6` (WRITE): `LD (HL),0xc3` — в коде pop_pair
- `DE79` start -> `E6E7` (WRITE): `LD (HL),E` — в коде pop_pair
- `DE7B` start -> `E6E8` (WRITE): `LD (HL),D` — в коде pop_pair

## ld a,r / ld a,i (R нет на i8080) (1)

- `B5B1` rnd: `LD A,R`

## IX / IY (0)


## exx / ex af,af' (16)

- `B14D` blit_tile: `EX AF,AF_`
- `B16A` blit_tile: `EX AF,AF_`
- `B18B` blit_tile: `EX AF,AF_`
- `B1A4` blit_tile: `EX AF,AF_`
- `B1AF` blit_tile: `EX AF,AF_`
- `B1C8` blit_tile: `EX AF,AF_`
- `BD2E` isr: `EXX`
- `BD2F` isr: `EX AF,AF_`
- `BDF9` isr: `EX AF,AF_`
- `BDFA` isr: `EXX`
- `C062` scr_copy: `EX AF,AF_`
- `C078` scr_copy: `EX AF,AF_`
- `C085` scr_copy: `EX AF,AF_`
- `C09B` scr_copy: `EX AF,AF_`
- `C0A8` scr_copy: `EX AF,AF_`
- `C0BE` scr_copy: `EX AF,AF_`

## Флаги P/V (на i8080 — только чётность) (0)


## daa (2)

- `B790` score_tick: `DAA` (после `ADC A,0x0`)
- `CE81` xf_timer: `DAA` (после `SUB 0x1`)

## ld sp / ex (sp) (0)


## Block-команды (ldir и др.) (32)

- `B2D3` cls_bitmap: `LDIR`
- `B2F1` cls_attr: `LDIR`
- `BD52` isr: `LDIR`
- `C057` strip_fill: `LDIR`
- `C069` scr_copy: `LDIR`
- `C08C` scr_copy: `LDIR`
- `C0AF` scr_copy: `LDIR`
- `C29F` drawlist_add: `LDDR`
- `C2A9` drawlist_add: `LDIR`
- `D203` console: `LDIR`
- `D233` console: `LDIR`
- `D58A` shot_spawn: `LDIR`
- `D5EC` objs_update: `LDIR`
- `D607` objs_update: `LDIR`
- `D9C5` objs_update: `LDIR`
- `D9EA` objs_update: `LDIR`
- `D9F5` objs_update: `LDIR`
- `DBE1` objs_update: `LDIR`
- `DC3D` objs_update: `LDIR`
- `DCAE` objs_update: `LDIR`
- `DDAB` font_copy: `LDIR`
- `DE8E` start: `LDIR`
- `E01C` start: `LDIR`
- `E117` start: `LDDR`
- `E126` start: `LDIR`
- `E135` start: `LDIR`
- `E140` start: `LDIR`
- `E14F` start: `LDDR`
- `E15A` start: `LDDR`
- `E1E7` start: `LDIR`
- `E66A` sprwins_flush: `LDIR`
- `E685` plr_droid_init: `LDIR`

## Сдвиги и биты CB (на i8080 нет) (56)

- `B125` blit_tile: `RL D`
- `B128` blit_tile: `RL D`
- `B3C1` dbg_monitor: `SRA A`
- `B4F9` gfx_lookup: `RL D`
- `B57F` gfx_lookup: `RR C`
- `B734` play_tune: `SRL A`
- `BEF3` deck_draw: `RL E`
- `BEF5` deck_draw: `RL E`
- `BEF8` deck_draw: `RR E`
- `BEFB` deck_draw: `RR E`
- `BEFE` deck_draw: `RR E`
- `BF01` deck_draw: `RR E`
- `C152` dk_attr: `RR H`
- `C154` dk_attr: `RR A`
- `C156` dk_attr: `RR H`
- `C158` dk_attr: `RR A`
- `C15A` dk_attr: `RR H`
- `C15C` dk_attr: `RR A`
- `C4C9` obj_move: `SRA A`
- `C4DA` obj_move: `SRA A`
- `C4E0` obj_move: `SRA A`
- `C4EE` obj_move: `SRA A`
- `C4FF` obj_move: `SRA A`
- `C508` obj_move: `SRA A`
- `C516` obj_move: `SRA C`
- `C518` obj_move: `SRA B`
- `C528` obj_move: `SRA C`
- `C52A` obj_move: `SRA B`
- `C56A` obj_move: `SLA B`
- `C56C` obj_move: `SLA C`
- `C676` obj_move: `SRA H`
- `C678` obj_move: `RR L`
- `C6A0` obj_move: `SRL A`
- `C6A6` obj_move: `SRL A`
- `CA21` xfer_game: `RRC A`
- `CA26` xfer_game: `RRC A`
- `CA2E` xfer_game: `RLC A`
- `CA33` xfer_game: `RLC A`
- `D145` console: `RL E`
- `D147` console: `RL E`
- `D14A` console: `RR E`
- `D14D` console: `RR E`
- `D150` console: `RR E`
- `D153` console: `RR E`
- `D7AC` objs_update: `SRA C`
- `D7AE` objs_update: `SRA C`
- `D7BF` objs_update: `SRA A`
- `D7FA` objs_update: `SRA A`
- `D8AD` objs_update: `SRA B`
- `DC80` objs_update: `RR H`
- `DC83` objs_update: `RR H`
- `DC86` objs_update: `RR H`
- `DF5D` start: `SRA A`
- `DFB2` start: `SRA A`
- `DFB4` start: `SRA A`
- `E394` start: `SRA A`
