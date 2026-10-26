; Добавки сборки i8080, вторая часть (tools/port8080.py кладёт её в свою дыру): процедуры, переписанные ради скорости.
; Метки и ячейки первой части (port/i8080.asm) доступны; c_* — входы процедур склейки (build/port8080/gcode.asm).

; ---- клавиатура: матрица Вектора и ряды ZX — в прерывании (kbd_scan склейки), опрос in a,(c) (rst 10h) — выбор готового ----
; kbd_scan_80: матрица -> vec_kb (как в склейке); при смене — ряды ZX zx_rows80 (как zx_row) и стрелки/пробел для Kempston.
; Регистры на выходе — как у kbd_scan склейки (A — ряд 7, B = FE, HL = vec_kb + 8, флаги S=1 Z=0 C=0), DE и C сохраняются.
		ASSERT	high g_vec_kb == high (g_vec_kb + 7)
kbd_scan_80:	push	bc
		push	de
		ld	a,0x8A
		out	(0),a
		ld	hl,g_vec_kb
		ld	de,kb_prev80
		ld	b,0xFE
		ld	c,0			; C <> 0 — матрица сменилась
.row:		ld	a,b
		out	(3),a
		in	a,(2)
		cpl
		ld	(hl),a
		ex	de,hl
		cp	(hl)
		jp	z,.same
		ld	(hl),a
		inc	c
.same:		inc	hl
		ex	de,hl
		inc	hl
		ld	a,b
		rlca
		ld	b,a
		jp	c,.row
		ld	a,0x88			; порт 03h — сразу FF: он же регистр прокрутки, защёлкивается на 40-й строке кадра
		out	(0),a			; (пересчёт рядов ниже долгий — с ним экран прыгал на кадр)
		ld	a,0xFF
		out	(3),a
		ld	a,c
		and	a
		call	nz,kb_rebuild80
		pop	de
		pop	bc
		ld	b,0xFE
		ld	hl,g_vec_kb + 8
		ld	a,b
		or	a
		ld	a,(g_vec_kb + 7)
		ret
; ряды ZX из vec_kb по zx_map (как zx_row склейки) и стрелки + пробел -> биты Kempston
kb_rebuild80:	ld	hl,zx_rows80
		ld	(kb_dst80),hl
		ld	hl,g_zx_map
		ld	e,8
.r:		ld	d,0xFF
		ld	c,1
		ld	b,5
.k:		call	.key
		inc	hl
		inc	hl
		ld	a,(hl)
		cp	0xFF
		call	nz,.key
		inc	hl
		inc	hl
		ld	a,c
		add	a,a
		ld	c,a
		dec	b
		jp	nz,.k
		push	hl
		ld	hl,(kb_dst80)
		ld	(hl),d
		inc	hl
		ld	(kb_dst80),hl
		pop	hl
		dec	e
		jp	nz,.r
		ld	a,(g_vec_kb)		; стрелки: б6 вправо -> б0, б4 влево -> б1, б7 вниз -> б2, б5 вверх -> б3
		ld	b,a
		ld	c,0
		and	0x40
		jp	z,.a1
		inc	c
.a1:		ld	a,b
		and	0x10
		jp	z,.a2
		ld	a,c
		or	2
		ld	c,a
.a2:		ld	a,b
		and	0x80
		jp	z,.a3
		ld	a,c
		or	4
		ld	c,a
.a3:		ld	a,b
		and	0x20
		jp	z,.a4
		ld	a,c
		or	8
		ld	c,a
.a4:		ld	a,(g_vec_kb + 7)	; пробел — огонь
		and	0x80
		jp	z,.a5
		ld	a,c
		or	0x10
		ld	c,a
.a5:		ld	a,(g_vec_kb + 1)	; F1 и F3 вместе — тоже огонь (старт игры в режиме бога, god_start)
		and	0x28
		cp	0x28
		jp	nz,.a6
		ld	a,c
		or	0x10
		ld	c,a
.a6:		ld	a,c
		ld	(kemp_kb80),a
		ret
