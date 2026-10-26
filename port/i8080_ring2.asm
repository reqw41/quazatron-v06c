; Добавки сборки i8080, пятая часть: bg_restore по полю-кольцу (port/i8080_ring.asm).

; bg_restore (C20D): окно спрайта из поля t_field (32 байта на строку) в полосу v_blt_buf (4 байта на строку) —
; push в полосу снизу вверх. Прерывание пишет ниже SP — в ещё не записанные строки полосы; последние 32 строки
; (128 байт до начала полосы) — при di. На выходе как у Z80: A = 0, BC = 1Dh, DE и HL за окном, v_tmp = 1.
V_STRIP_ROW8	equ	0xAF15
V_STRIP_COL8	equ	0xAF14
V_TMP8		equ	0xAF06
T_FIELD8	equ	0x2300
bg_restore_80:	ld	hl,(V_BLT_BUF)
		ex	de,hl
		ld	h,0
		ld	a,(V_STRIP_COL8)
		ld	c,a
		add	a,a
		sbc	a,a
		ld	b,a
		ld	a,(V_STRIP_ROW8)
		ld	l,a
		cp	0xC0
		jp	c,.pos
		cpl
		inc	a
		ld	l,a
		add	hl,hl
		add	hl,hl
		add	hl,de
		ex	de,hl
		ld	a,(V_STRIP_ROW8)
		ld	h,a
		ld	a,(V_STRIP_H8)
		add	a,h
		ret	z
		ret	nc
		xor	a
		ld	(rg_r0),a
		ld	a,(V_STRIP_ROW8)
		ld	h,a
		ld	a,(V_STRIP_H8)
		add	a,h
		ld	hl,0
		jp	.go
.pos:		ld	a,l
		ld	(rg_r0),a
		add	hl,hl
		add	hl,hl
		add	hl,hl
		add	hl,hl
		add	hl,hl
		ld	a,(V_STRIP_H8)
.go:		add	hl,bc
		ld	bc,T_FIELD8
		add	hl,bc			; HL — поле, DE — полоса, A — строк (0 — 256)
		ld	(bg_n),a
		push	hl
		ld	l,a
		ld	h,0
		and	a
		jp	nz,.n1
		inc	h
.n1:		push	hl
		add	hl,hl
		add	hl,hl
		add	hl,de
		ld	(bg_de),hl		; конец окна в полосе
		pop	hl
		add	hl,hl
		add	hl,hl
		add	hl,hl
		add	hl,hl
		add	hl,hl
		pop	de
		add	hl,de
		ld	(bg_hl),hl		; поле за окном (логический адрес)
		ex	de,hl
		ld	(rg_buf),hl		; начало окна в поле (логический)
		; кольцо: окно в поле (начало от 2300, байт 3 последней строки до 3600) и без разрыва кольца — как раньше;
		; через разрыв — bg_med; за полем — по байту (bg_slow)
		ld	a,(bg_n)
		and	a
		jp	z,bg_slow
		ld	a,h			; начало окна ниже поля — по байту
		cp	high RING_T
		jp	c,bg_slow
		ld	hl,(bg_hl)		; байт 3 последней строки (логический): за окном − 29
		ld	de,-29
		add	hl,de
		ld	a,h
		cp	high RING_END
		jp	nc,bg_slow		; за полем — по байту
		ex	de,hl
		ld	hl,(ring_off)
		add	hl,de			; + смещение кольца
		ld	a,h
		cp	high RING_END
		jp	c,bg_fast		; конец до 3600 — и начало тоже: разрыва нет
		push	hl
		ld	hl,(rg_buf)		; начало + смещение
		ex	de,hl
		ld	hl,(ring_off)
		add	hl,de
		ld	a,h
		pop	hl
		ld	de,-RING_N
		add	hl,de			; HL — конец в кольце
		cp	high RING_END
		jp	c,bg_med		; начало до 3600, конец после — разрыв
bg_fast:
		push	hl
		ld	hl,2
		add	hl,sp
		ld	(bg_sp),hl
		pop	de
		ld	bc,-29
		ld	hl,(bg_de)
		ld	a,(bg_n)
		sub	32			; строк при ei (над нижними 32)
		jp	z,.di
		jp	c,.di
		ld	sp,hl
		ex	de,hl
.r1:		ld	d,(hl)
		dec	hl
		ld	e,(hl)
		dec	hl
		push	de
		ld	d,(hl)
		dec	hl
		ld	e,(hl)
		push	de
		add	hl,bc
		dec	a
		jp	nz,.r1
		ld	a,32
		di
		jp	.r2
.di:		ld	a,(bg_n)
		di
		ld	sp,hl
		ex	de,hl
