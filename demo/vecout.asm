; Вывод в экран Вектора: полоса -> столбцы плоскости SCR (замена C1A5) и сдвиги поля при прокрутке.
; Экран Вектора: адрес = SCR*256 + столбец*256 + строка_памяти, строка_памяти = TOP - строка_поля
; (0xFF — верх кадра). Поле оригинала: 32 байта x 152 строки.

; sub_c1a5h: полоса STRIP (4 страницы, строки с 0) -> экран: (AF14) — первый байтовый столбец,
; (AF15) — первая строка поля, (AF17) — строк (кратно 8); (AF2D) = 1 — ширина 2 байта
; (горизонтальная прокрутка), иначе 4. Через push: 24 такта на байт, прерывания запрещены.
vo_band:	db	0			; 1 — выводить в полосу BAND (вертикальная прокрутка), а не в экран
sub_c1a5h:
		ld	a,(vo_band)
		or	a
		jp	nz,vo_toband
		ld	hl,0
		add	hl,sp
		ld	(sh_savesp),hl
		ld	a,(0xaf2d)
		cp	1
		ld	b,2
		jp	z,vo_w
		ld	b,4
vo_w:		ld	a,(0xaf14)
		add	a,SCR
		ld	(vo_dst+1),a		; страница первого столбца экрана
		ld	a,(0xaf15)
		ld	c,a
		ld	a,TOP+1
		sub	c
		ld	(vo_dst),a		; строка памяти над первой строкой полосы
		ld	a,(0xaf17)
		rrca
		rrca
		rrca
		and	0x1F
		ld	c,a			; групп по 8 строк
		ld	a,STRIP
		ld	(vo_src),a
		di
vo_col:		ld	hl,(vo_dst)
		ld	sp,hl			; SP = приёмник (push пишет вниз — по строкам поля вниз)
		ld	a,(vo_src)
		ld	h,a
		ld	l,0			; HL = источник
		ld	a,c
vo_g:		REPT	4
		ld	d,(hl)
		inc	l
		ld	e,(hl)
		inc	l
		push	de
		ENDR
		dec	a
		jp	nz,vo_g
		ld	hl,vo_dst+1
		inc	(hl)
		ld	hl,vo_src
		inc	(hl)
		dec	b
		jp	nz,vo_col
		jp	sh_ret
vo_src:		db	0
vo_dst:		dw	0

; полоса STRIP -> BAND + столбец*64, строки 0..(AF17)-1; всегда 4 байта ширины
vo_toband:	ld	hl,0
		add	hl,sp
		ld	(sh_savesp),hl
		ld	a,(0xaf14)
		ld	l,a
		ld	h,0
		add	hl,hl
		add	hl,hl
		add	hl,hl
		add	hl,hl
		add	hl,hl
		add	hl,hl			; столбец * 64
		ld	de,BAND
		add	hl,de			; HL = приёмник (столбцы BAND по 64 байта, не пересекают страницу)
		ld	a,(0xaf17)
		rrca
		rrca
		rrca
		and	0x1F
		ld	c,a			; групп по 8 строк
		ld	b,STRIP
		di
vob_col:	ld	(vob_dst),hl
		ld	h,b
		ld	l,0
		ld	sp,hl			; SP = источник
		ld	hl,(vob_dst)		; HL = приёмник
		ld	a,c
vob_g:		REPT	4
		pop	de
		ld	(hl),e
		inc	l
		ld	(hl),d
		inc	l
		ENDR
		dec	a
		jp	nz,vob_g
		ld	hl,(vob_dst)
		ld	de,64
		add	hl,de
		inc	b
		ld	a,b
		cp	STRIP+4
		jp	nz,vob_col
		jp	sh_ret
vob_dst:	dw	0

; 8 строк полосы с A-й -> поле, строка памяти E и 7 ниже, во всех 32 столбцах
vb_copy:	ld	l,a
		ld	h,BAND/256
		ld	d,SCR
		ld	b,32