.key:		ld	a,(hl)			; HL -> [ряд Вектора, маска]; нажата -> сбросить бит C в D
		push	hl
		add	a,low g_vec_kb
		ld	l,a
		ld	h,high g_vec_kb
		ld	a,(hl)
		pop	hl
		inc	hl
		and	(hl)
		dec	hl
		ret	z
		ld	a,c
		cpl
		and	d
		ld	d,a
		ret
; in a,(c) ZX: C = 1F — Kempston (джойстик «П» + стрелки/пробел из kemp_kb80), иначе AND рядов ZX, выбранных нулями B
zx_in_c_80:	ld	a,c
		cp	0x1F
		jp	z,.kemp
		push	bc
		push	hl
		ld	hl,zx_rows80
		ld	c,0xFF
.r:		ld	a,b			; B крутится 8 раз — на выходе прежний
		rrca
		ld	b,a
		jp	c,.n
		ld	a,c
		and	(hl)
		ld	c,a
.n:		inc	hl
		ld	a,l
		cp	low (zx_rows80 + 8)
		jp	nz,.r
		ld	a,c
		or	0xE0
		pop	hl
		pop	bc
		and	a
		ret
.kemp:		push	bc			; джойстик «П» (отличие от покоя — нажата): б0 вправо, б1 влево, б2 вверх, б3 вниз, б6 огонь
		in	a,(0x06)
		ld	b,a
		ld	a,(g_joy_rest)
		xor	b
		ld	b,a
		and	0x30			; биты 4, 5 сдвинулись — порта нет, ничего не нажато
		jp	z,.k0
		ld	b,0
.k0:		ld	a,b
		and	0x03
		ld	c,a
		ld	a,b
		and	0x04
		jp	z,.k1
		ld	a,c
		or	0x08
		ld	c,a
.k1:		ld	a,b
		and	0x08
		jp	z,.k2
		ld	a,c
		or	0x04
		ld	c,a
.k2:		ld	a,b
		and	0x40
		jp	z,.k3
		ld	a,c
		or	0x10
		ld	c,a
.k3:		ld	a,(kemp_kb80)
		or	c
		pop	bc
		and	a
		ret
		ASSERT	high zx_rows80 == high (zx_rows80 + 8)
zx_rows80:	db	0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF
kb_prev80:	db	0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF	; не бывает (vec_kb после cpl) — первое прерывание пересчитает
kemp_kb80:	db	0
kb_dst80:	dw	0

; font_copy (DD9E): знак L шрифта p_font (8 байт) -> (DE); как у Z80 после ldir: HL, DE + 8, BC = 0, A сохраняется
P_FONT		equ	0x61BC
font_copy_80:	push	af
		ld	h,0
		add	hl,hl
		add	hl,hl
		add	hl,hl
		push	de
		ex	de,hl
		ld	hl,(P_FONT)
		add	hl,de
		pop	de
		REPT	8
		ld	a,(hl)
		ld	(de),a
		inc	hl
		inc	de
		ENDR
		ld	bc,0
		pop	af
		ret

; vec_spr_flush склейки, полная ширина (.row4: HL — окно в полосе, 4 байта на строку, DE — плоскость: D = 80h + столбец,
; E — строка, B — строк): через стек — pop из полосы при di, строки змейкой (столбцы 0→3, затем 3→0).
; На выходе как у склейки: HL за окном, D, E − строк, B = 0, C = 4, A — последний байт.
spr_row4_80:	ex	de,hl
		ld	(sf_de),hl
		ex	de,hl
		push	hl
		ld	hl,2
		add	hl,sp
		ld	(sf_sp),hl
		pop	hl
		ld	a,b
		ld	(sf_n),a
		di
		ld	sp,hl
		ex	de,hl
.lp:		pop	bc
		pop	de
		ld	(hl),c
		inc	h
		ld	(hl),b
		inc	h
		ld	(hl),e
		inc	h
		ld	(hl),d
		dec	l
		dec	a
		jp	z,.end
		pop	bc
		pop	de
		ld	(hl),d
		dec	h
		ld	(hl),e
		dec	h
		ld	(hl),b
		dec	h
		ld	(hl),c
		dec	l
		dec	a
		jp	nz,.lp
