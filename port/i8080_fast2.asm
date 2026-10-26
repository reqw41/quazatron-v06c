; Добавки сборки i8080, третья часть (своя дыра): темп хода (pace80) и классы клеток поля после перекладки (fcls80).
; Метки и константы первых двух частей доступны.

; ---- темп хода вместо задержки spr_pace (B = число объектов, как ld a,(v_nobjs); 6 и больше — у ZX без задержки).
; У ZX проход = работа + (6 − n) × 0,492 кадра (задержка с его прерыванием). Работа i8080 W длиннее в R ≈ 1,46 раза:
; ждём X = (6 − n) × 0,492 − W × (1 − 1/R) кадра (PACE_K = 256 × (1 − 1/R); R мерить: работа прохода i8080 / ZX) —
; проход длится, как у ZX. W — по счёту кадров vfr80 от конца прошлого прохода (концы — в случайных местах кадра,
; в среднем без сдвига), X — цикл в 1/256 кадра: 220 тактов + доля прерывания (~6%) = 234. Регистры, кроме A и флагов, сохраняются.
PACE_K		equ	81
pace80:		push	hl
		push	de
		push	bc
		ld	a,b
		cp	7
		jp	c,.n
		ld	a,6
.n:		add	a,a
		ld	e,a
		ld	d,0
		ld	hl,pace_d256
		add	hl,de
		ld	a,(hl)
		inc	hl
		ld	h,(hl)
		ld	l,a
		ld	(pace_x),hl		; задержка ZX в 1/256 кадра
		ld	hl,(pace_st)
		ex	de,hl
		ld	hl,(vfr80)
		ld	a,l
		sub	e
		ld	l,a
		ld	a,h
		sbc	a,d
		jp	nz,.no
		ld	a,l
		cp	16
		jp	nc,.no			; работа от 16 кадров — без ожидания
		ld	e,a
		ld	d,0
		ld	hl,0
		ld	b,PACE_K
.m:		ld	a,b			; HL = W × PACE_K (1/256 кадра)
		and	a
		jp	z,.m1
		rra
		ld	b,a
		jp	nc,.m0
		add	hl,de
.m0:		ex	de,hl
		add	hl,hl
		ex	de,hl
		jp	.m
.m1:		ex	de,hl
		ld	hl,(pace_x)
		ld	a,l
		sub	e
		ld	c,a
		ld	a,h
		sbc	a,d
		ld	b,a			; BC = X
		jp	c,.no
		or	c
		jp	z,.no
.s:		ex	(sp),hl			; 7 × 24 + 5 × 4 + 32 = 220 тактов
		ex	(sp),hl
		ex	(sp),hl
		ex	(sp),hl
		ex	(sp),hl
		ex	(sp),hl
		ex	(sp),hl
		REPT	5
		nop
		ENDR
		dec	bc
		ld	a,b
		or	c
		jp	nz,.s
.no:		ld	hl,(vfr80)
		ld	(pace_st),hl
		pop	bc
		pop	de
		pop	hl
		ret
pace_d256:	dw	756,630,504,378,252,126,0
pace_st:	dw	0
pace_x:		dw	0

; ---- классы клеток поля после перекладки (вместо .same в vec_scr_copy_end): столбец — 19 клеток по 4 push при di, код
; класса 0/1 -> байт 00/FF; код 2/3 (класс по точкам) — флаг fc_mixed (call пишет адрес возврата в ещё не залитые строки
; столбца), такие клетки потом считает cell_class склейки (fc_fix). Регистры на выходе — как у цикла склейки.
fcls80:		call	fcls_core
		ld	hl,0			; как у склейки: fc_sp — SP цикла, fc_mixed — флаг
		add	hl,sp
		ld	(g_fc_sp),hl
		ld	a,(fc80_mix)
		ld	(g_fc_mixed),a
		ld	bc,32
		ld	de,32
		ld	hl,0x5A7F
		and	a
		jp	z,c_contour
		jp	c_fc_fix
; строки 0..18 всех столбцов; клетки с кодом 2/3 — флаг fc80_mix (запись 0, их считает cell_class)
fcls_core:	ld	hl,0
		add	hl,sp
		ld	(fc80_sp),hl
		xor	a
		ld	(fc80_mix),a
fc80_c:		ld	(fc80_col),a
		ld	e,a
		add	a,0xE0			; CPLANE
		ld	h,a
		ld	l,ROW08 + 1
		di
		ld	sp,hl			; push пишет в строки ROW0, ROW0 − 1, ...
		ld	h,0x58
		ld	l,e
		ld	d,high SEL80
		ld	a,2			; строки 0..7, 8..15 (блок целиком), 16..18 (последние 3 клетки блока)
		ld	(fc80_n),a
fc80_b:		REPT	8
		ld	e,(hl)
		ld	a,(de)
		cp	2
		call	nc,fc80_mx
		rra
		sbc	a,a
		ld	b,a
		ld	c,a
		push	bc
		push	bc
		push	bc
		push	bc
		ld	a,l
		add	a,32
		ld	l,a
		ENDR
