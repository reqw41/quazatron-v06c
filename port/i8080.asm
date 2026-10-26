; Добавки сборки i8080 (tools/port8080.py): замены команд Z80, которых нет на i8080, и blit_tile без exx/ex af.
; Код игры и склейки переводится из образа Z80 автоматически; сюда — только то, что пишется руками.
; Метки z_* — ячейки регистров Z80, которых нет у i8080. Флаги: S, Z, C как у Z80 (P/V и H игра не читает).

V_BLT_COLS	equ	0xAF04
V_BLT_SKIP	equ	0xAF05
V_BLT_X		equ	0xAF0E
V_BLT_Y		equ	0xAF10
V_BLT_BUF	equ	0xAF12
V_STRIP_HM1	equ	0xAF16
V_STRIP_H8	equ	0xAF17
V_BLT_CX	equ	0xAF1B

z_af2:		dw	0			; AF'
z_bc2:		dw	0			; BC'
z_de2:		dw	0			; DE'
z_hl2:		dw	0			; HL'
z_ix:		dw	0			; IX (склейка: опрос клавиатуры)
z_a:		db	0			; A на время сдвига другого регистра
z_t:		db	0
z_hls:		dw	0			; HL при ld (nn),sp / ld sp,(nn)
vfr80:		dw	0			; кадров с запуска
im2_dummy:	ds	3			; start пишет сюда jp isr (вектор IM 2 Z80 не нужен)

; кадровое прерывание (0x38 -> jp isr80): ячейки z_a, z_t, z_hls — на стеке на время обработчика (прерывание может прийти
; посреди переведённой команды, которая держит в них значение); обработчик склейки возвращается сюда своим ret
isr80:		push	af
		push	hl
		ld	hl,(vfr80)		; счёт кадров — срок прохода (pace80)
		inc	hl
		ld	(vfr80),hl
		ld	hl,(z_a)		; z_a, z_t
		push	hl
		ld	hl,(z_hls)
		push	hl
		ld	hl,.ret
		push	hl
		jp	g_isr_entry
.ret:		pop	hl
		ld	(z_hls),hl
		pop	hl
		ld	(z_a),hl
		pop	hl
		pop	af
		ret

; ldir / lddr: A и флаги сохраняются (у Z80 P/V = 0 — игра не читает)
; ldir / lddr: A и флаги сохраняются (у Z80 P/V = 0 — игра не читает). ldir от 64 байт — блоками по 16 через стек
; (ldir: pop из источника, lddr: push в приёмник) при di; между блоками SP свой и ei. Приёмник = источник ± 1
; (заливка) и хвост — по байту. Регистры на выходе как у Z80: HL, DE за последним байтом, BC = 0.
z_ldir:		push	af
		ld	a,b
		or	a
		jp	nz,.big
		ld	a,c			; (BC = 0 — 64К у Z80 — не бывает)
		cp	64
		jp	c,.s			; до 64 байт — по байту со счётом в C
.big:		inc	hl			; DE = HL + 1 — заливка (push сверху вниз)
		ld	a,l
		cp	e
		jp	nz,.ch0
		ld	a,h
		cp	d
.ch0:		dec	hl
		jp	z,.fill
.ch:		ld	a,b
		or	a
		jp	nz,.c64
		ld	a,c
		cp	16
		jp	c,.tail
.c64:		push	bc
		push	hl
		ld	hl,2
		add	hl,sp
		ld	(zl_sp),hl		; SP после push bc
		pop	hl			; HL — источник, DE — приёмник
		di
		ld	sp,hl
		ex	de,hl
		REPT	8
		pop	de
		ld	(hl),e
		inc	hl
		ld	(hl),d
		inc	hl
		ENDR
		ex	de,hl
		ld	hl,0
		add	hl,sp
		ld	(zl_src),hl
		ld	hl,(zl_sp)
		ld	sp,hl
		ei
		ld	hl,(zl_src)
		pop	bc
		ld	a,c
		sub	16
		ld	c,a
		ld	a,b
		sbc	a,0
		ld	b,a
		jp	.ch
.tail:		ld	a,c
		or	a
		jp	z,.x
.s:		ld	a,(hl)
		ld	(de),a
		inc	hl
		inc	de
		dec	c
		jp	nz,.s
		pop	af
		ret
.x:		pop	af
		ret