.end:		ld	hl,0
		add	hl,sp
		ld	(sf_src),hl
		ld	hl,(sf_sp)
		ld	sp,hl
		ei
		ld	hl,(sf_de)
		ld	a,(sf_n)
		ld	b,a
		ld	a,l
		sub	b
		ld	l,a
		ex	de,hl
		ld	hl,(sf_src)
		dec	hl
		ld	a,(hl)
		inc	hl
		ld	bc,4
		ret
sf_de:		dw	0
sf_sp:		dw	0
sf_src:		dw	0
sf_n:		db	0


; ---- класс клетки (вторая плоскость): без лишних пересчётов ----
; attr_set80 (вместо ld (hl),a / call cell_class в attr_de и attr_hl): тот же атрибут — класс уже верный, ничего не делать
attr_set80:	push	af
		cp	(hl)
		jp	z,.same
		pop	af
		ld	(hl),a
		jp	cell_class_80
.same:		pop	af
		ret
; cell_class_px80 (вместо call cell_class в vec_glyph): знак меняет класс, только если он по точкам (коды SEL 2, 3)
SEL80		equ	0x5100
cell_class_px80:
		push	af
		push	de
		ld	e,a
		ld	d,high SEL80
		ld	a,(de)
		pop	de
		cp	2
		jp	nc,.do
		pop	af
		ret
.do:		pop	af
		jp	cell_class_80

; ldir / lddr длиной N <= 16 (перед ними ld bc,N): развёрнутая копия, вход z_ldir_N = конец − 4N; A и флаги —
; push af / pop af у места вызова; на выходе BC = 0, HL и DE — как у Z80
z_ldir16:	REPT	16
		ld	a,(hl)
		ld	(de),a
		inc	hl
		inc	de
		ENDR
		ld	bc,0
		ret
z_lddr16:	REPT	16
		ld	a,(hl)
		ld	(de),a
		dec	hl
		dec	de
		ENDR
		ld	bc,0
		ret
z_ldir_1	equ	z_ldir16 + 60
z_lddr_1	equ	z_lddr16 + 60
z_ldir_2	equ	z_ldir16 + 56
z_lddr_2	equ	z_lddr16 + 56
z_ldir_3	equ	z_ldir16 + 52
z_lddr_3	equ	z_lddr16 + 52
z_ldir_4	equ	z_ldir16 + 48
z_lddr_4	equ	z_lddr16 + 48
z_ldir_5	equ	z_ldir16 + 44
z_lddr_5	equ	z_lddr16 + 44
z_ldir_6	equ	z_ldir16 + 40
z_lddr_6	equ	z_lddr16 + 40
z_ldir_7	equ	z_ldir16 + 36
z_lddr_7	equ	z_lddr16 + 36
z_ldir_8	equ	z_ldir16 + 32
z_lddr_8	equ	z_lddr16 + 32
z_ldir_9	equ	z_ldir16 + 28
z_lddr_9	equ	z_lddr16 + 28
z_ldir_10	equ	z_ldir16 + 24
z_lddr_10	equ	z_lddr16 + 24
z_ldir_11	equ	z_ldir16 + 20
z_lddr_11	equ	z_lddr16 + 20
z_ldir_12	equ	z_ldir16 + 16
z_lddr_12	equ	z_lddr16 + 16
z_ldir_13	equ	z_ldir16 + 12
z_lddr_13	equ	z_lddr16 + 12
z_ldir_14	equ	z_ldir16 + 8
z_lddr_14	equ	z_lddr16 + 8
z_ldir_15	equ	z_ldir16 + 4
z_lddr_15	equ	z_lddr16 + 4
z_ldir_16	equ	z_ldir16 + 0
z_lddr_16	equ	z_lddr16 + 0

; print_cont (B1FF) целиком, со знаком сразу в плоскость (как vec_glyph склейки) и классом клетки только по точкам:
; HL — строка (длина, коды; FF — перевод строки), DE — адрес экрана ZX. Как у Z80: v_prn_pos/str/line, DE — следующая
; позиция, HL — указатель в строке, C = 0, B сохраняется, A и флаги на выходе — как у Z80. Клетка в атрибутах (D >= 58h) — конец.
V_PRN_POS8	equ	0xB00E
V_PRN_STR8	equ	0xB010
V_PRN_LINE8	equ	0xB263
PLANE8		equ	0x80
ROW08		equ	223
print_cont_80:	ld	a,(hl)
		and	a
		ret	z
		ld	c,a