.r2:		ld	d,(hl)
		dec	hl
		ld	e,(hl)
		dec	hl
		push	de
		ld	d,(hl)
		dec	hl
		ld	e,(hl)
		push	de
		add	hl,bc
		dec	a
		jp	nz,.r2
bg_done:	ld	hl,(bg_sp)
		ld	sp,hl
		ei
bg_done2:	ld	a,1
		ld	(V_TMP8),a
		xor	a
		ld	bc,0x1D
		ld	hl,(bg_de)
		ex	de,hl
		ld	hl,(bg_hl)
		ret
bg_n:		db	0
bg_de:		dw	0
bg_hl:		dw	0
bg_sp:		dw	0
rg_r0:		db	0
rg_buf:		dw	0			; логический адрес начала окна в поле

; окно через разрыв кольца (при di): строки снизу вверх до разрыва и после него — подряд, как в быстром пути;
; строка, у которой сам разрыв внутри 4 байтов, — по байту; переход 2300 -> 3600 между ними
bg_med:		push	hl			; HL — байт 3 последней строки в кольце
		ld	hl,2
		add	hl,sp
		ld	(bg_sp),hl
		pop	hl
		push	hl			; k1 = строк целиком не ниже 2300: (HL − 2303) / 32 + 1 (HL < 2303 — 0)
		ld	de,-(RING_T + 3)
		add	hl,de
		ld	a,0
		jp	nc,.k
		add	hl,hl
		add	hl,hl
		add	hl,hl
		ld	a,h
		inc	a
.k:		ld	b,a
		ld	a,(bg_n)
		cp	b
		jp	nc,.k1
		ld	b,a			; не больше n
.k1:		sub	b
		ld	(bg_n2),a		; строк после
		pop	hl
		ex	de,hl
		ld	hl,(bg_de)
		di
		ld	sp,hl
		ex	de,hl
		ld	a,b
		and	a
		jp	z,.mid
.r1:		ld	d,(hl)			; до разрыва
		dec	hl
		ld	e,(hl)
		dec	hl
		push	de
		ld	d,(hl)
		dec	hl
		ld	e,(hl)
		push	de
		ld	de,-29
		add	hl,de
		dec	b
		jp	nz,.r1
.mid:		ld	a,(bg_n2)
		and	a
		jp	z,bg_done
		ld	b,a
		ld	a,h			; байт 3 строки уже ниже 2300 — разрыв между строками
		cp	high RING_T
		jp	c,.wr
		ld	d,(hl)			; разрыв внутри строки — по байту
		dec	hl
		ld	a,h
		cp	high RING_T
		jp	nc,.s1
		ld	hl,RING_END - 1
.s1:		ld	e,(hl)
		dec	hl
		ld	a,h
		cp	high RING_T
		jp	nc,.s2
		ld	hl,RING_END - 1
.s2:		push	de
		ld	d,(hl)
		dec	hl
		ld	a,h
		cp	high RING_T
		jp	nc,.s3
		ld	hl,RING_END - 1
.s3:		ld	e,(hl)
		push	de
		ld	de,-29			; дальше — уже за разрывом (3600 − ...)
		add	hl,de
		dec	b
		jp	z,bg_done
		jp	.r2
.wr:		ld	de,RING_N
		add	hl,de
.r2:		ld	d,(hl)			; после разрыва
		dec	hl
		ld	e,(hl)
		dec	hl
		push	de
		ld	d,(hl)
		dec	hl
		ld	e,(hl)
		push	de
		ld	de,-29
		add	hl,de
		dec	b
		jp	nz,.r2
		jp	bg_done
bg_n2:		db	0

; окно у края поля (столбец вне 0..28, строки за полем): по байту через ring_phys (вне поля — адрес как есть)
bg_slow:	ld	a,(bg_n)		; полоса: за окном − 4 * n (0 — 256)
		ld	l,a
		ld	h,0
		and	a
		jp	nz,.s1
		inc	h
.s1:		add	hl,hl
		add	hl,hl
		ex	de,hl
		ld	hl,(bg_de)
		ld	a,l
		sub	e
		ld	l,a
		ld	a,h
		sbc	a,d
		ld	h,a
		ex	de,hl			; DE — полоса
		ld	hl,(rg_buf)		; HL — поле (логический адрес начала окна)
		ld	a,(bg_n)
		ld	b,a
.r:		ld	c,4
.k:		push	hl
		call	ring_phys
		ld	a,(hl)
		pop	hl
		ld	(de),a
		inc	hl
		inc	de
		dec	c
		jp	nz,.k
		ld	a,l
		add	a,28
		ld	l,a
		jp	nc,.n
		inc	h
.n:		dec	b
		jp	nz,.r
		jp	bg_done2