; заливка байтом (HL) с DE = HL + 1, BC ≥ 64: от конца DE + BC вниз — push по 32 байта при di, хвост — по байту
.fill:		ld	a,(hl)
		ex	de,hl
		add	hl,bc			; HL = конец
		push	hl
		ld	d,a
		ld	e,a
		ld	a,c
		rra
		jp	nc,.f0
		dec	hl			; нечётный счёт — байт сверху
		ld	(hl),e
		dec	bc
.f0:		ld	(zl_src),hl
		ld	hl,0
		add	hl,sp
		ld	(zl_sp),hl
.fc:		ld	a,b
		or	a
		jp	nz,.f64
		ld	a,c
		cp	32
		jp	c,.ft
.f64:		ld	hl,(zl_src)
		di
		ld	sp,hl
		REPT	16
		push	de
		ENDR
		ld	hl,0
		add	hl,sp
		ld	(zl_src),hl
		ld	hl,(zl_sp)
		ld	sp,hl
		ei
		ld	a,c
		sub	32
		ld	c,a
		ld	a,b
		sbc	a,0
		ld	b,a
		jp	.fc
.ft:		ld	hl,(zl_src)
		ld	a,c
		or	a
		jp	z,.fe
.ftl:		dec	hl
		ld	(hl),d
		dec	c
		jp	nz,.ftl
.fe:		pop	de			; DE = конец, HL = конец − 1, BC = 0 — как у Z80
		ld	h,d
		ld	l,e
		dec	hl
		ld	bc,0
		pop	af
		ret
z_lddr:		push	af			; после поля-кольца — только короткие копии (t_colattr): по байту
		ld	a,b
		or	a
		jp	nz,.l
		ld	a,c
		or	a
		jp	nz,.s
		jp	.l			; BC = 0 — 64К, как у Z80
.s:		ld	a,(hl)
		ld	(de),a
		dec	hl
		dec	de
		dec	c
		jp	nz,.s
		pop	af
		ret
.l:		ld	a,(hl)
		ld	(de),a
		dec	hl
		dec	de
		dec	bc
		ld	a,b
		or	c
		jp	nz,.l
.x:		pop	af
		ret
zl_sp:		dw	0
zl_src:		dw	0

; rld: (HL) <- (HL)<<4 | A&0F, A <- A&F0 | (HL)>>4; S, Z — по A, C сохраняется
z_rld:		push	bc
		push	de
		push	af
		ld	b,a
		ld	a,(hl)
		rlca
		rlca
		rlca
		rlca
		ld	c,a			; тетрады (HL) переставлены
		and	0xF0
		ld	d,a
		ld	a,b
		and	0x0F
		or	d
		ld	(hl),a
		ld	a,c
		and	0x0F
		ld	d,a
		ld	a,b
		and	0xF0
		or	d
		ld	b,a
		pop	af
		ld	a,b
		inc	a
		dec	a
		pop	de
		pop	bc
		ret

; ld a,r (rnd): регистра R у i8080 нет — xorshift16 (результат дальше смешивается с байтами ПЗУ ZX, как в оригинале)
z_ld_a_r:	push	hl
		ld	hl,(.s)
		ld	a,h
		rra
		ld	a,l
		rra
		xor	h
		ld	h,a
		ld	a,l
		rra
		ld	a,h
		rra
		xor	l
		ld	l,a
		xor	h
		ld	h,a
		ld	(.s),hl
		pop	hl
		ret
.s:		dw	0x6B3D

; blit_tile (B07D) на i8080: изображение HL — [столбцов], на столбец [x со знаком][y][режим|строк], байты строк.
; Как оригинал: те же переменные (v_blt_cols, v_blt_skip, v_blt_cx), тот же вывод в полосу (4 байта на строку).
; Самомодификация, как у ZX: пара кодов операции (cpl+and (hl) — стереть по маске, nop+or (hl) — наложить, nop+nop —
; записать) и вход в цепочку сдвигов (jp вместо jr со смещением). Вход: проверка HL = 0 и noblit — как blit_guard.
blit_tile_80:	ld	a,h
		or	l
		ret	z
		ld	a,(g_noblit)
		and	a
		ret	nz
		push	hl			; границы dx видимых столбцов (x = v_blt_x + dx + 7 в 0..26h): dx + 80h в LO..LO+W
		ld	hl,(V_BLT_X)
		ld	a,l
		add	a,7
		ld	(bt_x7+1),a		; младший байт x + 7 (у видимого столбца старший — 0)
		ld	a,0x80 - 7		; HL = 80h − (x + 7) — смещённое dx, при котором x = 0 (A — старший байт)
		sub	l
		ld	l,a
		ld	a,0
		sbc	a,h
		jp	nz,.neg
		ld	a,l			; 0..FF: LO = L, конец min(L + 26h, FF)
		ld	(bt_lo+1),a
		add	a,0x26
		jp	nc,.w
		ld	a,0xFF
		jp	.w
