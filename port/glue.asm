; Склейка Quazatron (ZX) с Вектором-06Ц, процессор Z80 (этап 1, docs/PLAN.md).
; Занимает 0x0000-0x1FFF: старт, входы RST, кадровое прерывание, перевод теневого экрана ZX в плоскость,
; клавиатура ZX и Kempston из матрицы и джойстика Вектора, бипер. Копия ПЗУ ZX 0000-052F лежит с 0x1000.
; Игра — на своих адресах; окно 8000-9FFF перенесено в 2000-3FFF (tools/port_build.py), 4000-5AFF — теневой экран ZX.

		DEVICE	NOSLOT64K

RELO		equ	0x4000 - 0xDE70		; блок DE70-EE90 перенесён в 4000 (tools/port_build.py)
GAME_START	equ	0xDE70 + RELO		; start игры
GAME_ISR	equ	0xBD2D			; isr игры (звук), заканчивается ei / ret
GAME_SP		equ	0x61A5			; стек, как после загрузки с ленты
PLANE		equ	0x80			; видимая плоскость 0x8000-0x9FFF (бит 3 индекса палитры)
ROW0		equ	223			; строка памяти плоскости для строки 0 экрана ZX (поле 192 строки по центру)
COLS_PER_IRQ	equ	1			; scr_slice — перевод теневого экрана по столбцам (отладка; поле в тени не обновляется)
G_SPR_FLUSH	equ	0xB424			; spr_flush: окно спрайта -> экран ZX (вход заменён на jp vec_spr_flush)
G_SCR_COPY_ATTR	equ	0xC0C3			; scr_copy: атрибутная часть (битмап поля пишем сами)
G_CLS_BITMAP	equ	0xB2C9			; cls_bitmap (вход заменён на jp vec_cls)
T_FIELD		equ	0x2300			; буфер поля 32 x 152 (перенесён из 8300)
V_STRIP_H	equ	0xAF17
V_STRIP_ROW	equ	0xAF15
V_STRIP_COL	equ	0xAF14
INK		equ	0xFF			; %BBGGGRRR
PAPER		equ	0x00

		org	0
		di
		jp	boot

; rst 08h — вместо out (0FEh),a: бит 4 (бипер ZX) -> бит 0 порта C ВВ55 (бит-сет, порт 0)
		org	0x08
		jp	zx_out_fe

; rst 10h — вместо in a,(c): C = 1Fh — Kempston, иначе клавиатура ZX по рядам в B
		org	0x10
		jp	zx_in_c

; rst 18h — вместо ld (hl),a в атрибуты ZX (а также ld (hl),c в B96F и ld (hl),47h в D3C2/D402): атрибут + класс клетки
		org	0x18
		jp	attr_hl

; rst 20h — начало blit_tile (вместо ld a,(hl) / inc hl): HL = 0 — пустая ячейка графики, ничего не выводить
; (ошибка оригинала: на ZX выводится «картинка» из ПЗУ с адреса 0 — мусор на кадр)
		org	0x20
		jp	blit_guard

; rst 28h — вместо ld (de),a в атрибуты ZX: атрибут + класс клетки
		org	0x28
		jp	attr_de

; rst 30h — конец play_tune (вместо ei): мелодия замолкает
		org	0x30
		jp	vec_tune_end

		org	0x38
		jp	vec_isr

		org	0x100
boot:		di
		ld	sp,GAME_SP
		ld	a,0x88
		out	(0),a
		xor	a
		out	(2),a
		ld	a,0xFF
		out	(3),a
		ld	a,0x83			; джойстик «П»: ВВ55 №2, порт 5 = 9Fh — оба устройства сразу
		out	(4),a
		ld	a,0x9F
		out	(5),a
		in	a,(6)			; покой: им нормируется каждый опрос
		ld	(joy_rest),a
		ld	hl,PLANE << 8			; очистить видимую плоскость
.clr:		ld	(hl),0
		inc	hl
		ld	a,h
		cp	(PLANE + 0x20)
		jr	nz,.clr
		im	1
		jp	GAME_START

; ---- кадровое прерывание: палитра, клавиатура, кусок экрана, затем isr игры ----
vec_isr:	push	af
		push	bc
		push	de
		push	hl
		push	ix
		ld	hl,pal_left		; палитру грузим первые кадры после старта (дальше держится сама)
		ld	a,(hl)
		and	a
		jr	z,.nopal
		dec	(hl)
		ld	hl,vec_pal+15
		ld	c,15
.pal:		ld	a,c
		out	(2),a
		ld	a,(hl)
		dec	hl
		out	(0x0C),a
		out	(0x0C),a
		out	(0x0C),a
		out	(0x0C),a
		dec	c
		jp	p,.pal
.nopal:		call	kbd_scan
		ld	a,0x88
		out	(0),a
		ld	a,0xFF
		out	(3),a
		xor	a
		out	(2),a
		xor	a
		ld	(tone_frame),a
		call	GAME_ISR		; звук игры (возвращается с ei)
		di
		ld	a,(tone_frame)		; тона в этом кадре не было — счётчик 0 замолчать
		and	a
		call	z,vi_tone_off
		call	vi_frame_end
		pop	ix
		pop	hl
		pop	de
		pop	bc
		pop	af
		ei
		ret

; матрица Вектора -> vec_kb[8] (1 — нажата), затем ряды ZX zx_rows[8] (0 — нажата, биты 0-4)
kbd_scan:	ld	a,0x8A
		out	(0),a
		ld	hl,vec_kb
		ld	b,0xFE
.row:		ld	a,b
		out	(3),a
		in	a,(2)
		cpl
		ld	(hl),a
		inc	hl
		rlc	b
		jr	c,.row
		ret

; ряд ZX номер (zx_map + 20*номер в IX) из матрицы vec_kb -> A (0 — нажата, биты 0-4)
zx_row:		push	bc
		push	de
		push	hl
		ld	b,5
		ld	e,0xFF
		ld	d,1
.zb:		ld	a,(ix+0)
		call	.key
		ld	a,(ix+2)
		cp	0xFF
		jr	z,.znext
		inc	ix
		inc	ix
		call	.key
		dec	ix
		dec	ix
.znext:		inc	ix
		inc	ix
		inc	ix
		inc	ix
		sla	d
		djnz	.zb
		ld	a,e
		pop	hl
		pop	de
		pop	bc
		ret
.key:		ld	hl,vec_kb		; A — ряд Вектора, (IX+1) — маска; нажата -> сбросить бит D в E
		add	a,l
		ld	l,a
		jr	nc,.knc
		inc	h
.knc:		ld	a,(hl)
		and	(ix+1)
		ret	z
		ld	a,d
		cpl
		and	e
		ld	e,a
		ret

; rst 10h: in a,(c) ZX
zx_in_c:	ld	a,c
		cp	0x1F
		jr	z,.kemp
		push	bc
		push	de
		push	ix
		ld	ix,zx_map
		ld	c,0xFF
		ld	e,8
.k:		srl	b			; бит ряда в перенос: 0 — ряд выбран
		jr	c,.skip
		call	zx_row			; IX += 20
		and	c
		ld	c,a
		jr	.nx
.skip:		push	de
		ld	de,20
		add	ix,de
		pop	de
.nx:		dec	e
		jr	nz,.k
		ld	a,c
		or	0xE0			; биты 5-7 у ZX — 1
		pop	ix
		pop	de
		pop	bc
		and	a
		ret
.kemp:		; джойстик «П» (порт 06h, нормирован покоем, 0 — нажата: б0 вправо, б1 влево, б2 вверх, б3 вниз, б6 огонь)
		; -> Kempston (1 — нажата): б0 вправо, б1 влево, б2 вниз, б3 вверх, б4 огонь
		push	bc
		in	a,(0x06)
		ld	b,a
		ld	a,(joy_rest)
		xor	b			; отличие от покоя — нажато
		ld	b,a
		and	0x30			; биты 4, 5 не меняются: иначе порта нет и «нажато всё» — считаем, что ничего
		jr	z,.k0
		ld	b,0
.k0:		ld	a,b
		and	0x03			; вправо, влево — на месте
		ld	c,a
		bit	2,b
		jr	z,.k1
		set	3,c