fc80_be:	inc	h			; 8 строк по 32 — L снова столбец, следующая треть атрибутов
		ld	a,(fc80_n)
		dec	a
		ld	(fc80_n),a
		jp	z,fc80_b + 5 * ((fc80_be - fc80_b) / 8)
		jp	p,fc80_b
		ld	hl,(fc80_sp)
		ld	sp,hl
		ei
		ld	a,(fc80_col)
		inc	a
		cp	32
		jp	nz,fc80_c
		ret
fc80_mx:	ld	a,1
		ld	(fc80_mix),a
		xor	a
		ret
fc80_col:	db	0
fc80_n:		db	0
fc80_mix:	db	0
fc80_sp:	dw	0

; ---- cell_class склейки: класс клетки в плоскость E000 по коду SEL. A — атрибут, HL — адрес атрибута (5800-5AFF);
; в игре панель (5A60..5AFF) — класс 0. Все регистры и флаги сохраняются, как у склейки
cell_class_80:	push	bc
		push	de
		push	af
		push	hl
		ld	e,a
		ld	d,high SEL80
		ld	a,(de)
		ld	b,a			; код класса
		ld	a,(g_in_game)
		and	a
		jp	z,.ng
		ld	a,h
		cp	0x5A
		jp	nz,.ng
		ld	a,l
		cp	0x60
		jp	c,.ng
		ld	b,0
.ng:		ld	a,l
		and	0x1F
		ld	c,a			; столбец
		ld	a,h			; верхняя строка клетки = ROW0 − ((h & 3) << 6 | (l & E0h) >> 2)
		and	3
		rrca
		rrca
		ld	e,a
		ld	a,l
		and	0xE0
		rrca
		rrca
		or	e
		cpl
		add	a,ROW08 + 1
		ld	l,a
		ld	e,a
		ld	a,c
		add	a,PLANE8
		ld	h,a			; точки
		add	a,0xE0 - PLANE8
		ld	d,a			; классы
		ld	a,b
		call	cls_put80
.done:		pop	hl
		pop	af
		pop	de
		pop	bc
		ret

; ---- attr_de склейки (rst 28h: (DE) <- A). Без pal_lock — как склейка: attr_promote, запись и класс, если атрибут
; другой, promo_done. При pal_lock (игра, захват; promo_pend тогда 0 — его ставит только attr_promote) — запись и класс
; клетки здесь же. После rst 28h жив только A (флаги портятся); BC, DE, HL сохраняются
attr_de_80:	push	hl
		ld	h,d
		ld	l,e
		push	af
		ld	a,(g_pal_lock)
		and	a
		jp	z,.slow
		pop	af
		cp	(hl)
		jp	z,.x
		ld	(hl),a
		push	de
		push	bc
		ld	e,a
		ld	d,high SEL80
		ld	a,(de)
		ld	b,a			; код класса
		ld	a,h			; в игре панель (5A60..5AFF) — класс 0
		cp	0x5A
		jp	nz,.ng
		ld	a,(g_in_game)
		and	a
		jp	z,.ng
		ld	a,l
		cp	0x60
		jp	c,.ng
		ld	b,0
.ng:		ld	a,h			; верхняя строка клетки = ROW0 − ((h & 3) << 6 | (l & E0h) >> 2)
		and	3
		rrca
		rrca
		ld	c,a
		ld	a,l
		and	0xE0
		rrca
		rrca
		or	c
		cpl
		add	a,ROW08 + 1
		ld	e,a
		ld	a,l
		and	0x1F
		add	a,PLANE8
		ld	l,e
		ld	h,a			; HL — точки, DE — классы
		add	a,0xE0 - PLANE8
		ld	d,a
		ld	a,b
		call	cls_put80
.done:		pop	bc
		pop	de
		ld	h,d
		ld	l,e
		ld	a,(hl)			; A — записанный атрибут
.x:		pop	hl
		ret
.slow:		pop	af
		call	c_attr_promote
		push	af
		cp	(hl)
		jp	z,.same
		pop	af
		ld	(hl),a
		call	cell_class_80
		push	af
.same:		pop	af
		pop	hl
		jp	c_promo_done

; xf_rowaddr (CBEE): адрес ячейки захвата — первый ряд стороны + (3 − ячеек) * 3 * шаг, затем (12 − рядов) раз
; scr_down8 (здесь — сразу, по шагам только у низа экрана). Как у Z80: v_xf_scr, DE — адрес, HL — сохранён (ячейка CED9), B — 0
V_XF_ROWS8	equ	0xCEB8
V_XF_CELLS8	equ	0xCEB9
V_XF_DIR8	equ	0xCEBC
V_XF_SCR8	equ	0xCEBE
V_XF_SCR08	equ	0xCECA
xf_rowaddr_80:	ld	(0xCED9),hl
		ld	a,(V_XF_ROWS8)		; рядов на 1 меньше прошлого вызова и ячеек столько же (обход xf_update) — от прошлого
		cp	12			; адреса на строку знаков вниз. Только k = 12 − рядов от 1 до 12 (прошлый k от 0 до 11).
		jp	nc,.full		; Первый ряд и шаг сторона задаёт в xf_side_setup — там кэш сбрасывается (xr_rows = 0)
		inc	a
		ld	hl,xr_rows
		cp	(hl)
		jp	nz,.full
		dec	a
		ld	(hl),a
		ld	a,(V_XF_CELLS8)
		dec	hl
		cp	(hl)
		jp	nz,.full
		ld	hl,(xr_res)
		ld	a,l
		add	a,0x20
		ld	l,a
		jp	nc,.d
		ld	a,h
		add	a,8
		cp	0x58
		jp	nc,.d
		ld	h,a