.neg:		inc	a
		jp	nz,.none		; меньше −100h или больше FFh — ни одного
		ld	a,l
		add	a,0x26
		jp	nc,.none		; весь отрезок ниже 0
		ld	l,a
		xor	a
		ld	(bt_lo+1),a
		ld	a,l
.w:		ld	hl,bt_lo+1
		sub	(hl)
		inc	a			; W + 1 (не больше 27h)
		jp	.wset
.none:		xor	a
.wset:		ld	(bt_w+1),a
		pop	hl
		ld	a,(hl)
		inc	hl
bt_col:		ld	(V_BLT_COLS),a
		ld	a,(hl)			; столбец вне полосы — сразу к следующему
		xor	0x80
bt_lo:		sub	0
bt_w:		cp	0
		jp	nc,bt_fskip
		ld	a,(hl)
		inc	hl
bt_x7:		add	a,0			; E = x (0..26h)
		ld	e,a
		and	7
bt_scmp:	cp	0xFF			; сдвиг как у прошлого столбца — маски и переходы уже записаны
		jp	z,.ssame
		ld	(bt_scmp+1),a
		ld	(bt_s),a
		ld	b,a
		push	hl			; маски сдвига: левый байт — младшие 7 − s бит повёрнутого байта, правый — остальные
		add	a,low bt_mtab
		ld	l,a
		ld	h,high bt_mtab
		ld	a,(hl)
		ld	(bt_m1+1),a
		ld	(bt_m4+1),a
		cpl
		ld	(bt_m2+1),a
		ld	(bt_m0+1),a
		pop	hl
		ld	a,b
		add	a,low bt_c1
		ld	(bt_j1+1),a
		ld	a,b
		add	a,low bt_c4
		ld	(bt_j4+1),a
		ld	a,b
		add	a,low bt_c0
		ld	(bt_j0+1),a
.ssame:		ld	a,(hl)
		inc	hl
		ld	d,a
		ld	a,(V_BLT_Y)
		add	a,d
		ld	d,a			; D = y
		ld	a,(hl)
		inc	hl
		ld	c,a
		and	0xC0
bt_mcmp:	cp	0xFF			; режим как у прошлого столбца — команды уже записаны
		jp	z,.msame
		ld	(bt_mcmp+1),a
		ld	b,0
		and	0x80
		jp	z,.m1
		ld	a,0xA6			; and (hl)
		ld	b,0x2F			; cpl
		jp	.mp
.m1:		ld	a,c
		and	0x40
		ld	a,0
		jp	nz,.mp			; A = 0, B = 0: nop, nop
		ld	a,0xB6			; or (hl)
.mp:		ld	(bt_o1+1),a
		ld	(bt_o2+1),a
		ld	(bt_o4+1),a
		ld	(bt_o0+1),a
		ld	(bt_oa+1),a
		ld	a,b
		ld	(bt_o1),a
		ld	(bt_o2),a
		ld	(bt_o4),a
		ld	(bt_o0),a
		ld	(bt_oa),a
.msame:		ld	a,c
		and	0x3F
		ld	c,a
		jp	z,bt_h0
		ld	a,(V_STRIP_HM1)
		cp	d
		jp	nc,.clip
		ld	a,d			; столбец начинается выше полосы
		add	a,c
		jp	nc,bt_skip
		jp	z,bt_skip
		ld	c,a
		ld	a,d
		cpl
		inc	a
		add	a,l
		ld	l,a
		ld	a,0
		adc	a,h
		ld	h,a
		ld	d,0
.clip:
		ld	a,(V_STRIP_H8)
		sub	d
		ld	b,a
		ld	a,c
		sub	b
		jp	nc,.c1
		ld	b,c
		xor	a
.c1:		ld	(V_BLT_SKIP),a
		ld	a,b
		ld	(bt_n),a		; строк вывести
		ld	a,e
		rra
		rra
		rra
		and	7
		ld	(V_BLT_CX),a
		ld	e,a
		ld	b,h			; BC = данные
		ld	c,l
		ld	a,d			; DE = полоса + строка * 4 + столбец
		add	a,a
		jp	c,bt_big
		add	a,a
		jp	c,bt_big
		add	a,e
		jp	c,bt_big
		ld	hl,(V_BLT_BUF)
		add	a,l
		ld	e,a
		ld	a,h
		adc	a,0
		ld	d,a
		jp	bt_dst