.k1:		bit	3,b
		jr	z,.k2
		set	2,c
.k2:		bit	6,b
		jr	z,.k3
		set	4,c
.k3:		ld	a,(vec_kb)		; + стрелки клавиатуры: б7 вниз, б6 вправо, б5 вверх, б4 влево
		ld	b,a
		bit	6,b
		jr	z,.a1
		set	0,c
.a1:		bit	4,b
		jr	z,.a2
		set	1,c
.a2:		bit	7,b
		jr	z,.a3
		set	2,c
.a3:		bit	5,b
		jr	z,.a4
		set	3,c
.a4:		ld	a,(vec_kb+7)		; + пробел — огонь
		and	0x80
		jr	z,.a5
		set	4,c
.a5:		ld	a,(vec_kb+1)		; + F1 и F3 вместе — тоже огонь (старт игры в режиме бога, god_start)
		and	0x28
		cp	0x28
		jr	nz,.a6
		set	4,c
.a6:		ld	a,c
		pop	bc
		and	a
		ret

; rst 08h: out (0FEh),a ZX — бит 4 -> бипер Вектора (бит 0 порта C, бит-сет через порт 0)
zx_out_fe:	push	af
		rrca
		rrca
		rrca
		rrca
		and	1
		out	(0),a
		pop	af
		ret

; кусок теневого экрана ZX 4000-57FF -> плоскость: COLS_PER_IRQ столбцов с scr_col
scr_slice:	ld	a,(scr_col)
		ld	c,a			; первый столбец куска
		add	a,COLS_PER_IRQ
		and	31
		ld	(scr_col),a
		ld	hl,0x4000		; адрес строки ZX (y = 0)
		ld	e,ROW0			; строка плоскости
		ld	b,192
.line:		push	hl
		ld	a,l
		add	a,c
		ld	l,a
		ld	a,PLANE
		add	a,c
		ld	d,a
		REPT	COLS_PER_IRQ
		ld	a,(hl)
		inc	l
		ld	(de),a
		inc	d
		ENDR
		pop	hl
		dec	e
		; следующая строка ZX
		inc	h
		ld	a,h
		and	7
		jr	nz,.nx
		ld	a,l
		add	a,32
		ld	l,a
		jr	c,.nx
		ld	a,h
		sub	8
		ld	h,a
.nx:		djnz	.line
		ret

; ---- звук на ВИ53 (порты: управление 08h, счётчики 0/1/2 — 0Bh/0Ah/09h; такт 1 497 600 Гц) ----
; эффекты (isr_tone) — счётчик 0; мелодии (play_tune) — счётчики 1 и 2. Тишина — управляющее слово без делителя.
G_ISR_SWEEP	equ	0xBD9F
V_SFX_PERIOD	equ	0xBDFD
; isr_tone (вход BD8A -> jp vec_tone): вместо 255 полупериодов бипера — делитель по периоду, затем isr_sweep
vec_tone:	ld	a,1
		ld	(tone_frame),a
		ld	a,(V_SFX_PERIOD)
		ld	l,a
		ld	h,0
		add	hl,hl
		ld	de,vi_tone_tab
		add	hl,de
		ld	e,(hl)
		inc	hl
		ld	d,(hl)
		ld	a,(vi0_on)
		cp	1
		jr	z,.cached
		ld	a,0x36			; счётчик 0, младший и старший байт, режим 3
		out	(8),a
		ld	a,1
		ld	(vi0_on),a
		ld	hl,0xFFFF
		ld	(vi0_div),hl
.cached:	ld	hl,(vi0_div)
		and	a
		sbc	hl,de
		jr	z,.same
		ld	(vi0_div),de
		ld	a,e
		out	(0x0B),a
		ld	a,d
		out	(0x0B),a
.same:		ld	a,(V_SFX_PERIOD)	; isr_sweep ждёт период в H
		ld	h,a
		jp	G_ISR_SWEEP
vi_tone_off:	ld	a,(vi0_on)
		and	a
		ret	z
		xor	a
		ld	(vi0_on),a
		ld	a,0x36			; управляющее слово без делителя — счётчик встаёт
		out	(8),a
		ret
; шум (вместо and 10h / or 02h / out (FEh),a в isr_noise и bonus_count): A — случайное, бит 4 — щелчок бипера ZX.
; Счётчик в режиме «только старший байт»: делитель = (случайное | 1) * 256 — 5,8 кГц и ниже; меняется на каждом щелчке.
vi_noise0:	push	af
		ld	a,(vi0_on)
		cp	2
		jr	z,.on
		ld	a,0x26			; счётчик 0, старший байт, режим 3
		out	(8),a
		ld	a,2
		ld	(vi0_on),a
.on:		ld	a,1
		ld	(tone_frame),a
		pop	af
		push	af
		and	0x1F
		or	1
		out	(0x0B),a
		pop	af
		ret
vi_noise1:	push	af
		ld	a,(vi1_on)
		cp	2
		jr	z,.on
		ld	a,0x66			; счётчик 1, старший байт, режим 3
		out	(8),a
		ld	a,2
		ld	(vi1_on),a
.on:		ld	a,1
		ld	(vi1_frame),a
		pop	af
		push	af
		and	0x1F
		or	1
		out	(0x0A),a
		pop	af
		ret
; тоны мини-игры (вместо ld hl,nn перед циклом): A — период цикла b (полупериод 27 тактов ZX на итерацию)
; -> делитель 1497600 * 2 * 27 * b / 3500000 ≈ 23,1 * b; счётчик 2; HL = длительность цикла, как в оригинале
vi_pick:	call	vi2_tone
		ld	hl,0x0300
		ret
vi_beep:	call	vi2_tone
		ld	hl,0x0301
		ret
vi2_tone:	push	af
		push	bc
		push	de
		push	hl
		ld	c,a
		ld	b,0
		ld	h,b
		ld	l,c
		add	hl,hl			; 2b
		ld	d,h
		ld	e,l
		add	hl,hl			; 4b
		add	hl,hl			; 8b
		add	hl,hl			; 16b
		add	hl,de			; 18b
		add	hl,de			; 20b
		add	hl,de			; 22b
		add	hl,bc			; 23b
		ld	a,0xB6			; счётчик 2, младший и старший байт, режим 3
		out	(8),a
		ld	a,l
		out	(0x09),a
		ld	a,h
		out	(0x09),a
		ld	a,1
		ld	(vi2_on),a
		ld	(vi2_frame),a
		pop	hl
		pop	de
		pop	bc
		pop	af
		ret
; конец кадра (после isr игры): шум счётчика 0 — только очередью в кадре; счётчики 1, 2 без обновления в кадре — тишина
vi_frame_end:	ld	a,(vi0_on)
		cp	2
		call	z,vi0_stop
		ld	a,(tune_on)
		and	a
		ret	nz
		ld	a,(vi1_frame)
		and	a
		jr	nz,.k1
		ld	a,(vi1_on)
		and	a
		jr	z,.k1
		xor	a
		ld	(vi1_on),a
		ld	a,0x76
		out	(8),a
.k1:		xor	a
		ld	(vi1_frame),a
		ld	a,(vi2_frame)
		and	a
		jr	nz,.k2
		ld	a,(vi2_on)
		and	a
		jr	z,.k2
		xor	a
		ld	(vi2_on),a
		ld	a,0xB6
		out	(8),a
.k2:		xor	a
		ld	(vi2_frame),a
		ret
vi0_stop:	xor	a
		ld	(vi0_on),a
		ld	a,0x36
		out	(8),a
		ret
vi1_on:		db	0
vi1_frame:	db	0
vi2_on:		db	0
vi2_frame:	db	0
tune_on:	db	0
tone_frame:	db	0
vi0_on:		db	0
vi0_div:	dw	0xFFFF

; play_tune: нота B (период) -> счётчики 1 и 2 (голоса n и n-1), DE = 1530h (длительность, вместо ld de,1530h)
vec_note:	push	af
		push	hl
		ld	a,1
		ld	(tune_on),a
		ld	a,0x76			; счётчик 1, режим 3
		out	(8),a
		ld	a,b
		call	note_div
		ld	a,l
		out	(0x0A),a
		ld	a,h
		out	(0x0A),a
		ld	a,0xB6			; счётчик 2, режим 3
		out	(8),a
		ld	a,b
		dec	a
		call	note_div
		ld	a,l
		out	(0x09),a
		ld	a,h
		out	(0x09),a
		pop	hl
		pop	af
		ld	de,0x1530
		ret