vbc_col:	push	hl
		push	de
		REPT	8
		ld	a,(hl)
		ld	(de),a
		inc	hl
		dec	e
		ENDR
		pop	de
		pop	hl
		inc	d
		ld	a,l
		add	a,64
		ld	l,a
		ld	a,h
		adc	a,0
		ld	h,a
		dec	b
		jp	nz,vbc_col
		ret

ROWS		equ	152
ROW0		equ	TOP-(ROWS-1)		; младший адрес поля в столбце (нижняя строка поля)

; Сдвиги — копированием через стек (прерывания запрещены на время работы, SP сохраняется).
; Горизонталь: столбец целиком (152 байта) pop из источника, запись через HL: 22 такта на байт.
; Вертикаль вверх: чтение через HL вниз, push в приёмник (вниз); вниз: pop + запись через HL вверх.

sh_savesp:	dw	0

; содержимое влево на 2 байта (направление 0x0A): столбец c <- c+2, c = 0..29
sh_left:	di
		ld	hl,0
		add	hl,sp
		ld	(sh_savesp),hl
		ld	c,SCR
		ld	b,30
shl_c:		ld	h,c
		inc	h
		inc	h
		ld	l,ROW0
		ld	sp,hl
		dec	h
		dec	h
		REPT	ROWS/2
		pop	de
		ld	(hl),e
		inc	l
		ld	(hl),d
		inc	l
		ENDR
		inc	c
		dec	b
		jp	nz,shl_c
		jp	sh_ret
; содержимое вправо на 2 байта (0x14): столбец c <- c-2, c = 31..2
sh_right:	di
		ld	hl,0
		add	hl,sp
		ld	(sh_savesp),hl
		ld	c,SCR+31
		ld	b,30
shr_c:		ld	h,c
		dec	h
		dec	h
		ld	l,ROW0
		ld	sp,hl
		inc	h
		inc	h
		REPT	ROWS/2
		pop	de
		ld	(hl),e
		inc	l
		ld	(hl),d
		inc	l
		ENDR
		dec	c
		dec	b
		jp	nz,shr_c
		jp	sh_ret
; содержимое вверх на 8 строк (0x1E): строка r <- r+8 (адрес TOP-r <- TOP-r-8), r = 0..143
sh_up:		di
		ld	hl,0
		add	hl,sp
		ld	(sh_savesp),hl
		ld	c,SCR
		ld	b,32
shu_c:		ld	h,c
		ld	l,TOP+1
		ld	sp,hl
		ld	l,TOP-8
		REPT	(ROWS-8)/2
		ld	d,(hl)
		dec	l
		ld	e,(hl)
		dec	l
		push	de
		ENDR
		inc	c
		dec	b
		jp	nz,shu_c
		jp	sh_ret
; содержимое вниз на 8 строк (0x28): строка r <- r-8 (адрес ROW0+k <- ROW0+8+k), k = 0..143
sh_down:	di
		ld	hl,0
		add	hl,sp
		ld	(sh_savesp),hl
		ld	c,SCR
		ld	b,32
shd_c:		ld	h,c
		ld	l,ROW0+8
		ld	sp,hl
		ld	l,ROW0
		REPT	(ROWS-8)/2
		pop	de
		ld	(hl),e
		inc	l
		ld	(hl),d
		inc	l
		ENDR
		inc	c
		dec	b
		jp	nz,shd_c
sh_ret:		ld	hl,(sh_savesp)
		ld	sp,hl
		ei
		ret

; sub_c044h: залить полосу 0xFF — 4 страницы STRIP, (AF17) строк (кратно 8), через push
sub_c044h:	ld	hl,0
		add	hl,sp
		ld	(sh_savesp),hl
		ld	a,(0xaf17)
		ld	l,a
		rrca
		rrca
		rrca
		and	0x1F
		ld	c,a			; групп по 8 строк
		ld	h,STRIP
		ld	de,0xFFFF
		ld	b,4
		di
sf_col:		ld	sp,hl
		ld	a,c
sf_g:		push	de
		push	de
		push	de
		push	de
		dec	a
		jp	nz,sf_g
		inc	h
		dec	b
		jp	nz,sf_col
		jp	sh_ret