bt_big:		ld	l,d
		ld	h,0
		add	hl,hl
		add	hl,hl
		ld	d,0
		add	hl,de
		ex	de,hl
		ld	hl,(V_BLT_BUF)
		add	hl,de
		ex	de,hl
bt_dst:		ld	a,(bt_s)
		cp	7
		jp	z,bt_al
		dec	de
; сдвиг: байт данных повернуть влево на 7 − s (rlca, вход в цепочку по s) и разделить масками на два байта полосы
; (левый — старшие биты сдвинутого, правый — младшие). HL — полоса, BC — данные, D — строк, E — повёрнутый байт
bt_sh:		ex	de,hl
		ld	a,(bt_n)
		ld	d,a
		ld	a,(V_BLT_CX)
		and	a
		jp	z,bt_l0
		cp	4
		jp	z,bt_l4
bt_l1:		ld	a,(bc)
		inc	bc
bt_j1:		jp	bt_c1
bt_c1:		rlca
		rlca
		rlca
		rlca
		rlca
		rlca
		rlca
		ld	e,a
bt_m1:		and	0
bt_o1:		nop
		nop
		ld	(hl),a
		inc	hl
		ld	a,e
bt_m2:		and	0
bt_o2:		nop
		nop
		ld	(hl),a
		inc	hl
		inc	hl
		inc	hl
		dec	d
		jp	nz,bt_l1
bt_next:	ld	h,b
		ld	l,c
bt_next2:	ld	a,(V_BLT_SKIP)
		ld	c,a
bt_skip:	ld	d,0
		ld	e,c
		add	hl,de
		ld	a,(V_BLT_COLS)
		dec	a
		jp	nz,bt_col
		ret
bt_h0:		ld	a,(bt_o1)		; высота 0 — выход, как у Z80: B — код cpl режима (или 0), A = 0, Z
		ld	b,a
		xor	a
		ret
bt_fskip:	inc	hl			; как bt_skipcol + bt_skip, на выходе B = 0, C = E = высота, D = 0 (как у Z80)
		inc	hl
		ld	a,(hl)
		and	0x3F
		ld	c,a
		inc	hl
		add	a,l
		ld	l,a
		jp	nc,.n
		inc	h
.n:		ld	a,(V_BLT_COLS)
		dec	a
		jp	nz,bt_col
		ld	b,a
		ld	d,a
		ld	e,c
		ret
bt_skipcol:	inc	hl
		ld	a,(hl)
		and	0x3F
		ld	c,a
		inc	hl
		jp	bt_skip
; столбец 4: только левый байт
bt_l4:		ld	a,(bc)
		inc	bc
bt_j4:		jp	bt_c4
bt_c4:		rlca
		rlca
		rlca
		rlca
		rlca
		rlca
		rlca
bt_m4:		and	0
bt_o4:		nop
		nop
		ld	(hl),a
		inc	hl
		inc	hl
		inc	hl
		inc	hl
		dec	d
		jp	nz,bt_l4
		jp	bt_next
; столбец 0: только правый байт
bt_l0:		inc	hl
bt_l0r:		ld	a,(bc)
		inc	bc
bt_j0:		jp	bt_c0
bt_c0:		rlca
		rlca
		rlca
		rlca
		rlca
		rlca
		rlca
bt_m0:		and	0
bt_o0:		nop
		nop
		ld	(hl),a
		inc	hl
		inc	hl
		inc	hl
		inc	hl
		dec	d
		jp	nz,bt_l0r
		jp	bt_next
; без сдвига
bt_al:		ld	h,d
		ld	l,e
		ld	d,b
		ld	e,c
		ld	a,(bt_n)
		ld	b,a
bt_la:		ld	a,(de)
		inc	de
bt_oa:		nop
		nop
		ld	(hl),a
		inc	hl
		inc	hl
		inc	hl
		inc	hl
		dec	b
		jp	nz,bt_la
		ex	de,hl
		jp	bt_next2
bt_s:		db	0xFF			; сдвиг прошлого столбца
bt_n:		db	0
bt_mtab:	db	0x7F,0x3F,0x1F,0x0F,0x07,0x03,0x01,0x00	; 0xFF >> (s + 1)
		ASSERT	high bt_mtab == high (bt_mtab + 7)
		ASSERT	high bt_c1 == high (bt_c1 + 7) && high bt_c4 == high (bt_c4 + 7) && high bt_c0 == high (bt_c0 + 7)