; делитель голоса по периоду n (A): выход ZX переключается на каждом срабатывании голоса (раз в n итераций
; по 88 тактов) — полный период 2n итераций; n = 0 — 256 (как dec h в цикле). Таблица vi_note_tab.
note_div:	push	de
		ld	l,a
		ld	h,0
		add	hl,hl
		ld	de,vi_note_tab
		add	hl,de
		ld	e,(hl)
		inc	hl
		ld	d,(hl)
		ex	de,hl
		pop	de
		ret
; spr_pace (вместо ld a,(v_nobjs)): во время прокрутки задержки темпа нет (проход и так долгий)
V_NOBJS		equ	0xAF09
V_SCROLLDIR	equ	0xAF2B
vec_pace_n:	ld	a,(V_SCROLLDIR)
		and	a
		ld	a,6			; 6 объектов и больше — без задержки
		ret	nz
		ld	a,(V_NOBJS)
		ret

; начало blit_tile (rst 20h): HL = 0 или режим «без плиток» — выход из blit_tile
blit_guard:
		ld	a,h
		or	l
		jr	z,.skip
		ld	a,(noblit)		; обход палубы без вывода плиток (вертикальная прокрутка из BAND)
		and	a
		jr	nz,.skip
		ld	a,(hl)
		inc	hl
		ret
.skip:		pop	af			; адрес возврата в blit_tile
		ret				; -> в вызвавший blit_tile


; ---- вертикальная прокрутка из готовой полосы (приём из демо i8080) ----
; cam_step (E1A9: call deck_draw -> call vec_cam_draw). Для 0x1E/0x28 на первом шаге (v_scr_steps = 7) полоса 64 строки
; рисуется один раз при конечной камере в BAND; на каждом шаге deck_draw обходит палубу без вывода плиток
; (служебная работа — цвета столбцов, переменные — как в оригинале), затем 8 строк из BAND — в поле.
BAND		equ	0x1600			; 64 строки x 32 байта
G_DECK_DRAW	equ	0xBE38
G_CAM_ISO	equ	0xE69F + RELO
V_SCR_STEPS	equ	0xAF2C
V_CAM		equ	0xAF1C
V_SCR_DE	equ	0xAF34
T_COLATTR	equ	0xB024
STRIP_DST	equ	0xC1B8			; операнд ld de,t_field в strip_put
vec_cam_draw:	ld	a,(V_SCROLLDIR)
		cp	0x1E
		jr	z,.v
		cp	0x28
		jp	nz,G_DECK_DRAW
.v:		ld	a,(V_SCR_STEPS)
		cp	7
		call	z,vband_render
		ld	a,1
		ld	(noblit),a
		call	G_DECK_DRAW
		xor	a
		ld	(noblit),a
		ld	a,(V_SCROLLDIR)
		cp	0x28
		ld	a,(V_SCR_STEPS)		; k = 7..0
		ld	de,T_FIELD		; 0x28: строки полосы k*8 -> строки поля 0..7
		jr	z,.copy
		cpl				; 0x1E: строки полосы (7-k)*8 -> строки 144..151
		add	a,8
		ld	de,T_FIELD + 144*32
.copy:		add	a,a
		add	a,a
		add	a,a
		ld	l,a
		ld	h,0
		add	hl,hl
		add	hl,hl
		add	hl,hl
		add	hl,hl
		add	hl,hl
		ld	bc,BAND
		add	hl,bc
		ld	bc,256
		ldir
		ret

vband_render:	ld	hl,V_SCR_STEPS		; сохранить блок прокрутки, камеру, t_colattr
		ld	de,vb_save
		ld	bc,10
		ldir
		ld	hl,(V_CAM)
		ld	(vb_cam),hl
		ld	hl,T_COLATTR
		ld	de,vb_colattr
		ld	bc,32
		ldir
		ld	a,(V_SCR_DE)		; камера += 7 шагов
		ld	c,a
		add	a,a
		add	a,a
		add	a,a
		sub	c
		ld	hl,V_CAM
		add	a,(hl)
		ld	(hl),a
		ld	a,(V_SCR_DE+1)
		ld	c,a
		add	a,a
		add	a,a
		add	a,a
		sub	c
		inc	hl
		add	a,(hl)
		ld	(hl),a
		ld	a,(V_CAM)
		ld	c,a
		ld	a,(V_CAM+1)
		ld	b,a
		call	G_CAM_ISO
		ld	hl,vb_p28		; блок полосы 64 строки
		ld	a,(V_SCROLLDIR)
		cp	0x28
		jr	z,.p
		ld	hl,vb_p1e
.p:		ld	de,V_SCR_STEPS+1	; v_scr_steps оставить
		ld	bc,9
		ldir
		ld	a,(V_SCR_STEPS+5)	; R0 -> приёмник strip_put = BAND - R0*32
		ld	l,a
		ld	h,0
		add	hl,hl
		add	hl,hl
		add	hl,hl
		add	hl,hl
		add	hl,hl
		ex	de,hl
		ld	hl,BAND
		and	a
		sbc	hl,de
		ld	(STRIP_DST),hl
		call	G_DECK_DRAW
		ld	hl,T_FIELD
		ld	(STRIP_DST),hl
		ld	hl,vb_save		; вернуть всё
		ld	de,V_SCR_STEPS
		ld	bc,10
		ldir
		ld	hl,(vb_cam)
		ld	(V_CAM),hl
		ld	hl,vb_colattr
		ld	de,T_COLATTR
		ld	bc,32
		ldir
		ld	a,(V_CAM)
		ld	c,a
		ld	a,(V_CAM+1)
		ld	b,a
		jp	G_CAM_ISO
vb_p28:		db	0x20,0x58,0x40,0,0,0x03,0xFF,2,0xFE	; после v_scr_steps: wide, ybot, h, col, R0, mape, mapd, de, dd
vb_p1e:		db	0x20,0x58,0x40,0,88,0xED,0x15,0xFE,2
vb_save:	ds	10
vb_cam:		dw	0
vb_colattr:	ds	32
noblit:		db	0

; режим бога: F1 + F3 зажаты в момент старта игры из заставки (title_loop: call game_reset -> call god_start) —
; energy_check (call god_chk вместо ld a,(v_energy)) держит энергию и её предел полными, гибели нет
V_ENERGY	equ	0xAF93
V_ENERGY_MAX	equ	0xAFA9
G_GAME_RESET	equ	0xB87C
god_start:	ld	a,(vec_kb + 1)		; ряд 1 матрицы: F1 — бит 3, F3 — бит 5 (1 — нажата)
		and	0x28
		cp	0x28
		ld	a,0
		jr	nz,.s
		inc	a
.s:		ld	(god),a
		jp	G_GAME_RESET
god_chk:	ld	a,(god)
		and	a
		jr	z,.x
		ld	a,0x3F
		ld	(V_ENERGY_MAX),a
		ld	(V_ENERGY),a
.x:		ld	a,(V_ENERGY)
		ret
god:		db	0

; конец play_tune (вместо ei): счётчики 1, 2 замолчать
vec_tune_end:	xor	a
		ld	(tune_on),a
		ld	(vi1_on),a
		ld	(vi2_on),a
		ld	a,0x76
		out	(8),a
		ld	a,0xB6
		out	(8),a
		ei
		ret