.d:		ld	(xr_res),hl
		ld	b,0
		jp	.r0
.full:		ld	a,(V_XF_CELLS8)
		ld	(xr_cells),a
		ld	a,(V_XF_ROWS8)
		ld	(xr_rows),a
		call	.calc
		ld	(xr_res),hl
.r0:		ld	(V_XF_SCR8),hl
		ex	de,hl
		ld	hl,(0xCED9)
		ret
.calc:		ld	hl,(V_XF_DIR8)
		ld	d,h
		ld	e,l
		add	hl,hl
		add	hl,de
		ex	de,hl			; DE = 3 * шаг
		ld	hl,(V_XF_SCR08)
		ld	a,(V_XF_CELLS8)
		ld	b,a
		ld	a,3
		sub	b
		jp	z,.c0
		ld	b,a
.c:		add	hl,de
		dec	b
		jp	nz,.c
.c0:		ld	a,(V_XF_ROWS8)
		ld	b,a
		ld	a,12
		sub	b
		ret	z
		cp	13			; k > 12 (ряд FFh — выход за таблицу) — по шагам
		jp	nc,.slow0
		push	hl			; k = 12 − рядов строк знаков вниз сразу: L + 20h * k, переносы — H + 8 каждый
		ld	e,a
		ld	d,0
		ex	de,hl
		add	hl,hl
		add	hl,hl
		add	hl,hl
		add	hl,hl
		add	hl,hl
		ld	a,e
		add	a,l
		ld	e,a
		ld	a,h
		adc	a,0
		add	a,a
		add	a,a
		add	a,a
		add	a,d
		cp	0x58
		jp	nc,.slow		; упор в низ экрана — по шагам, как scr_down8
		ld	d,a
		ex	de,hl
		pop	de
		ld	b,0
		ret
.slow:		pop	hl
.slow0:		ld	a,(V_XF_ROWS8)
		ld	b,a
		ld	a,12
		sub	b
		ld	b,a
.r:		ld	a,l			; scr_down8: строка знаков вниз (не ниже 5800)
		add	a,0x20
		ld	l,a
		jp	nc,.rn
		ld	a,h
		add	a,8
		cp	0x58
		jp	nc,.rn
		ld	h,a
.rn:		dec	b
		jp	nz,.r
		ret
xr_cells:	db	0xFF
xr_rows:	db	0
xr_res:		dw	0

; класс клетки по коду SEL A (0..3): HL — верхняя строка клетки в плоскости точек, DE — в плоскости классов (строки вниз —
; dec). 0/1 — байт 00/FF, 3 — точки, 2 — ~точки. Портит A, L, E
cls_put80:	cp	2
		jp	nc,.pix
		rra
		sbc	a,a
		REPT	8
		ld	(de),a
		dec	e
		ENDR
		ret
.pix:		jp	z,.inv
		REPT	8
		ld	a,(hl)
		ld	(de),a
		dec	l
		dec	e
		ENDR
		ret
.inv:		REPT	8
		ld	a,(hl)
		cpl
		ld	(de),a
		dec	l
		dec	e
		ENDR
		ret

; ---- reclass_all склейки: классы всех 768 клеток. Строки 0..18 — fcls_core (push по столбцам), панель 19..23 — по клетке
; (cell_class_80: в игре там класс 0), клетки 0..18 с классом по точкам — после, cell_class_80.
; Выход как у склейки: HL = 5B00, BC = 0, A = 0 (Z = 1, C = 0), DE сохранён
reclass_all_80:	push	de
		call	fcls_core
		ld	hl,0x5800 + 19 * 32
.pn:		ld	a,(hl)
		call	cell_class_80
		inc	l
		jp	nz,.pn
		ld	a,(fc80_mix)
		and	a
		jp	z,.x
		ld	hl,0x5800
		ld	d,high SEL80
.mx:		ld	e,(hl)
		ld	a,(de)
		cp	2
		jp	c,.mn
		ld	a,e
		call	cell_class_80
.mn:		inc	hl
		ld	a,h
		cp	0x5A
		jp	nz,.mx
		ld	a,l
		cp	0x60
		jp	nz,.mx
.x:		pop	de
		ld	hl,0x5B00
		ld	bc,0
		xor	a
		ret