pc_lp:		ex	de,hl
		ld	(V_PRN_POS8),hl
		ex	de,hl
		inc	hl
		ld	(V_PRN_STR8),hl
		ld	a,(hl)
		cp	0xFF
		jp	nz,pc_ch
		ex	de,hl			; перевод строки: две строки знаков вниз от начала строки
		ld	hl,(V_PRN_LINE8)
		call	zB070
		call	zB070
		ld	(V_PRN_LINE8),hl
		ex	de,hl
		jp	pc_nx
pc_ch:		push	bc
		ld	l,a
		ld	h,0
		add	hl,hl
		add	hl,hl
		add	hl,hl
		ex	de,hl
		ld	hl,(P_FONT)
		add	hl,de			; HL — знак в шрифте
		ld	a,l			; русские буквы (за t_font >= 73B9) — из ru_font
		sub	0xB9
		ld	a,h
		sbc	a,0x73
		jp	c,.lat
		ex	de,hl
		ld	hl,(g_ru_font_off)
		add	hl,de
.lat:		ld	b,h
		ld	c,l			; BC — знак
		ld	hl,(V_PRN_POS8)
		ex	de,hl			; DE — позиция
		ld	a,d
		cp	0x58
		jp	nc,pc_end
		and	0x18			; строка плоскости = ROW0 − ((d & 18h) << 3 | (e & E0h) >> 2)
		rlca
		rlca
		rlca
		ld	l,a
		ld	a,e
		and	0xE0
		rrca
		rrca
		or	l
		cpl
		add	a,ROW08 + 1
		ld	l,a
		ld	a,e
		and	0x1F
		add	a,PLANE8
		ld	h,a
		REPT	8
		ld	a,(bc)
		ld	(hl),a
		inc	bc
		dec	l
		ENDR
		ld	a,d			; атрибут клетки -> класс (если по точкам)
		rrca
		rrca
		rrca
		and	3
		or	0x58
		ld	h,a
		ld	l,e
		ld	c,(hl)			; класс клетки — только если он по точкам (коды SEL 2, 3)
		ld	b,high SEL80
		ld	a,(bc)
		cp	2
		jp	c,.nocls
		ld	a,c
		call	cell_class_80
.nocls:		pop	bc
		inc	e
		jp	nz,.ne
		ld	a,d
		add	a,8
		ld	d,a
.ne:		ld	a,0xB2			; как у Z80: A, флаги — от снятого склейкой адреса возврата B22E (C = 0)
		scf
		ccf
pc_nx:		ld	hl,(V_PRN_STR8)
		dec	c
		jp	nz,pc_lp
		ret
pc_end:		pop	bc			; как у Z80 (pop af склейки: A = B2h, флаги 2Eh — S = Z = C = 0)
		ld	a,1
		or	a
		ld	a,0xB2
		ret

; pal_set: zxcol по таблице (цвет ZX A, яркость — бит 6 C -> %BBGGGRRR; портит DE, как zxcol) и коды 80h..FFh = 00h..7Fh
zxcol_t80:	push	hl
		ld	e,a
		ld	a,c
		and	0x40
		rrca
		rrca
		rrca
		add	a,e
		ld	e,a
		ld	d,0
		ld	hl,zxcol_tab80
		add	hl,de
		ld	a,(hl)
		pop	hl
		ret
zxcol_tab80:	db	0x00,0x91,0x55,0x94,0x6A,0xAA,0x6D,0xAD,0x00,0xDA,0x5F,0x9E,0x7B,0xFB,0x77,0xB6	; = zxcol_tab склейки (пастель)
pal_hi80:	push	hl			; SEL 00..7F -> 80..FF; HL, BC, DE — как после цикла по 256 (L = 0, H — SEL)
		push	bc
		ld	hl,SEL80
		ld	de,SEL80 + 0x80
		ld	bc,0x80
		call	z_ldir
		pop	bc
		pop	hl
		ld	l,0
		ret