; ---- цвет: вторая плоскость E000 (бит 0 индекса палитры) — класс точки ----
; Палитра на 4 цвета: P0/P1 — цвета фона (точка 0) класса 0/1, I0/I1 — цвета точек (точка 1). Для каждого атрибута ZX
; таблица SEL: 0 — класс 0 всей клетке, 1 — класс 1, 2 — класс 1 только фону (байт = ~точки), 3 — только точкам (= точки).
; По умолчанию цвета берутся из двух самых частых атрибутов (A, B); у поля — v_fieldattr / v_fieldattr2; у захвата — заданы.
CPLANE		equ	0xE0
vi_tone_tab	equ	0x5400			; делители тона эффектов по периоду (tools/port_build.py)
vi_note_tab	equ	0x5600			; делители нот мелодий по периоду (tools/port_build.py)
COUNTS		equ	0x5200			; 256 счётчиков по 2 байта (за перенесённым блоком, бывший теневой экран)
SEL		equ	0x5100			; 256 кодов класса по атрибуту
attrA:		db	0
attrB:		db	0
attrBv:		db	0
colP0:		db	0
colI0:		db	0
colP1:		db	0
colI1:		db	0
; класс клетки: A — атрибут, HL — адрес атрибута ZX (5800-5AFF); регистры сохраняются (кроме флагов)
cell_class:	push	bc
		push	de
		push	af
		push	hl
		ld	e,a
		ld	d,high(SEL)
		ld	a,(de)
		ld	b,a			; код класса
		ld	a,(in_game)		; в игре панель (адреса атрибутов 5A60..5AFF) — одним классом 0
		and	a
		jr	z,.ng
		ld	a,h
		cp	0x5A
		jr	nz,.ng
		ld	a,l
		cp	0x60
		jr	c,.ng
		ld	b,0
.ng:
		ld	a,l
		and	0x1F
		ld	c,a			; столбец
		ld	a,h
		and	3
		rlca
		rlca
		rlca
		ld	e,a
		ld	a,l
		rlca
		rlca
		rlca
		and	7
		or	e			; строка знакомест 0..23
		add	a,a
		add	a,a
		add	a,a
		ld	e,a
		ld	a,ROW0
		sub	e
		ld	l,a			; верхняя строка клетки в плоскостях
		ld	a,c
		add	a,PLANE
		ld	h,a			; точки
		add	a,CPLANE - PLANE
		ld	d,a			; классы
		ld	e,l
		ld	a,b
		cp	2
		jr	nc,.pix
		neg				; 0 -> 00, 1 -> FF
		REPT	8
		ld	(de),a
		dec	e
		ENDR
		jr	.done
.pix:		jr	z,.inv
		REPT	8			; 3: класс = точки
		ld	a,(hl)
		ld	(de),a
		dec	l
		dec	e
		ENDR
		jr	.done
.inv:		REPT	8			; 2: класс = ~точки
		ld	a,(hl)
		cpl
		ld	(de),a
		dec	l
		dec	e
		ENDR
.done:		pop	hl
		pop	af
		pop	de
		pop	bc
		ret

; цвета P0 I0 P1 I1 -> палитра и таблица SEL
pal_set:	ld	hl,vec_pal
		ld	b,0
.p:		ld	a,b			; индекс: бит 3 — точка, бит 0 — класс
		and	9
		ld	de,colP0
		jr	z,.pc
		ld	de,colI0
		cp	8
		jr	z,.pc
		ld	de,colP1
		cp	1
		jr	z,.pc
		ld	de,colI1
.pc:		ld	a,(de)
		ld	(hl),a
		inc	hl
		inc	b
		ld	a,b
		cp	16
		jr	nz,.p
		ld	a,3
		ld	(pal_left),a
		ld	hl,SEL			; коды по атрибутам
.s:		ld	c,l			; атрибут
		ld	a,c
		rrca
		rrca
		rrca
		and	7
		call	zxcol			; фон
		ld	b,0			; биты: 0 — фон может 0, 1 — фон может 1, 2 — точка может 0, 3 — точка может 1
		ld	d,a
		ld	a,(colP0)
		cp	d
		jr	nz,.s1
		set	0,b
.s1:		ld	a,(colP1)
		cp	d
		jr	nz,.s2
		set	1,b
.s2:		ld	a,c
		and	7
		push	bc
		call	zxcol			; точка
		pop	bc
		ld	d,a
		ld	a,(colI0)
		cp	d
		jr	nz,.s3
		set	2,b
.s3:		ld	a,(colI1)
		cp	d
		jr	nz,.s4
		set	3,b
.s4:		ld	a,(xf_noinv)		; захват: без инверсии (нет цвета точки — точка цветом проводов I0)
		and	a
		jr	nz,.s4n
		ld	a,c			; у ZX точка и фон одного цвета (скрытое) — без инверсии
		and	7
		ld	e,a
		ld	a,c
		rrca
		rrca
		rrca
		and	7
		cp	e
		jr	z,.s4n
		ld	a,b
		and	0x0C
		jr	nz,.s4n			; цвет точки есть среди точек
		ld	a,(colP0)
		cp	d
		ld	e,0			; фон -> класс 0 ...
		jr	z,.inv
		ld	a,(colP1)
		cp	d
		ld	e,2			; ... или класс 1 (бит 1 — класс фона)
		jr	nz,.s4n
.inv:		; инверсия: точки ZX показать цветом фона (их цвет), фон ZX — видимой точкой (I0, а если совпал — I1)
		push	hl
		ld	hl,colP0
		bit	1,e
		jr	z,.iv1
		ld	hl,colP1
.iv1:		ld	a,(colI0)
		cp	(hl)
		pop	hl
		jr	nz,.iv2
		set	0,e
.iv2:		; код с инверсией: класс по НЕ-точкам (фон) = e.1, по точкам = e.0 — но точки и фон меняются местами,
		; поэтому байт класса = (e.1 ? ~точки : 0) | (e.0 ? точки : 0) -> те же коды 0..3, только смысл обратный.
		; Вид: точки ZX (bm=1) — цвет I(e.0); фон ZX (bm=0) — цвет P(e.1) = цвет точки ZX.
		jp	.cd
.s4n:		; класс фона pc: 1, только если цвет фона есть лишь в классе 1; класс точки ic — так же
		ld	e,0			; бит 1 — pc, бит 0 — ic
		bit	0,b
		jr	nz,.f0
		bit	1,b
		jr	z,.f0
		set	1,e
.f0:		bit	2,b
		jr	nz,.i0
		bit	3,b
		jr	z,.i0
		set	0,e
.i0:		; видимость: показанный цвет точки = показанному цвету фона, а у ZX они разные — точку в другой класс
		ld	a,c
		and	7
		ld	d,a
		ld	a,c
		rrca
		rrca
		rrca
		and	7
		cp	d
		jr	z,.same			; у ZX точка и фон одного цвета — найти в палитре такую же пару
		push	hl
		ld	hl,colP0
		bit	1,e
		jr	z,.vp
		ld	hl,colP1
.vp:		ld	d,(hl)			; показанный фон
		ld	hl,colI0
		bit	0,e
		jr	z,.vi
		ld	hl,colI1
.vi:		ld	a,(hl)
		pop	hl
		cp	d
		jr	nz,.vis
		ld	a,e
		xor	1
		ld	e,a
		jr	.vis
.same:		; пары (класс фона, класс точки) с одинаковым цветом: 00, 11, 10, 01 — первая найденная
		push	hl
		ld	a,(colP0)
		ld	d,a
		ld	a,(colI0)
		cp	d
		ld	e,0
		jr	z,.sf
		ld	a,(colP1)
		ld	d,a
		ld	a,(colI1)
		cp	d
		ld	e,3
		jr	z,.sf
		ld	a,(colI0)
		cp	d
		ld	e,2
		jr	z,.sf
		ld	a,(colP0)
		ld	d,a
		ld	a,(colI1)
		cp	d
		ld	e,1
		jr	z,.sf
		ld	e,0
.sf:		pop	hl
		jr	.cd
.vis:		; фон «свободен» (оба класса дают его цвет) — взять класс точки, клетка однородна
		bit	0,b
		jr	z,.cd
		bit	1,b
		jr	z,.cd
		res	1,e
		bit	0,e
		jr	z,.cd
		set	1,e
.cd:		ld	a,e			; (pc, ic): 00 -> 0, 11 -> 1, 10 -> 2, 01 -> 3
		cp	3
		jr	nz,.c1
		ld	a,1
		jr	.k
.c1:		cp	1
		jr	nz,.k
		ld	a,3
.k:		ld	(hl),a
		inc	l
		jp	nz,.s
		ret

