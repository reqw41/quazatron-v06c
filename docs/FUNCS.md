# Оглавление кода (сгенерировано `tools/funcs.py`)

Участок — от имени кода до следующего имени. Покрытие — доля команд (по Ghidra), исполненных в трассах MAME.

Всего участков 252, команд 6602, исполнено 6527 (98.9%).

| адрес | имя | байт | покрытие | вызывают | вызывает | описание |
|---|---|---|---|---|---|---|
| B070 | `scr_down8` | 13 | 100% | print_cont, salv_mark, xf_down, xf_draw, xf_rowaddr |  | адрес экрана ZX на знакоряд ниже |
| B07D | `blit_tile` | 2 | 100% | cs_menu, dk_tile, spr_drawlist |  | вывод плитки/спрайта столбцами в буфер-полосу (режимы стирание/запись/или) |
| B07F | `bt_column` | 74 | 100% | bt_shift | bt_patch | blit_tile: столбец — dx, dy, режим/высота; вне полосы — пропуск (B178) |
| B0C9 | `bt_patch` | 63 | 100% | bt_column | bt_clip | самомодификация по режиму: B15F/B164/B19D/B1C2/B1DA — 0xA6 and (hl) (стирание, с cpl 0x2F в B15E/B163/B19C/B1C1/B1D9), 0x00 nop (запись), 0xB6 or (hl); B154/B192/B1B6 — смещение jr = x & 7 |
| B108 | `bt_clip` | 69 | 100% | bt_patch | bt_aligned | обрезка столбца по высоте полосы (v_blt_skip — пропустить байт) |
| B14D | `bt_shift` | 62 | 100% |  | bt_column | цикл столбца: байт в HL, `jr` со смещением x & 7 (B154, самомодификация) пропускает часть 7 команд add hl,hl — сдвиг на нужное число бит; затем 2 байта в полосу (cpl/nop B15E, and/or/nop B15F) |
| B18B | `bt_shift4` | 36 | 100% |  |  | то же для байтового столбца 3 (край полосы 4 байта) |
| B1AF | `bt_shift0` | 35 | 100% |  |  | то же для байтового столбца 0 |
| B1D2 | `bt_aligned` | 20 | 100% | bt_clip |  | x & 7 = 0: байт как есть |
| B1E6 | `str_find2` | 7 | 100% | lift_list, print_list, xf_board | list_nth | A (& 0x7F)-я строка из p_strtab2 |
| B1ED | `msg_find` | 3 | 100% | city_clear, city_start, console, droid_desc, game_over, print_comp, print_list |  | A-я строка из t_msgs |
| B1F0 | `list_nth` | 11 | 100% | print_comp, str_find2 |  | HL = A-я запись списка с префиксом длины |
| B1FB | `print_at` | 4 | 100% | bonus_count, city_clear, city_start, console, cs_circuit, dbg_monitor, droid_desc, game_over, hi_letter, lift_list, panel_cls, print_list, score_show, title_loop, xf_board, xf_draw, xf_glyph, xf_timer |  | печать строки HL (длина, коды; 0xFF — перевод строки) в экран с адреса DE |
| B1FF | `print_cont` | 102 | 100% | print_comp | scr_down8 | то же без запоминания начала строки |
| B265 | `print_comp` | 50 | 100% | city_start, cs_circuit, plr_die, print_list, xf_finish, xf_won, xfer_game | list_nth, msg_find, print_cont | печать составной строки (список номеров сообщений) |
| B297 | `print_list` | 50 | 100% | cs_parts, game_reset, hi_enter, menu_controls, panel_frame, panel_msg, salv_mark, scr_droidinfo, scr_gameover, scr_salvage, title_loop, xf_restart | msg_find, print_at, print_comp, str_find2 | список надписей: [номер, адрес экрана] ..., 0xFF — конец |
| B2C9 | `cls_bitmap` | 30 | 100% | cs_menu, cs_parts, lift_screen, menu_controls, scr_droidinfo, scr_gameover, xf_restart |  | залить экран ZX (без нижней части) значением A |
| B2E7 | `cls_attr` | 13 | 100% | bonus_count, cs_menu, lift_screen, menu_controls, plr_cooldown, plr_fire, scr_gameover, xf_restart |  | залить атрибуты строк 0..18 значением A |
| B2F4 | `dbg_monitor` | 257 | 94% | input_read | hex_nibbles, print_at | отладочный монитор авторов (каждый опрос ввода): при v_mon_on — адрес и 8 байт памяти в строке 0 экрана, клавиши 5–8 — курсор и правка цифр, «заморозка» байта (v_mon_hold = 0x20); сочетание клавиш — im 1, ei, jp F70F (внешний отладчик, в образе его нет). Выключенная ветка: CAPS SHIFT (F7FE) — ret, включение B304 недостижимо |
| B3F5 | `hex_nibbles` | 47 | 100% | dbg_monitor |  | байт -> две шестнадцатеричные цифры |
| B424 | `spr_flush` | 205 | 99% | cs_menu, cs_plan, sprwins_flush |  | окно спрайта (4 байта, шаг 8) -> экран ZX с отсечением |
| B4F1 | `gfx_lookup` | 178 | 100% | city_start, cs_menu, deck_reset, dk_tile |  | номер плитки A (с 1) -> HL = кадры (по v_obj_anim); плитка с заголовком б5 — при первом обращении строятся зеркальные кадры в кэш, указатели — в запасные ячейки таблицы |
| B5A3 | `rnd` | 25 | 100% | ai_think, bonus_count, city_start, isr_noise, om_wander, plr_die, plr_settle, pop_gen, pop_pair, salv_roll, xf_after_plr, xf_ai_pick, xf_gen_cell |  | случайное: R xor байт таблицы (указатель B5BA, по кругу 1 КБ). На i8080 R нет! |
| B5BC | `attr_rects` | 50 | 100% | console, cs_parts, game_reset, hi_enter, menu_controls, panel_frame, panel_msg, salv_loop, scr_droidinfo, scr_gameover, scr_salvage, title_loop, xf_board, xf_counts, xf_restart, xu_count |  | список прямоугольников атрибутов: [ширина, высота, адрес, цвет] ..., 0xFF |
| B5EE | `panel_msg` | 40 | 100% | energy_check, panel_mode, pause_check, plr_die, xf_board, xf_result, xf_side_done, xfer_arm | attr_rects, print_list | сообщение A в окне состояния панели |
| B616 | `panel_mode` | 9 | 100% | energy_check, panel_key, pause_check, xfer_off | panel_msg | сообщение режима (AF0D + 7) |
| B61F | `input_read` | 108 | 100% | hi_letter, input_wait_up, menu_controls, pause_check, play_tune, xf_pickside, xf_turn | dbg_monitor | опрос управления по v_ctrlmode -> v_in_* |
| B68B | `input_wait_up` | 31 | 100% | console, cs_circuit, cs_droids_loop, cs_menu, hi_letter, lift, lift_wait, menu_controls, pause_check, xf_lost | input_read | ждать, пока всё отпущено |
| B6AA | `pause_check` | 63 | 100% | cs_droids_loop, cs_menu, cs_parts_loop, lift_loop, objs_frame, salv_loop | input_read, input_wait_up, panel_mode, panel_msg | пауза по любой клавише |
| B6E9 | `play_tune` | 148 | 100% | city_start, game_over, hi_letter, plr_die, salv_loop, salv_mark, title_loop, xf_result | input_read | мелодия A через бипер (прерывания запрещены), огонь прерывает |
| B77D | `score_tick` | 24 | 100% | bonus_count, city_clear, game_over, ou_deck_dec, spr_pace |  | начислить единицу из v_score_add, вывести счёт |
| B795 | `score_show` | 35 | 100% | game_reset | print_at | вывести счёт |
| B7B8 | `panel_frame` | 103 | 100% | bonus_count, cs_parts, lift_screen, menu_controls, scr_droidinfo, scr_gameover | attr_rects, print_list | рамка панели |
| B81F | `bonus_count` | 83 | 100% | console, game_over | cls_attr, panel_frame, print_at, rnd, score_tick | подсчёт бонуса с шумом |
| B872 | `panel_cls` | 10 | 100% | game_reset, plr_die, salv_exit | print_at | вывод номера класса (строка B062: длина + v_panel_cls) в панель |
| B87C | `game_reset` | 127 | 100% | menu_controls, title_loop | attr_rects, panel_cls, print_list, score_show | сброс счёта и панели перед игрой |
| B8FB | `scr_gameover` | 43 | 100% | city_clear, city_start, console, game_over, hi_enter, plr_die, title_loop, xfer_game | attr_rects, cls_attr, cls_bitmap, panel_frame, print_list | экран конца игры |
| B926 | `menu_controls` | 170 | 98% | start | attr_rects, cls_attr, cls_bitmap, game_reset, input_read, input_wait_up, panel_frame, print_list | меню выбора управления |
| B9D0 | `droid_desc` | 132 | 100% | console, scr_droidinfo, xfer_game | droid_desc_lu, msg_find, print_at | описание дроида (класс, назначение) текстом |
| BA54 | `droid_desc_lu` | 48 | 100% | droid_desc |  | поиск в таблице описаний |
| BA84 | `droid_stats` | 104 | 92% | plr_droid_init, salv_exit | part_stat | характеристики дроида по частям (AFAA, AFA6) |
| BAEC | `part_stat` | 15 | 100% | droid_stats |  | характеристика части |
| BAFB | `scr_droidinfo` | 100 | 100% | cs_droids, cs_droids_loop, xf_won | attr_rects, cls_bitmap, droid_desc, hi_nibble7, panel_frame, part_byte3, print_list | экран сведений о дроиде |
| BB5F | `part_byte3` | 15 | 100% | scr_droidinfo |  | байт 3 записи части |
| BB6E | `hi_nibble7` | 61 | 100% | scr_droidinfo |  | (A >> 4) & 7 |
| BBAB | `scr_salvage` | 33 | 100% | xf_won | attr_rects, print_list | трофеи после захвата: выбор частей побеждённого дроида |
| BBCC | `salv_roll` | 20 | 100% |  | rnd | трофеи: часть доступна, если (rnd & 7) < v_xf_count (перевес в захвате) |
| BBE0 | `salv_loop` | 67 | 100% | salv_mark, salv_take, salv_weapon | attr_rects, pause_check, play_tune, salv_take | трофеи: опрос, курсор по 6 строкам (выход + 5 частей) |
| BC23 | `salv_take` | 90 | 97% | salv_loop | salv_chassis, salv_drive, salv_exit, salv_loop, salv_mark, salv_power, salv_weapon | огонь: взять выбранную часть, если доступна и не взята |
| BC7D | `salv_drive` | 8 | 100% | salv_take | salv_mark | DRIVE: байт 0 противника целиком |
| BC85 | `salv_power` | 16 | 100% | salv_take | salv_mark | POWER: байт 2 целиком, предел энергии и энергия 0x3F |
| BC95 | `salv_weapon` | 20 | 100% | salv_take | salv_loop, salv_mark | WEAPON: младшая тетрада байта 1 (если у противника есть оружие) |
| BCA9 | `salv_chassis` | 15 | 100% | salv_take |  | CHASSIS: старшая тетрада байта 1 |
| BCB8 | `salv_mark` | 33 | 100% | salv_drive, salv_power, salv_take, salv_weapon | play_tune, print_list, salv_loop, scr_down8 | отметка «взято» у строки, мелодия 4 |
| BCD9 | `salv_exit` | 84 | 100% | salv_take | droid_stats, panel_cls | выход: класс противника -> игроку (б2 младшая тетрада), droid_stats, номер класса в панель |
| BD2D | `isr` | 41 | 100% |  | isr_sfx, isr_tone | прерывание IM 2: звуковые эффекты через бипер |
| BD56 | `isr_sfx` | 22 | 100% | isr | isr_exit, isr_noise, isr_tone | isr: текущий эффект; 0x11 — шум |
| BD6C | `isr_noise` | 30 | 100% | isr_sfx | isr_exit, rnd | шум: 0x30 импульсов бипера по rnd, отрезков v_sfx_segs |
| BD8A | `isr_tone` | 21 | 100% | isr, isr_sfx | isr_sweep | тон: 255 полупериодов с периодом v_sfx_period |
| BD9F | `isr_sweep` | 37 | 87% | isr_tone | isr_exit, isr_segment | период += v_sfx_sweep; кадры отрезка, отрезки, следующий эффект |
| BDC4 | `isr_segment` | 52 | 100% | isr_sweep |  | новый отрезок: база по режиму (0 та же, 1 −2, 2 +2, 3 обратить шаг) |
| BDF8 | `isr_exit` | 16 | 100% | isr_noise, isr_sfx, isr_sweep |  | восстановить AF', exx, ei, ret |
| BE08 | `dk_tile` | 48 | 100% | cs_plan, dd_cell, dd_top, dk_column, dk_tiles_n | blit_tile, gfx_lookup | плитка A (+ чётность клетки) в y = v_dk_y, если видна |
| BE38 | `deck_draw` | 68 | 100% | cam_step, deck_reset |  | отрисовка палубы полосами по блоку v_scr_* |
| BE7C | `dd_strip` | 29 | 100% | dd_next_diag | strip_fill | deck_draw: новая полоса (столбец v_strip_col): залить, начать диагональ |
| BE99 | `dd_cell` | 50 | 100% | dd_next | dd_edge, dd_mapcell, dd_next_diag, dk_attr, dk_column, dk_tile | клетка диагонали (e, d): вне карты — край; иначе высота и тип (BEF1) |
| BECB | `dd_edge` | 38 | 100% | dd_cell | dd_next, dd_next_diag, dk_attr, dk_y_next | за краем карты: фон (dk_attr 0) или нижний край |
| BEF1 | `dd_mapcell` | 92 | 100% | dd_cell | dd_wall | индекс клетки (d & 0x3C) << 2 / e >> 2, высота, тип, наклон по чётности |
| BF4D | `dd_wall` | 66 | 100% | dd_mapcell | dd_top, dk_attr, dk_column, dk_y_next | стенка от прошлой высоты до текущей (dk_column) или первая клетка |
| BF8F | `dd_top` | 35 | 100% | dd_wall | dd_next_diag, dk_tile, dk_y_next | верх клетки: тип 0 — стена (v_tilebase + 7), иначе плитка тип*2 + 0x21 |
| BFB2 | `dd_next` | 19 | 100% | dd_edge | dd_cell | следующая клетка диагонали (d += 2, e −= 2) |
| BFC5 | `dd_next_diag` | 58 | 100% | dd_cell, dd_edge, dd_top | dd_strip, strip_put | следующая диагональ (d0, e0 += 2), по ширине — следующая полоса, в конце strip_put |
| BFFF | `dk_column` | 69 | 100% | dd_cell, dd_wall | dk_tile, dk_y_next | столб высотой A уровней: верх, середина, низ |
| C044 | `strip_fill` | 22 | 100% | cs_menu, cs_plan, dd_strip |  | залить буфер-полосу 0xFF |
| C05A | `scr_copy` | 209 | 100% | cs_menu, deck_show, flash_end, frame_tail, ou_deck_dec, ou_touch_plr, plr_die, spr_pace, use_lift |  | буфер поля 0x8300 -> экран ZX + атрибуты по t_colattr |
| C12B | `dk_attr` | 111 | 100% | dd_cell, dd_edge, dd_wall |  | отметить цвет столбца в t_colattr |
| C19A | `dk_y_next` | 11 | 100% | dd_edge, dd_top, dd_wall, dk_column |  | v_dk_y += 8 |
| C1A5 | `strip_put` | 104 | 100% | dd_next_diag |  | буфер-полоса -> буфер поля 0x8300 |
| C20D | `bg_restore` | 88 | 100% | spr_render |  | фон из t_field в окно спрайта (под спрайтом) |
| C265 | `drawlist_add` | 71 | 100% | ou_draw, plr_base |  | вставить v_drawrec в t_drawlist по глубине |
| C2AC | `obj_anim` | 84 | 100% | ou_alive, plr_hover |  | шаг анимации объекта -> AFBB кадр |
| C300 | `obj_move` | 22 | 100% | objs_update, plr_update | om_project, om_walk | движение объекта, высоты и столкновение с картой; игроку — v_plr_cell |
| C316 | `om_walk` | 56 | 100% | obj_move | om_fall, om_move_x, om_shot_end | шаг по y (затем om_move_x), граница карты |
| C34E | `om_move_x` | 107 | 100% | om_walk | map_cell, om_shot_end, om_shot_wall, om_slope | шаг по x (после y), граница карты: дроиды отскакивают, выстрелы гаснут |
| C3B9 | `om_slope` | 76 | 100% | om_move_x | om_height | клетки 1/2 — наклон: высота по положению в клетке, игрока сталкивает |
| C405 | `om_height` | 76 | 100% | om_slope | om_bounce, om_store | сравнение высоты клетки: подъём ≤ 4 — встать, выше — отскок, ниже — падение |
| C451 | `om_fall` | 89 | 100% | om_walk | map_cell, om_store | падение: v_obj_dz растёт до 6, приземление — звук 10 |
| C4AA | `om_store` | 56 | 100% | om_fall, om_height | om_accel, om_wander | записать новую высоту/позицию |
| C4E2 | `om_accel` | 85 | 100% | om_store |  | игрок: разгон по вводу с пределом v_plr_speed, ограничение диагонали |
| C537 | `om_wander` | 81 | 100% | om_store | om_wander_chk, rnd | дроид: стоит — случайное направление; в центре клетки — новое (t_wander_dir) |
| C588 | `om_wander_chk` | 87 | 100% | om_wander | om_stop | дроид: проверка клетки по направлению (перепад высоты > 7 — стоп) |
| C5DF | `om_bounce` | 44 | 100% | om_height |  | стена (выше на > 4): отскок по скоростям |
| C60B | `om_shot_end` | 7 | 100% | om_move_x, om_walk | om_stop | выстрел за границей карты: в конец (анимация 0x10) |
| C612 | `om_shot_wall` | 41 | 100% | om_move_x | om_stop | выстрел в стену: тип / 0x80, кадры попадания t_hit_gfx (2), энергия 8 |
| C63B | `om_stop` | 11 | 100% | om_shot_end, om_shot_wall, om_wander_chk |  | обнулить скорости |
| C646 | `om_project` | 105 | 100% | obj_move | om_offscreen | проекция на экран (v_dr_x/y) и глубина (v_drawrec) |
| C6AF | `om_offscreen` | 9 | 100% | om_project |  | вне экрана |
| C6B8 | `map_cell` | 72 | 100% | om_fall, om_move_x |  | клетка карты по координатам HL -> v_cellptr, AFB0 высота*8, AFB1 тип |
| C700 | `xfer_game` | 21 | 100% | ou_touch_plr | droid_desc, print_comp, scr_gameover, xf_result | мини-игра захвата дроида (провода и импульсы) |
| C715 | `xf_restart` | 21 | 100% | xf_finish | attr_rects, cls_attr, cls_bitmap, print_list | новый раунд (после ничьей DEADLOCK) |
| C72A | `xf_gen` | 40 | 100% |  | xf_side_setup | захват: генерация проводов обеих сторон |
| C752 | `xf_gen_cell` | 269 | 99% | xf_gen_next | rnd, xf_gen_next | генерация: ячейка ряда (rnd & 15 -> элемент) |
| C85F | `xf_gen_next` | 30 | 100% | xf_gen_cell | xf_gen_cell | генерация: следующая ячейка / ряд / сторона |
| C87D | `xf_draw` | 159 | 100% |  | print_at, scr_down8, xf_glyph_t, xf_side_setup | захват: вывод проводов стороны |
| C91C | `xf_pulses` | 54 | 100% |  | xf_side_setup, xf_use_pulse | число импульсов по классам, таймер 0x99 |
| C952 | `xf_board` | 115 | 100% | xf_pickside | attr_rects, panel_msg, print_at, str_find2, xf_counts | рамки, цвета сторон, подписи, сообщение |
| C9C5 | `xf_pick_loop` | 19 | 100% | xf_pickside | xf_side_done, xf_timer | выбор стороны: таймер и звук |
| C9D8 | `xf_pickside` | 50 | 100% |  | input_read, xf_board, xf_pick_loop, xf_side_done | выбор стороны по таймеру |
| CA0A | `xf_side_done` | 15 | 100% | xf_pick_loop, xf_pickside | panel_msg | сторона выбрана (огонь или время вышло) |
| CA19 | `xf_play` | 52 | 100% | xf_ai_move | xf_movecount, xf_turn | основная фаза: таймер, ходы |
| CA4D | `xf_beep` | 19 | 100% |  | xf_timer, xf_turn | захват: щелчки бипера в такт (анимация знака в шрифте 0x38B) |
| CA60 | `xf_movecount` | 7 | 100% | xf_play | xf_finish | ходов −1, 0 — итог |
| CA67 | `xf_turn` | 74 | 100% | xf_beep, xf_play | input_read, xf_after_plr, xf_cursor, xf_fire, xf_side_setup | ход игрока: курсор, импульс |
| CAB1 | `xf_after_plr` | 18 | 100% | xf_turn | rnd, xf_ai_turn, xf_finish, xf_update | после хода игрока — обход проводов; на последнем ходу 50% — итог сразу |
| CAC3 | `xf_ai_turn` | 37 | 100% | xf_after_plr | xf_ai_move, xf_ai_pick, xf_side_setup | ход противника (по чётности v_xf_tick) |
| CAE8 | `xf_ai_move` | 57 | 80% | xf_ai_turn | xf_ai_pick, xf_cursor, xf_fire, xf_play, xf_update | противник: курсор к выбранному ряду, на ряду — импульс и новый выбор |
| CB21 | `xf_finish` | 22 | 100% | xf_after_plr, xf_movecount | print_comp, xf_restart, xf_result, xf_won | итог по v_xf_count: 0 ничья, < 0x80 победа (сведения + трофеи), иначе поражение |
| CB37 | `xf_won` | 25 | 100% | xf_finish | print_comp, scr_droidinfo, scr_salvage, xf_lost, xf_result | перевес < 0x80 — победа: COMPLETE, мелодия 3 |
| CB50 | `xf_lost` | 13 | 100% | xf_won | input_wait_up, xf_result | поражение: FAILED, энергия игрока 0 (гибель) |
| CB5D | `xf_ai_pick` | 33 | 100% | xf_ai_move, xf_ai_turn | rnd | противник выбирает провод (случайно) |
| CB7E | `xf_fire` | 84 | 100% | xf_ai_move, xf_turn | xf_glyph, xf_glyph_t, xf_rowaddr, xf_use_pulse | пустить импульс по проводу |
| CBD2 | `xf_glyph_t` | 12 | 100% | xf_down, xf_draw, xf_fire | xf_glyph | знак из таблицы CF07 |
| CBDE | `xf_glyph` | 16 | 100% | xf_fire, xf_glyph_t, xu_draw | print_at, scr_attr_hi | знак захвата в экран |
| CBEE | `xf_rowaddr` | 50 | 100% | xf_fire, xu_row | scr_down8 | адрес ряда проводов в экране |
| CC20 | `xf_side_setup` | 88 | 100% | xf_ai_turn, xf_draw, xf_gen, xf_pulses, xf_turn |  | параметры стороны (цвета, буфер, адреса) |
| CC78 | `xf_counts` | 30 | 100% | xf_board, xf_use_pulse | attr_rects | показать запас импульсов |
| CC96 | `xf_use_pulse` | 40 | 100% | xf_fire, xf_pulses | xf_counts, xf_cursor | израсходовать импульс |
| CCBE | `xf_cursor` | 57 | 100% | xf_ai_move, xf_turn, xf_use_pulse | xf_down | курсор выбора провода |
| CCF7 | `xf_down` | 14 | 100% | xf_cursor | scr_down8, xf_glyph_t | вниз на N знакорядов и знак |
| CD05 | `xf_update` | 10 | 100% | xf_after_plr, xf_ai_move |  | движение импульсов по проводам |
| CD0F | `xu_row` | 50 | 100% | xu_next | xf_rowaddr, xu_cell | xf_update: ряд стороны; ячейка 0 — время импульса (≥ 0x10): −0x10 за обход, по истечении снова провод |
| CD41 | `xu_cell` | 57 | 100% | xu_row | xu_draw, xu_next | ячейка: цвет состояния, знак горящего/холодного провода; узел 2 в слиянии — цвет из рядов выше/ниже |
| CD7A | `xu_draw` | 48 | 100% | xu_cell | xf_glyph | вывод ячейки (xf_glyph) и атрибута цвета |
| CDAA | `xu_pass` | 30 | 100% |  | xu_invert, xu_latch, xu_next, xu_split | передать цвет в следующую ячейку по её типу |
| CDC8 | `xu_split` | 20 | 100% | xu_pass | xu_next | тип 2 (разветвление): цвет в ряд выше и ниже |
| CDDC | `xu_invert` | 11 | 100% | xu_pass | xu_next | тип 4: не пусто -> цвет противника |
| CDE7 | `xu_latch` | 6 | 100% | xu_pass | xu_next | тип 7: принимает только цвет (держит) |
| CDED | `xu_next` | 34 | 100% | xu_cell, xu_invert, xu_latch, xu_pass, xu_split | xu_row | следующая ячейка / ряд; после всех рядов — подсчёт |
| CE0F | `xu_count` | 96 | 100% |  | attr_rects | центр: цвет ряда по последней ячейке (0x30 жёлтый / 0x08 синий), v_xf_count ±1, полоса цвета перевеса |
| CE6F | `scr_attr_hi` | 10 | 100% | xf_glyph |  | старший байт адреса атрибута для адреса экрана |
| CE79 | `xf_timer` | 36 | 100% | xf_beep, xf_pick_loop | print_at | таймер захвата -1 (BCD: daa после sub — на i8080 вручную!) |
| CE9D | `xf_result` | 283 | 100% | xf_finish, xf_lost, xf_won, xfer_game | panel_msg, play_tune | сообщение и мелодия итога захвата |
| CFB8 | `console` | 105 | 100% | use_console | attr_rects, bonus_count, cs_menu, droid_desc, input_wait_up, msg_find, print_at, scr_gameover | пульт: база дроидов, карта палуб |
| D021 | `cs_menu` | 230 | 100% | console | blit_tile, cls_attr, cls_bitmap, cs_droids, gfx_lookup, input_wait_up, lift_screen, pause_check, scr_copy, spr_flush, strip_fill | меню пульта: выбор v_menu_sel (0 выход, 1 план палубы, 2 схема палуб, 3 база дроидов) |
| D107 | `cs_plan` | 243 | 100% |  | dk_tile, dk_tiles_n, dk_y_add4, spr_flush, strip_fill | план палубы целиком: клетки карты мини-плитками t_droidgfx 25–38 (тип*2 + 27) в буфер E700, по столбцам |
| D1FA | `cs_droids` | 28 | 100% | cs_menu | scr_droidinfo | пульт, база дроидов: карточка своего дроида, листание типов (вверх/вниз), огонь — к частям |
| D216 | `cs_droids_loop` | 66 | 100% |  | cs_parts, input_wait_up, pause_check, scr_droidinfo | база дроидов: опрос, смена типа (до своего класса), огонь |
| D258 | `cs_parts` | 71 | 100% | cs_droids_loop | attr_rects, cls_bitmap, cs_exit, panel_frame, print_list | база частей: карточки частей с классом доступа ≤ класса игрока (t_partstats б2) |
| D29F | `cs_circuit` | 104 | 100% |  | input_wait_up, print_at, print_comp | карточка части: картинка CIRCUIT из байтов ПЗУ ZX (по v_cs_romptr), 11 знаков в строке |
| D307 | `cs_parts_loop` | 26 | 100% |  | cs_exit, pause_check | карточки частей: опрос, листание, огонь — выход |
| D321 | `cs_exit` | 53 | 100% | cs_parts, cs_parts_loop |  | выход из пульта в меню |
| D356 | `lift` | 31 | 100% | use_lift | input_wait_up, lift_screen | лифт: выбор палубы |
| D375 | `lift_find` | 26 | 95% |  | lift_found | поиск остановки по позиции игрока (x, y & 0xF0) и палубе |
| D38F | `lift_found` | 53 | 100% | lift_find |  | шахта, подсветка на схеме |
| D3C4 | `lift_loop` | 22 | 100% | lift_wait | lift_move, pause_check | лифт: огонь — выход, вверх/вниз — ехать |
| D3DA | `lift_move` | 28 | 100% | lift_loop | lift_wait | движение по шахте: шагов (б4/б5 остановки), звук 14/15 |
| D3F6 | `lift_anim` | 38 | 100% |  | lift_arrive | подсветка ползёт по схеме (атрибут 0x47), задержка |
| D41C | `lift_arrive` | 47 | 100% | lift_anim | lift_list | новая остановка: палуба, позиция и камера игрока |
| D44B | `lift_wait` | 7 | 100% | lift_move | input_wait_up, lift_loop | ждать отпускания, снова опрос |
| D452 | `lift_screen` | 13 | 100% | cs_menu, lift | cls_attr, cls_bitmap, panel_frame | экран списка палуб |
| D45F | `lift_list` | 162 | 97% | lift_arrive | print_at, str_find2 | список палуб с цветами |
| D501 | `dk_tiles_n` | 26 | 100% | cs_plan | dk_tile | плитка 0x19 A раз со сдвигом y на 2 |
| D51B | `dk_y_add4` | 11 | 100% | cs_plan |  | v_dk_y += 4 |
| D526 | `shot_spawn` | 149 | 100% | ai_shoot, plr_shot |  | выстрел: новый объект в конце списка, звук |
| D5BB | `objs_frame` | 14 | 100% | main_loop | pause_check | кадр объектов: пауза, обход t_objs (продолжается в D5C9) |
| D5C9 | `objs_update` | 132 | 100% | plr_die | obj_move, objs_listend, ou_alive, ou_dead, ou_store | обновление объектов: ИИ, стрельба, столкновения, вывод |
| D64D | `ou_alive` | 18 | 100% | objs_update | obj_anim, ou_dead, ou_live | объект жив: анимация, столкновения, ИИ |
| D65F | `ou_live` | 63 | 100% | ou_alive | ou_collide, ou_draw, ou_explode, sat_sub | objs_update: объект жив? энергия 0 -> взрыв; при прокрутке только вывод; вспышка ранит дроидов без 0x40 |
| D69E | `ou_collide` | 16 | 100% | ou_live | ai_think, obj_collide, ou_contact, ou_draw | столкновение с другим объектом (obj_collide), иначе ИИ дроида |
| D6AE | `ou_contact` | 22 | 100% | ou_collide | ou_bounce, ou_touch_plr, shot_contact | разбор столкновения: выстрел -> D883, с игроком -> ou_touch_plr, с выстрелом/взрывом -> урон, дроид-дроид -> ou_bounce |
| D6C4 | `ai_think` | 63 | 100% | ou_collide | ai_aim, ai_regen, ou_draw, rnd | ИИ дроида: не больше 7 объектов, раз в 8 кадров — решение стрелять, иначе ai_regen |
| D703 | `ai_aim` | 58 | 74% | ai_think | ai_shoot, ou_draw | не больше 3 выстрелов; игрок почти на линии x или y (≤ 16) — направление выстрела |
| D73D | `ai_shoot` | 24 | 100% | ai_aim | ou_draw, shot_spawn | выстрел 0x30 / оружие, дроид останавливается |
| D755 | `ai_regen` | 16 | 100% | ai_think | ou_draw | энергия дроида +1 до 0x3F |
| D765 | `ou_touch_plr` | 25 | 100% | ou_contact | ou_dead, ou_deck_dec, ou_ram, scr_copy, xfer_game, xfer_off | дроид коснулся игрока: в режиме захвата — xfer_game, иначе таран |
| D77E | `ou_ram` | 106 | 100% | ou_touch_plr | ou_draw, ou_ram_win, sat_sub | таран: массы по CHASSIS (+16 за RAM THRUSTER); легче игрок — урон игроку |
| D7E8 | `ou_ram_win` | 59 | 0% | ou_ram | ou_draw, sat_sub | таран: дроид легче — урон дроиду; обоих отбрасывает |
| D823 | `ou_bounce` | 96 | 100% | ou_contact | ou_draw, sat_sub | дроид-дроид: отскок (скорости меняют знак по стороне касания) |
| D883 | `shot_contact` | 19 | 100% | ou_contact | shot_cancel, shot_hit_fx, shot_hit_plr | выстрел во что-то: в игрока (LASER SHIELDS — урон /2), в дроида, во взрыв, в другой выстрел |
| D896 | `shot_hit_plr` | 41 | 95% | shot_contact | ou_dead, ou_draw, ou_hit | выстрел дроида в игрока: урон по оружию, сравнение с CHASSIS |
| D8BF | `ou_hit` | 15 | 100% | shot_hit_plr | ou_dead, sat_sub | попадание: урон по энергии цели, звук 10 |
| D8CE | `shot_hit_fx` | 28 | 100% | shot_contact | ou_draw, sat_sub | выстрел во взрыв/обломки |
| D8EA | `shot_cancel` | 8 | 0% | shot_contact | ou_dead | выстрел в выстрел — оба исчезают |
| D8F2 | `ou_explode` | 59 | 100% | ou_live | ou_dead, ou_draw | энергия 0: объект -> взрыв (тип / 0x80, кадры A493, звук 0x11) |
| D92D | `ou_dead` | 21 | 100% | objs_update, ou_alive, ou_explode, ou_hit, ou_touch_plr, shot_cancel, shot_hit_plr | ou_killed, ou_remove | объект кончился: счёт, v_kills, счётчики выстрелов |
| D942 | `ou_killed` | 47 | 96% | ou_dead | ou_deck_dec, panel_ind | дроид уничтожен: v_kills += тип, очки (класс+1)*10.. |
| D971 | `ou_deck_dec` | 50 | 100% | ou_killed, ou_touch_plr | ou_remove, score_tick, scr_copy | дроидов на палубе -1; палуба очищена — +500 |
| D9A3 | `ou_remove` | 21 | 100% | ou_dead, ou_deck_dec |  | объект упал за край (z ≥ 0x80) — удалить |
| D9B8 | `ou_draw` | 3 | 100% | ai_aim, ai_regen, ai_shoot, ai_think, ou_bounce, ou_collide, ou_explode, ou_live, ou_ram, ou_ram_win, shot_hit_fx, shot_hit_plr | drawlist_add | в список вывода (drawlist_add) |
| D9BB | `ou_store` | 22 | 100% | objs_update |  | запись объекта обратно в t_objs |
| D9D1 | `objs_listend` | 16 | 100% | objs_update | objs_post | конец списка объектов; затем игрок (при гибели, v_scrolldir = 5, — пропуск) |
| D9E1 | `plr_update` | 185 | 100% |  | obj_move, plr_body_gfx | игрок: копия записи, движение obj_move, направление по вводу, выстрел/огонь |
| DA9A | `plr_body_gfx` | 48 | 100% | plr_update | plr_settle | игрок: «лицо» корпуса — отдача или покой |
| DACA | `plr_settle` | 211 | 100% | plr_body_gfx | plr_hover, rnd | игрок: подъём корпуса (v_part_dy) и оглядывание глаз |
| DB9D | `plr_hover` | 37 | 100% | plr_settle | obj_anim, plr_base | игрок: анимация опоры (t_plr_hover, 3 кадра) |
| DBC2 | `plr_base` | 58 | 100% | plr_hover | drawlist_add | игрок: основание по энергии, запись в список вывода |
| DBFC | `objs_post` | 40 | 100% | objs_listend | panel_ind, spr_render | конец кадра объектов: v_frame+1; раз в 16 кадров v_kills −1 и бонус к счёту (v_kills >> 6)*5, индикатор |
| DC24 | `spr_render` | 143 | 100% | objs_post | bg_restore, spr_pace | вывод спрайтов: окна в буфере E700 (0x81/0xC1 байт), полоса, bg_restore, части по списку вывода |
| DCB3 | `spr_drawlist` | 198 | 100% |  | blit_tile, font_copy | spr_render: части объектов из списка вывода в окно (игрок — 4 части, дроид — купол и номер) |
| DD79 | `spr_pace` | 37 | 100% | spr_render | score_tick, scr_copy | конец кадра: досчёт очков, задержка по числу объектов (меньше 6 — ждать), полная копия при v_scrolldir ≥ 7 |
| DD9E | `font_copy` | 65 | 100% | spr_drawlist |  | знак A шрифта (8 байт) в DE |
| DDDF | `obj_collide` | 99 | 100% | ou_collide |  | есть ли объект рядом с v_obj_x/y/z |
| DE42 | `sat_sub` | 7 | 100% | ou_bounce, ou_hit, ou_live, ou_ram, ou_ram_win, shot_hit_fx |  | (HL) = max((HL) - C, 0) |
| DE49 | `xfer_off` | 14 | 100% | deck_enter, ou_touch_plr, xfer_armed | panel_mode | выход из режима захвата |
| DE57 | `panel_ind` | 25 | 100% | objs_post, ou_killed |  | индикатор панели по v_kills >> 6 (t_ind_attr) |
| DE70 | `start` | 36 | 94% |  | menu_controls | старт игры (после загрузчика) |
| DE94 | `title_loop` | 43 | 100% | hi_letter | attr_rects, game_reset, play_tune, plr_droid_init, print_at, print_list, scr_gameover | заставка и меню (сюда же после конца игры) |
| DEBF | `city_start` | 121 | 100% | city_clear | gfx_lookup, msg_find, play_tune, print_at, print_comp, rnd, scr_gameover | начало города: экран, население, стартовая палуба |
| DF38 | `pop_gen` | 62 | 100% |  | pop_pair, rnd | city_start: население города — по палубам 12 дроидов (тип ≤ предела палубы и города), позиции из клеток |
| DF76 | `deck_enter` | 149 | 100% | deck_change | cam_iso, xfer_off | вход на палубу: карта, позиция, отрисовка, объекты |
| E00B | `deck_reset` | 84 | 100% |  | deck_draw, gfx_lookup, mul12 | deck_enter: сброс кэша плиток, режимов прокрутки, t_colattr |
| E05F | `deck_objs` | 90 | 100% |  | deck_objs_end | deck_enter: объекты палубы из населения (тип, позиция, энергия 0x3F, кадры 43) |
| E0B9 | `deck_objs_end` | 21 | 100% | deck_objs | deck_show | конец списка; нет дроидов — тёмная палуба (0x08) |
| E0CE | `deck_show` | 14 | 100% | deck_objs_end | scr_copy | полная копия поля, графика дроидов, игрок |
| E0DC | `main_loop` | 24 | 100% | cam_step, city_check, plr_die, scroll_start | objs_frame, scroll_step, sprwins_flush | главный цикл (внутри start) |
| E0F4 | `scroll_step` | 41 | 100% | main_loop | colattr_shift, scr_shift_left, scr_shift_right, scr_shift_up, scroll_check | шаг прокрутки: сдвиг t_field по направлению v_scrolldir |
| E11D | `scr_shift_up` | 15 | 100% | scroll_step | colattr_shift | поле вверх на 8 строк (игрок у нижнего края, 0x1E) |
| E12C | `scr_shift_left` | 26 | 100% | scroll_step |  | поле влево на 2 байта (у правого края, 0x0A), t_colattr тоже |
| E146 | `scr_shift_right` | 30 | 100% | scroll_step | cam_step | поле вправо на 2 байта (у левого края, 0x14) |
| E164 | `colattr_shift` | 42 | 100% | scr_shift_up, scroll_step |  | сдвиг строк пола в t_colattr на ±1 знакоряд (вертикальная прокрутка) |
| E18E | `cam_step` | 33 | 100% | scr_shift_right | cam_iso, deck_draw, main_loop | камера += шаг режима, новая полоса палубы |
| E1AF | `scroll_check` | 40 | 100% | scroll_step | frame_tail, scroll_start | игрок у края экрана (x < 9, ≥ 0xF7, y < 0x18, ≥ 0x97) -> scroll_start |
| E1D7 | `scroll_start` | 21 | 100% | scroll_check | main_loop | запуск прокрутки: блок режима из t_scrollmodes |
| E1EC | `frame_tail` | 13 | 100% | scroll_check | scr_copy, xfer_armed | полная копия по запросу, режим захвата, клавиши, огонь |
| E1F9 | `xfer_armed` | 36 | 100% | frame_tail | after_action, panel_key, xfer_off | режим захвата включён: сигнал раз в 16 кадров, огонь — выключить |
| E21D | `panel_key` | 40 | 100% | xfer_armed | fire_logic, panel_mode | клавиша W (FBFE б1) — смена режима окна панели |
| E245 | `fire_logic` | 37 | 100% | panel_key | after_action, cell_action, plr_fire | огонь без направления — счёт удержания v_fire_hold |
| E26A | `cell_action` | 22 | 100% | fire_logic | plr_fire, use_console, use_lift, xfer_arm | удержание ≥ 8: лифт (3), пульт (4), иначе режим захвата |
| E280 | `plr_fire` | 48 | 100% | cell_action, fire_logic | after_action, cls_attr, plr_shot | выстрел по направлению: задержка; оружие 5 — вспышка, иначе выстрел |
| E2B0 | `plr_shot` | 54 | 100% | plr_fire | after_action, shot_spawn | выстрел игрока 0x40 / оружие со скоростью t_shot_vel (один в полёте) |
| E2E6 | `use_lift` | 20 | 100% | cell_action | deck_change, lift, plr_cooldown, scr_copy | лифт; другая палуба -> deck_change |
| E2FA | `xfer_arm` | 18 | 100% | cell_action | panel_msg, plr_cooldown | включить режим захвата (сообщение, рамка панели) |
| E30C | `use_console` | 5 | 100% | cell_action | console, plr_cooldown | пульт |
| E311 | `after_action` | 45 | 100% | fire_logic, plr_fire, plr_shot, xfer_armed | plr_cooldown | после действий игрока: подзарядка |
| E33E | `plr_cooldown` | 40 | 100% | after_action, use_console, use_lift, xfer_arm | cls_attr, energy_tick, flash_end, sat_sub2 | задержка выстрела, вспышка (v_flash), предупреждение энергии, проверка города |
| E366 | `flash_end` | 36 | 100% | plr_cooldown | sat_sub2, scr_copy | вспышка: экран назад, урон игроку без DISRUPTOR SHIELDS (город + 0x18 − CHASSIS) |
| E38A | `energy_tick` | 33 | 100% | plr_cooldown | energy_check, sat_sub2 | раз в 64 кадра: износ — предел энергии −(расход/2 + 1) |
| E3AB | `energy_check` | 47 | 100% | energy_tick | city_check, panel_mode, panel_msg, plr_die | энергия 0 -> гибель; < 8 — сигнал и сообщение в панели |
| E3DA | `city_check` | 17 | 100% | energy_check | city_clear, main_loop | сумма t_deckdroids = 0 -> city_clear |
| E3EB | `plr_die` | 224 | 100% | energy_check | game_over, main_loop, objs_update, panel_cls, panel_msg, play_tune, plr_droid_init, print_comp, rnd, scr_copy, scr_gameover, sprwins_flush | гибель: 4 обломка вокруг игрока, класс 0 -> конец игры, иначе слабый дроид |
| E4CB | `deck_change` | 72 | 92% | use_lift | deck_enter, mul12 | лифт на другую палубу: живые дроиды палубы -> население, вход на новую |
| E513 | `city_clear` | 77 | 100% | city_check | city_start, msg_find, print_at, score_tick, scr_gameover | город пройден: сообщение, +2000, следующий город |
| E560 | `game_over` | 50 | 100% | plr_die | bonus_count, hi_enter, msg_find, play_tune, print_at, score_tick, scr_gameover | конец игры: бонус, досчёт, мелодия 1, сравнение с рекордом |
| E592 | `hi_enter` | 34 | 100% | game_over | attr_rects, print_list, scr_gameover | новый рекорд: запись счёта и ввод имени |
| E5B4 | `hi_letter` | 162 | 98% |  | input_read, input_wait_up, play_tune, print_at, title_loop | ввод буквы имени в таблицу рекордов |
| E656 | `sprwins_flush` | 38 | 100% | main_loop, plr_die | spr_flush | t_sprwins -> экран (spr_flush) |
| E67C | `plr_droid_init` | 20 | 100% | plr_die, title_loop | droid_stats | дроид игрока по умолчанию, характеристики, v_energy_max |
| E690 | `mul12` | 15 | 100% | deck_change, deck_reset |  | A * 12 |
| E69F | `cam_iso` | 31 | 100% | cam_step, deck_enter |  | камера -> v_iso_x/y |
| E6BE | `sat_sub2` | 7 | 100% | energy_tick, flash_end, plr_cooldown |  | копия sat_sub |
| E6C5 | `pop_pair` | 33 | 100% | pop_gen | rnd | позиция дроида населения: y = (ряд*2+2)*16, x = rnd & 0xF0 |
| E6E6 | `isr_jump` | 1963 | 100% |  |  | jp isr (вектор IM 2) |