; цвета из атрибутов A, B (B нет — те же, что A)
cols_from_ab:	ld	a,(attrA)
		ld	c,a
		rrca
		rrca
		rrca
		and	7
		call	zxcol
		ld	(colP0),a
		ld	a,c
		and	7
		call	zxcol
		ld	(colI0),a
		ld	a,(attrBv)
		and	a
		jr	z,.nob
		ld	a,(attrB)
		ld	c,a
.nob:		ld	a,c
		rrca
		rrca
		rrca
		and	7
		call	zxcol
		ld	(colP1),a
		ld	a,c
		and	7
		call	zxcol
		ld	(colI1),a
		ld	a,(in_game)		; в игре — нет: клетки пола должны быть однородными (спрайты)
		and	a
		jr	nz,.np
		ld	a,(colP0)		; фон у A и B один — второй цвет фона отдать панели (строки 19..23)
		ld	b,a
		ld	a,(colP1)
		cp	b
		call	z,panel_paper
.np:
		jp	pal_set
; самый частый в панели цвет фона, отличный от P0 -> colP1 (счётчики по атрибуту: фон + яркость, 16 корзин)
panel_paper:	ld	hl,pp_cnt
		ld	b,16
.z:		ld	(hl),0
		inc	hl
		djnz	.z
		ld	hl,0x5800 + 19*32
		ld	b,5*32
.c:		ld	a,(hl)
		rrca
		rrca
		rrca
		and	0x0F			; фон (б0-2) и яркость (б3)
		push	hl
		ld	e,a
		ld	d,0
		ld	hl,pp_cnt
		add	hl,de
		inc	(hl)
		pop	hl
		inc	hl
		djnz	.c
		ld	hl,pp_cnt
		ld	c,0			; номер
		ld	de,0			; D — лучший номер, E — лучший счёт
.m:		ld	a,(hl)
		cp	e
		jr	c,.n
		jr	z,.n
		push	de
		push	bc
		ld	a,c
		and	7
		bit	3,c
		ld	c,0
		jr	z,.nb
		ld	c,0x40
.nb:		call	zxcol
		pop	bc
		pop	de
		ld	b,a
		ld	a,(colP0)
		cp	b
		jr	z,.n
		ld	a,(hl)
		ld	e,a
		ld	d,c
		ld	a,b
		ld	(pp_col),a
.n:		inc	hl
		inc	c
		ld	a,c
		cp	16
		jr	nz,.m
		ld	a,e
		and	a
		ret	z
		ld	a,(pp_col)
		ld	(colP1),a
		ret
pp_cnt:		ds	16
pp_col:		db	0

; классы всех клеток экрана
reclass_all:	ld	hl,0x5800
		ld	bc,768
.c:		ld	a,(hl)
		call	cell_class
		inc	hl
		dec	bc
		ld	a,b
		or	c
		jr	nz,.c
		ret

; мини-игра захвата (xf_restart: call attr_rects в C721 -> call vec_xf_attr): цвета заданы —
; фон красный и жёлтый, точки чёрные и синие (провода, ряды центра, импульсы синей стороны)
vec_xf_attr:	call	vec_attr_rects
		ld	a,0x55			; красный (как zxcol: не яркий)
		ld	(colP0),a
		xor	a			; чёрный
		ld	(colI0),a
		ld	a,0x6D			; жёлтый (не яркий)
		ld	(colP1),a
		ld	a,0x91			; синий (не яркий)
		ld	(colI1),a
		ld	a,1
		ld	(xf_noinv),a
		call	pal_set
		xor	a
		ld	(xf_noinv),a
		call	xf_skin
		ld	a,1
		ld	(pal_lock),a
		ld	(xf_on),a		; захват: палитру по атрибутам больше не пересчитывать (vec_attr_rects)
		jp	reclass_all
; палитра показа по классу противника (v_obj_p2 б0–2): классы клеток считаны по цветам выше (как у ZX), здесь
; только цвета на экране — 4 байта на класс: P0 фон, I0 провода, P1 «жёлтая» сторона, I1 «синяя» (%BBGGGRRR)
V_OBJ_P2	equ	0xAF84
xf_skin:	ld	a,(V_OBJ_P2)
		and	7
		add	a,a
		add	a,a
		ld	e,a
		ld	d,0
		ld	hl,xf_skins
		add	hl,de
		ld	b,(hl)			; P0
		inc	hl
		ld	d,(hl)			; I0
		inc	hl
		ld	c,(hl)			; P1
		inc	hl
		ld	e,(hl)			; I1
		ld	hl,vec_pal		; индекс: бит 3 — точка, бит 0 — класс
		ld	a,4
.p:		ld	(hl),b
		inc	hl
		ld	(hl),c
		inc	hl
		dec	a
		jr	nz,.p
		ld	a,4
.i:		ld	(hl),d
		inc	hl
		ld	(hl),e
		inc	hl
		dec	a
		jr	nz,.i
		ret
xf_noinv:	db	0
xf_on:		db	0			; идёт захват (vec_xf_attr .. vec_cls / vec_cls_attr / vec_scr_copy_end)
xf_skins:	db	0x10,0xA4,0x3F,0xC7	; 0 тёмно-зелёный, серые провода, жёлтый, сиреневый
		db	0x02,0xA4,0x2F,0xF0	; 1 тёмно-красный, серые провода, золото, голубой
		db	0x40,0xFF,0x3F,0x07	; 2 тёмно-синий, белые провода, жёлтый, алый
		db	0x00,0xA4,0x3F,0xC7	; 3 чёрный, серые провода, жёлтый, сиреневый
		db	0x07,0xFF,0x3F,0xC0	; 4 ярко-красный, белые провода, жёлтый, синий
		db	0x43,0xA4,0x3E,0xE8	; 5 фиолетовый, серые провода, лимон, бирюза
		db	0x52,0xFF,0x3F,0xF8	; 6 серый, белые провода, жёлтый, голубой
		db	0xA4,0x00,0x1F,0xC0	; 7 светло-серый, чёрные провода, оранжевый, синий

; rst 18h: (HL) <- A (B96F: <- C; D3C2/D402: <- байт после rst, он пропускается)
attr_hl:	ld	(ah_val),a
		ld	(ah_hl),hl
		pop	hl			; адрес возврата
		push	af
		ld	a,l
		cp	0x70
		jr	nz,.s2
		ld	a,h
		cp	0xB9
		jr	nz,.s2
		ld	a,c			; menu_controls: ld (hl),c
		ld	(ah_val),a
		jr	.go
.s2:		ld	a,l
		cp	0xC3
		jr	nz,.s3
		ld	a,h
		cp	0xD3
		jr	z,.imm
.s3:		ld	a,l
		cp	0x03
		jr	nz,.go
		ld	a,h
		cp	0xD4
		jr	nz,.go
.imm:		ld	a,(hl)			; ld (hl),47h: значение — следующий байт
		inc	hl
		ld	(ah_val),a
.go:		ld	(ah_ret),hl
		ld	hl,(ah_hl)
		ld	a,(ah_val)
		call	attr_promote
		ld	(hl),a
		call	cell_class
		call	promo_done
		pop	af
		ld	hl,(ah_ret)
		push	hl
		ld	hl,(ah_hl)
		ret
ah_val:		db	0
ah_hl:		dw	0
ah_ret:		dw	0
; rst 28h: (DE) <- A
attr_de:	push	hl
		ld	h,d
		ld	l,e
		call	attr_promote
		ld	(hl),a
		call	cell_class
		call	promo_done
		pop	hl
		ret

; курсор атрибутом (A — новый атрибут, HL — адрес): если на экране клетка с ним выглядит так же, как со старым
; атрибутом, а цвета ZX у них разные — сделать новый атрибут вторым (B) и пересчитать палитру. Не в игре и не в захвате
; (pal_lock). Регистры сохраняются.
attr_promote:	push	af
		push	bc
		push	de
		push	hl
		ld	c,a			; новый
		ld	a,(pal_lock)
		and	a
		jr	nz,.x
		ld	a,(hl)
		ld	b,a			; старый
		cp	c
		jr	z,.x
		ld	a,b
		xor	c
		and	0x7F			; без мигания
		jr	z,.x
		ld	a,b
		call	shown
		push	hl			; вид старого
		ld	a,c
		call	shown
		pop	de
		and	a
		sbc	hl,de
		jr	nz,.x			; вид разный — курсор и так виден
		ld	a,c
		ld	(attrB),a
		ld	a,1
		ld	(attrBv),a
		call	cols_from_ab
		ld	a,1
		ld	(promo_pend),a		; классы всех клеток — после записи (в конце кадра)
.x:		pop	hl
		pop	de
		pop	bc
		pop	af
		ret
; вид атрибута A: H = цвет фона, L = цвет точки (по коду SEL и палитре)
shown:		ld	e,a
		ld	d,high(SEL)
		ld	a,(de)
		ld	hl,colP0
		ld	de,colI0
		cp	1
		jr	nz,.s2
		ld	hl,colP1
		ld	de,colI1
		jr	.s
.s2:		cp	2
		jr	nz,.s3
		ld	hl,colP1
		jr	.s
.s3:		cp	3
		jr	nz,.s
		ld	de,colI1
.s:		ld	a,(de)
		ld	l,(hl)
		ld	h,l
		ld	l,a
		ret
promo_done:	push	af
		ld	a,(promo_pend)
		and	a
		jr	z,.x
		xor	a
		ld	(promo_pend),a
		push	bc
		push	hl
		call	reclass_all
		pop	hl
		pop	bc
.x:		pop	af
		ret
pal_lock:	db	0
in_game:	db	0
promo_pend:	db	0

; cls_attr (вход B2E7 -> jp vec_cls_attr): A во все атрибуты строк 0..18, затем пересчёт палитры и классов
vec_cls_attr:	push	af
		xor	a
		ld	(pal_lock),a
		ld	(in_game),a
		ld	(xf_on),a
		pop	af
		ld	hl,0x5800
		ld	(hl),a
		ld	de,0x5801
		ld	bc,0x025F
		ldir
		jp	attr_full

; attr_rects (вход B5BC -> jp vec_attr_rects): как в оригинале, с классом клеток; много клеток — полный пересчёт
V_AR_W		equ	0xB5EB
V_AR_PTR	equ	0xB5EC
vec_attr_rects:	ld	a,0
		ld	(ar_cells),a
.rect:		ld	a,(hl)
		cp	0xFF
		jr	z,.end
		ld	b,a
		ld	(V_AR_W),a
		inc	hl
		ld	c,(hl)
		inc	hl
		ld	e,(hl)
		inc	hl
		ld	d,(hl)
		inc	hl
		ld	a,(hl)
		inc	hl
		ld	(V_AR_PTR),hl
		ex	de,hl
		ld	d,a			; цвет
		ld	a,0x20
		sub	b
		ld	e,a
.row:		ld	a,(V_AR_W)
		ld	b,a
		ld	a,d
.cell:		ld	(hl),a
		call	cell_class
		inc	hl
		push	af
		ld	a,(ar_cells)
		inc	a
		jr	z,.sat
		ld	(ar_cells),a
.sat:		pop	af
		djnz	.cell
		ld	d,0
		add	hl,de
		ld	d,a
		dec	c
		jr	nz,.row
		ld	hl,(V_AR_PTR)
		jr	.rect
.end:		ld	a,(ar_cells)
		cp	40
		ret	c
		ld	a,(xf_on)		; в захвате цвета заданы (xf_skin) — классы клеток уже записаны выше
		and	a
		ret	nz
		jp	attr_full
ar_cells:	db	0
fc_mixed:	db	0
fc_sp:		dw	0

; после атрибутной части scr_copy: классы клеток поля (строки 0..18) — атрибуты A/B не пересчитываются
vec_scr_copy_end:
		xor	a
		ld	(xf_on),a
		inc	a
		ld	(pal_lock),a
		ld	(in_game),a
		ld	a,(0xB044)		; v_fieldattr — вне пола (класс 0)
		ld	b,a
		ld	a,(0xB045)		; v_fieldattr2 — пол (класс 1)
		ld	c,a
		ld	a,(attrA)
		cp	b
		jr	nz,.np
		ld	a,(attrB)
		cp	c
		jr	z,.same
.np:		ld	a,b
		ld	(attrA),a
		ld	a,c
		ld	(attrB),a
		sub	b
		jr	z,.one
		ld	a,1
.one:		ld	(attrBv),a
		call	cols_from_ab
		ld	hl,0x5800 + 19*32	; палитра сменилась — классы панели (строки 19..23) по новой таблице
		ld	bc,5*32
.pn:		ld	a,(hl)
		call	cell_class
		inc	hl
		dec	bc
		ld	a,b
		or	c
		jr	nz,.pn
.same:		; классы клеток поля (строки 0..18) по столбцам, через стек: клетка — 4 push (коды 0/1);
		; коды 2/3 (класс по точкам) — после, общей cell_class
		xor	a
		ld	(fc_mixed),a
		ld	(fc_sp),sp
		ld	c,0			; столбец
.col:		di
		ld	a,c
		add	a,CPLANE
		ld	h,a
		ld	l,ROW0 + 1
		ld	sp,hl			; push пишет в строки ROW0, ROW0-1, ...
		ld	h,0x58
		ld	l,c			; атрибут строки 0 столбца c
		ld	b,19
.cell:		ld	e,(hl)
		ld	d,high(SEL)
		ld	a,(de)
		cp	2
		jr	c,.u
		ld	a,1
		ld	(fc_mixed),a
		xor	a
.u:		neg
		ld	d,a
		ld	e,a
		push	de
		push	de
		push	de
		push	de
		ld	de,32
		add	hl,de
		djnz	.cell
		ld	sp,(fc_sp)
		ei
		inc	c
		ld	a,c
		cp	32
		jr	nz,.col
		ld	a,(fc_mixed)
		and	a
		jr	z,contour
fc_fix:		ld	hl,0x5800		; есть клетки с классом по точкам — пересчитать их
		ld	bc,19*32
.c:		ld	a,(hl)
		push	de
		ld	e,a
		ld	d,high(SEL)
		ld	a,(de)
		pop	de
		cp	2
		ld	a,(hl)
		call	nc,cell_class
		inc	hl
		dec	bc
		ld	a,b
		or	c
		jr	nz,.c
		; дальше — контур пола

; контур пола: на границах пола (t_colattr) окно в 2 знакоместа красится по точкам. По столбцу точек от фона внутрь:
; пока чернила подряд — фон (класс 0), с первой бумажной точки — палуба (класс 1). У всех палуб бумага фона и пола
; одна, разница в чернилах — край пола идёт по контуру ножек и стенок, а не знакоместами
contour:	ld	a,(0xB044)
		ld	hl,0xB045
		cp	(hl)
		ret	z
		ld	hl,0xB024		; t_colattr: пары [начальная, конечная строка пола] на 2 столбца
		ld	c,0
.pair:		ld	e,(hl)
		inc	hl
		ld	d,(hl)
		inc	hl
		push	hl
		push	bc
		ld	a,e
		inc	a
		jr	z,.next			; FF — весь столбец фон
		ld	a,d
		and	a
		jr	z,.next			; 0 — весь фон
		inc	a
		jr	z,.top			; FF — пол до низа: только верхний край
		ld	a,e
		and	a
		jr	z,.bot			; 0 — пол от верха: только нижний край
		ld	a,d
		sub	e
		cp	2
		jr	c,.next			; пол в одно знакоместо — окна перекрылись бы, остаются клетки
.bot:		push	de
		ld	a,d			; снизу знакоместа s вверх на 16 строк
		add	a,a
		add	a,a
		add	a,a
		add	a,7
		ld	b,a
		ld	a,ROW0
		sub	b
		ld	l,a
		ld	a,c
		add	a,PLANE
		ld	h,a
		push	hl
		call	ct_up
		pop	hl
		inc	h
		call	ct_up
		pop	de
		pop	bc			; столбец (ct_up портит C)
		push	bc
.top:		ld	a,e			; сверху знакоместа f-1 вниз на 16 строк
		and	a
		jr	z,.next
		dec	a
		add	a,a
		add	a,a
		add	a,a
		ld	b,a
		ld	a,ROW0
		sub	b
		ld	l,a
		ld	a,c
		add	a,PLANE
		ld	h,a
		push	hl
		call	ct_dn
		pop	hl
		inc	h
		call	ct_dn
.next:		pop	bc
		pop	hl
		inc	c
		inc	c
		ld	a,c
		cp	32
		jr	nz,.pair
		ret
; HL — точка видимой плоскости; 16 строк вверх (ct_up) или вниз (ct_dn), класс = не (чернила подряд от начала).
; Первые 8 строк — знакоместо фона, пишутся все; дальше знакоместо пола (класс уже FF) — до первого обрыва во всех 8 точках
ct_up:		ld	a,h
		add	a,CPLANE - PLANE
		ld	d,a
		ld	e,l
		ld	c,0xFF
		REPT	8
		ld	a,(hl)
		and	c
		ld	c,a
		cpl
		ld	(de),a
		inc	l
		inc	e
		ENDR
		REPT	8
		ld	a,(hl)
		and	c
		ret	z
		ld	c,a
		cpl
		ld	(de),a
		inc	l
		inc	e
		ENDR
		ret
ct_dn:		ld	a,h
		add	a,CPLANE - PLANE
		ld	d,a
		ld	e,l
		ld	c,0xFF
		REPT	8
		ld	a,(hl)
		and	c
		ld	c,a
		cpl
		ld	(de),a
		dec	l
		dec	e
		ENDR
		REPT	8
		ld	a,(hl)
		and	c
		ret	z
		ld	c,a
		cpl
		ld	(de),a
		dec	l
		dec	e
		ENDR
		ret

; полный пересчёт: два самых частых атрибута -> палитра, затем классы всех 768 клеток
attr_full:	ld	hl,COUNTS
		ld	de,COUNTS+1
		ld	bc,511
		ld	(hl),0
		ldir
		ld	hl,0x5800
		ld	bc,768
.cnt:		push	hl
		ld	e,(hl)
		ld	d,0
		ld	hl,COUNTS
		add	hl,de
		add	hl,de
		inc	(hl)
		jr	nz,.nc
		inc	hl
		inc	(hl)
.nc:		pop	hl
		inc	hl
		dec	bc
		ld	a,b
		or	c
		jr	nz,.cnt
		call	.max			; A — самый частый
		ld	(attrA),a
		ld	l,a
		ld	h,0
		add	hl,hl
		ld	de,COUNTS
		add	hl,de
		xor	a
		ld	(hl),a
		inc	hl
		ld	(hl),a
		call	.max			; B — второй
		ld	(attrB),a
		ld	a,d
		or	e
		ld	a,1
		jr	nz,.hb
		xor	a
.hb:		ld	(attrBv),a
		call	cols_from_ab
		jp	reclass_all
; атрибут с наибольшим счётчиком -> A, его счётчик -> DE
.max:		ld	hl,COUNTS
		ld	de,0			; лучший счётчик
		ld	bc,0			; C — номер, B — лучший номер
.m:		push	hl
		ld	a,(hl)
		inc	hl
		ld	h,(hl)
		ld	l,a			; счётчик
		push	hl
		and	a
		sbc	hl,de
		pop	hl
		jr	c,.ms
		jr	z,.ms
		ex	de,hl
		ld	b,c
.ms:		pop	hl
		inc	hl
		inc	hl
		inc	c
		jr	nz,.m
		ld	a,b
		ret

; цвет ZX A (0..7) при атрибуте C (бит 6 — яркость) -> A = %BBGGGRRR; портит DE
zxcol:		push	hl			; цвет ZX A (0..7), яркость — бит 6 C -> %BBGGGRRR по таблице (портит DE)
		ld	e,a
		ld	a,c
		and	0x40
		rrca
		rrca
		rrca
		add	a,e
		ld	e,a
		ld	d,0
		ld	hl,zxcol_tab
		add	hl,de
		ld	a,(hl)
		pop	hl
		ret
; цвета ZX на Векторе — мягче спектрумовских (пастель): обычные 0..7, затем яркие; чёрный всегда чёрный.
; Все 14 цветов разные (классы клеток сопоставляются по точному совпадению); vec_xf_attr — те же значения
zxcol_tab:	db	0x00,0x91,0x55,0x94,0x6A,0xAA,0x6D,0xAD,0x00,0xDA,0x5F,0x9E,0x7B,0xFB,0x77,0xB6


; ---- вывод по месту ----
; адрес строки y (A) экрана ZX -> HL (столбец 0)
zx_rowaddr:	ld	h,a
		and	0x38
		rlca
		rlca
		ld	l,a
		ld	a,h
		and	7
		ld	b,a
		ld	a,h
		and	0xC0
		rrca
		rrca
		rrca
		or	b
		or	0x40
		ld	h,a
		ret

; строка y (A) экрана ZX, столбцы c (C) .. c+n-1 (n — B) -> плоскость (столбец < 32)
row_to_plane:	push	bc
		ld	(rtp_y),a
		push	bc
		call	zx_rowaddr
		pop	bc
		ld	a,(rtp_y)
		ld	e,a
		ld	a,ROW0
		sub	e
		ld	e,a			; строка плоскости
		ld	a,l
		add	a,c
		ld	l,a
		ld	a,PLANE
		add	a,c
		ld	d,a
.c:		ld	a,c
		cp	32
		jr	nc,.s
		ld	a,(hl)
		ld	(de),a
.s:		inc	l
		inc	d
		inc	c
		djnz	.c
		pop	bc
		ret
rtp_y:		db	0

; печать знака (print_cont, вместо ld de,(v_prn_pos) в B22B): знак HL (8 байт шрифта) сразу в плоскость,
; в клетку экрана ZX v_prn_pos; цикл ZX (B233..B250) пропускается. Теневой экран ZX больше не пишется.
V_PRN_POS	equ	0xB00E
G_PRN_AFTER	equ	0xB255			; после ld de,(v_prn_pos) в B251
vec_glyph:	ld	a,l			; знаки с B8 (русские буквы, адрес за t_font >= 73B9) — из ru_font (tools/ru_pack.py)
		sub	0xB9
		ld	a,h
		sbc	a,0x73
		jr	c,.lat
		ld	de,(ru_font_off)
		add	hl,de
.lat:		ld	de,(V_PRN_POS)
		ld	a,d
		cp	0x58			; как в оригинале: клетка в атрибутах — конец печати
		jr	c,.ok
		pop	af			; адрес возврата сюда
		ret				; -> из print_cont
.ok:		push	hl
		ld	a,d			; y верха клетки = (d & 0x18) << 3 | (e & 0xE0) >> 2
		and	0x18
		rlca
		rlca
		rlca
		ld	l,a
		ld	a,e
		and	0xE0
		rrca
		rrca
		or	l
		ld	l,a
		ld	a,ROW0
		sub	l
		ld	l,a			; строка плоскости
		ld	a,e
		and	0x1F
		add	a,PLANE
		ld	h,a
		pop	de			; DE = знак
		REPT	8
		ld	a,(de)
		ld	(hl),a
		inc	de
		dec	l
		ENDR
		ld	de,(V_PRN_POS)		; класс клетки по её атрибуту (зависит от точек)
		ld	a,d
		and	0x18
		rrca
		rrca
		rrca
		or	0x58
		ld	h,a
		ld	l,e
		ld	a,(hl)
		call	cell_class
		pop	af			; адрес возврата сюда (B22F)
		jp	G_PRN_AFTER

; spr_flush целиком (вход B424 -> jp vec_spr_flush): окно спрайта из буфера-полосы (4 байта на строку)
; сразу в плоскость. Отсечение и записи в переменные — как в оригинале (v_strip_row/col, v_tmp, v_spr_skip).
V_TMP		equ	0xAF06
V_SPR_SKIP	equ	0xAF0A
V_BLT_BUF	equ	0xAF12
vec_spr_flush:	ld	a,(V_STRIP_H)
		ld	b,a
		ld	a,(V_STRIP_ROW)
		ld	c,a
		cp	0x98
		jr	c,.vpos
		add	a,b			; строка «выше верха» (отрицательная)
		ret	nc
		ret	z
		ld	(V_TMP),a		; видимых строк
		ld	a,c
		neg
		ld	(V_SPR_SKIP),a
		xor	a
		ld	(V_STRIP_ROW),a
		jr	.hor
.vpos:		xor	a
		ld	(V_SPR_SKIP),a
		ld	a,b
		ld	(V_TMP),a
		add	a,c
		sub	0x98
		jr	c,.hor
		neg
		add	a,b
		ld	(V_TMP),a
.hor:		ld	a,(V_STRIP_COL)
		cp	0x20
		jr	c,.hpos
		add	a,4			; столбец левее края
		ret	nc
		ret	z
		ld	c,a			; видимых байт
		neg
		add	a,4
		ld	b,a			; пропустить слева
		xor	a
		ld	(V_STRIP_COL),a
		jr	.go
.hpos:		ld	b,0
		ld	c,4
		add	a,4
		sub	0x20
		jr	c,.go
		neg
		add	a,4
		ld	c,a
.go:		ld	a,(V_TMP)
		and	a
		ret	z
		ld	hl,(V_BLT_BUF)		; источник: буфер + пропуск слева + пропуск строк * 4
		ld	e,b
		ld	d,0
		add	hl,de
		ld	a,(V_SPR_SKIP)
		ld	e,a
		ex	de,hl
		add	hl,hl
		add	hl,hl
		add	hl,de
		ld	a,(V_STRIP_ROW)		; приёмник: столбец v_strip_col, строка ROW0 − y
		ld	e,a
		ld	a,ROW0
		sub	e
		ld	e,a
		ld	a,(V_STRIP_COL)
		add	a,PLANE
		ld	d,a
		ld	a,(V_TMP)
		ld	b,a
		ld	a,c
		cp	4
		jr	nz,.narrow
.row4:		push	de			; полная ширина — 4 байта на строку
		ld	a,(hl)
		inc	hl
		ld	(de),a
		inc	d
		ld	a,(hl)
		inc	hl
		ld	(de),a
		inc	d
		ld	a,(hl)
		inc	hl
		ld	(de),a
		inc	d
		ld	a,(hl)
		inc	hl
		ld	(de),a
		pop	de
		dec	e
		djnz	.row4
		ret
.narrow:	push	bc
		push	de
		push	hl
		ld	b,c
.nb:		ld	a,(hl)
		inc	hl
		ld	(de),a
		inc	d
		djnz	.nb
		pop	hl
		pop	de
		pop	bc
		inc	hl
		inc	hl
		inc	hl
		inc	hl
		dec	e
		djnz	.narrow
		ret

; scr_copy: поле t_field (32 x 152, построчно) -> плоскость, затем атрибуты оригиналом
vec_scr_copy:	ld	(vsc_sp),sp
		ld	hl,T_FIELD
		ld	(vsc_src),hl
		ld	a,ROW0			; строка плоскости
		ld	(vsc_row),a
		ld	c,19			; 19 блоков по 8 строк = 152
.blk:		di
		ld	sp,(vsc_src)
		ld	a,(vsc_row)
		ld	l,a
		ld	b,8
.r:		ld	h,PLANE
		REPT	16
		pop	de
		ld	(hl),e
		inc	h
		ld	(hl),d
		inc	h
		ENDR
		dec	l
		djnz	.r
		ld	(vsc_src),sp
		ld	sp,(vsc_sp)
		ei
		ld	a,l
		ld	(vsc_row),a
		dec	c
		jp	nz,.blk
		call	G_SCR_COPY_ATTR
		jp	vec_scr_copy_end
vsc_sp:		dw	0
vsc_src:	dw	0
vsc_row:	db	0

; cls_bitmap(A): строки 0..151 плоскости залить A (вместо экрана ZX)
vec_cls:	push	af
		ld	c,a
		xor	a
		ld	(xf_on),a		; новый экран — захват кончился
		ld	h,PLANE
.c:		ld	l,ROW0 - 151
		ld	b,152
.r:		ld	(hl),c
		inc	l
		djnz	.r
		inc	h
		ld	a,h
		cp	PLANE + 32
		jr	nz,.c
		pop	af
		ret				; теневой экран ZX не используется

; делитель тона по периоду h эффекта: полупериод бипера ZX 27h + 29 тактов (h = 0 — 256) -> 1497600 * 2(27h+29) / 3500000


vec_pal:	db	PAPER,PAPER,PAPER,PAPER,PAPER,PAPER,PAPER,PAPER
		db	INK,INK,INK,INK,INK,INK,INK,INK
scr_col:	db	0
pal_left:	db	4
slice_div:	db	0
vec_kb:		ds	8
joy_rest:	db	0xFF			; джойстик «П» в покое (замер в boot)

; ряды ZX (FE, FD, FB, F7, EF, DF, BF, 7F) по 5 клавиш: [ряд Вектора, маска], FF — нет клавиши
; матрица Вектора: 7 SPC ^ ] \ [ Z Y X; 6 W V U T S R Q P; 5 O N M L K J I H; 4 G F E D C B A @;
; 3 / . = , ; : 9 8; 2 7 6 5 4 3 2 1 0; 1 F5 F4 F3 F2 F1 АР2 СТР ^\; 0 вниз вправо вверх влево ЗАБ ВК ПС ТАБ
; ряды ZX (FE, FD, FB, F7, EF, DF, BF, 7F) по 5 клавиш: [ряд Вектора, маска, ряд, маска] — основная и вторая клавиша
; Вектора (0xFF, 0 — нет). Вторые: 5 6 7 8 0 — стрелки и пробел (режим «2», курсор ZX).
zx_map:		db	0,0x08,0xFF,0, 7,0x04,0xFF,0, 7,0x01,0xFF,0, 4,0x08,0xFF,0, 6,0x40,0xFF,0	; CAPS(ЗАБ) Z X C V
		db	4,0x02,0xFF,0, 6,0x08,0xFF,0, 4,0x10,0xFF,0, 4,0x40,0xFF,0, 4,0x80,0xFF,0	; A S D F G
		db	6,0x02,0xFF,0, 6,0x80,0xFF,0, 4,0x20,0xFF,0, 6,0x04,0xFF,0, 6,0x10,0xFF,0	; Q W E R T
		db	2,0x02,0xFF,0, 2,0x04,0xFF,0, 2,0x08,0xFF,0, 2,0x10,0xFF,0, 2,0x20,0,0x10	; 1 2 3 4 5
		db	2,0x01,7,0x80, 3,0x02,0xFF,0, 3,0x01,0,0x40, 2,0x80,0,0x20, 2,0x40,0,0x80	; 0 9 8 7 6
		db	6,0x01,0xFF,0, 5,0x80,0xFF,0, 5,0x02,0xFF,0, 6,0x20,0xFF,0, 7,0x02,0xFF,0	; P O I U Y
		db	0,0x04,0xFF,0, 5,0x10,0xFF,0, 5,0x08,0xFF,0, 5,0x04,0xFF,0, 5,0x01,0xFF,0	; ENTER(ВК) L K J H
		db	7,0x80,0xFF,0, 0,0x02,0xFF,0, 5,0x20,0xFF,0, 5,0x40,0xFF,0, 4,0x04,0xFF,0	; SPACE SYM(ПС) M N B

; msg_find русской версии (B1ED -> jp vec_msg_find, tools/ru_pack.py): сообщения в двух таблицах — номера с msg_split
; во второй (адреса и границу пишет сборщик)
vec_msg_find:	ld	hl,msg_split
		cp	(hl)
		ld	hl,(msg_tab1)
		jp	c,0xB1F0		; list_nth
		ld	hl,msg_split
		sub	(hl)
		inc	a
		ld	hl,(msg_tab2)
		jp	0xB1F0
msg_tab1:	dw	0x77C0
msg_tab2:	dw	0
msg_split:	db	0
ru_font_off:	dw	0			; адрес русских букв − 73B9 (0 — нет)

glue_end:
		ASSERT	glue_end <= 0x1000
		ASSERT	SEL >= 0x5021 && COUNTS + 512 <= vi_tone_tab

		org	0x1000
		incbin	"../build/port/zxrom_0000.bin"	; ПЗУ ZX 0000-052F (rnd, CIRCUIT)
		ASSERT	$ <= 0x2000

		SAVEBIN	"../build/port/glue.bin",0,0x2000
