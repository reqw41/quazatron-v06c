; Демо прокрутки палубы Quazatron на ванильном Векторе-06Ц (i8080).
; Палуба рисуется переведённым кодом оригинала (BE38 и вызываемые, build/demo/render_8080.asm),
; вывод столбцов плитки — ручной (blit.asm), вывод полосы и сдвиги — vecout.asm.
; Данные игры (карта, графика, переменные) лежат на своих адресах ZX: снимок ОЗУ игры 0x61A9-0xDFFF.
; Стрелки: прокрутка, как в оригинале — 7 шагов по 16 точек по горизонтали, 8 шагов по 8 строк по вертикали.
; Замер: кадров (50 Гц) на полную отрисовку — qz_t_full, на последнюю прокрутку — qz_t_scroll.

		DEVICE	NOSLOT64K

SCR		equ	0xE0			; видимая плоскость 0xE000 (бит 0 индекса палитры)
TOP		equ	0xFF-24			; строка памяти для строки 0 поля
TBL		equ	0x40			; таблицы сдвигов 0x4000-0x4DFF (14 страниц)
STRIP		equ	0x58			; буфер-полоса раскладкой Вектора: 4 страницы 0x5800-0x5BFF
BAND		equ	0x5000			; полоса вертикальной прокрутки: 32 столбца x 64 строки (столбец*64 + строка)
INK		equ	0x38			; %BBGGGRRR: зелёный, как на ZX
PAPER		equ	0x00

		org	0
		di
		jp	start
		org	0x38
		jp	isr

		org	0x100
start:		di
		ld	sp,0x6000		; стек 0x5C00-0x5FFF
		ld	a,0x88
		out	(0),a
		xor	a
		out	(2),a
		ld	a,0xFF
		out	(3),a
		ld	a,0xC3			; RST 7 -> isr (для .rom с 0x100 ячейки 0x38 нет в файле)
		ld	(0x38),a
		ld	hl,isr
		ld	(0x39),hl
		ld	hl,0xE000		; очистить видимую плоскость
qz_clr:		ld	(hl),0
		inc	hl
		ld	a,h
		or	l
		jp	nz,qz_clr
		ei
		; полная отрисовка (параметры AF36 -> AF2C, как E003 оригинала)
		xor	a
		ld	(0xaf2b),a
		ld	hl,0xaf36
		call	qz_params
		ld	hl,(qz_frames)
		push	hl
		call	sub_be38h
		pop	de
		call	qz_elapsed
		ld	(qz_t_full),hl

qz_main:	ld	a,(qz_kbd)		; ряд 0: б7 вниз, б6 вправо, б5 вверх, б4 влево (0 = нажата)
		rla
		ld	b,a
		ld	c,0x1E
		jp	nc,qz_go		; вниз: содержимое вверх
		ld	a,b
		rla
		ld	b,a
		ld	c,0x0A
		jp	nc,qz_go		; вправо: содержимое влево
		ld	a,b
		rla
		ld	b,a
		ld	c,0x28
		jp	nc,qz_go		; вверх: содержимое вниз
		ld	a,b
		rla
		ld	c,0x14
		jp	nc,qz_go		; влево: содержимое вправо
		jp	qz_main

qz_go:		ld	a,c
		ld	(0xaf2b),a
		ld	e,a
		ld	d,0
		ld	hl,0xaf36
		add	hl,de
		call	qz_params
		ld	hl,(qz_frames)
		ld	(qz_t0),hl
		ld	a,(0xaf2b)
		cp	0x1E
		call	z,qz_vband
		cp	0x28
		call	z,qz_vband
qz_step:	ld	a,(0xaf2b)
		cp	0x0A
		jp	z,qz_s_l
		cp	0x14
		jp	z,qz_s_r
		cp	0x1E
		jp	z,qz_s_u
		call	sh_down
		jp	qz_s_done
qz_s_l:		call	sh_left
		jp	qz_s_done
qz_s_r:		call	sh_right
		jp	qz_s_done
qz_s_u:		call	sh_up
qz_s_done:
		ld	a,(0xaf34)		; камера += шаг (E18E оригинала)
		ld	c,a
		ld	a,(0xaf1c)
		add	a,c
		ld	(0xaf1c),a
		ld	a,(0xaf35)
		ld	c,a
		ld	a,(0xaf1d)
		add	a,c
		ld	(0xaf1d),a
		ld	a,(0xaf2b)
		cp	0x1E
		jp	z,qz_s_vu
		cp	0x28
		jp	z,qz_s_vd
		call	sub_be38h
qz_s_next:	ld	a,(0xaf2c)
		dec	a
		ld	(0xaf2c),a
		jp	nz,qz_step
		ld	hl,(qz_t0)
		ex	de,hl
		call	qz_elapsed
		ld	(qz_t_scroll),hl
		ld	hl,(qz_nscroll)
		inc	hl
		ld	(qz_nscroll),hl
		jp	qz_main

; вертикальный шаг из готовой полосы: вверх (0x1E) — строки полосы (8-AF2C)*8.. в строки поля 144..151,
; вниз (0x28) — строки (AF2C-1)*8.. в строки 0..7
qz_s_vu:	ld	a,(0xaf2c)
		cpl
		add	a,9			; 8 - AF2C
		add	a,a
		add	a,a
		add	a,a
		ld	e,TOP-(ROWS-8)
		call	vb_copy
		jp	qz_s_next
qz_s_vd:	ld	a,(0xaf2c)
		dec	a
		add	a,a
		add	a,a
		add	a,a
		ld	e,TOP
		call	vb_copy
		jp	qz_s_next

; Полоса 64 строки для вертикальной прокрутки, при конечной камере (камера + 8 шагов), в буфер BAND.
; Строки поля R0..R0+63: вниз (0x28) R0 = 0, смещение карты (03, FF), как у полной отрисовки;
; вверх (0x1E) R0 = 88, смещение (03 - 88/4, FF + 88/4) = (ED, 15): 8 строк поля = шаг карты (-2, +2).
; Нижняя граница AF2E = высота + 24 (как в таблице AF36: 0x98 -> 0xB0, 8 -> 0x20). Сохраняет A.
qz_vband:	push	af
		ld	hl,0xaf2c		; сохранить параметры и камеру
		ld	de,qz_psave
		ld	b,10
		call	qz_copyn
		ld	hl,(0xaf1c)
		ld	(qz_cam),hl
		ld	a,(0xaf34)
		add	a,a
		add	a,a
		add	a,a
		ld	c,a
		ld	a,(0xaf1c)
		add	a,c
		ld	(0xaf1c),a
		ld	a,(0xaf35)
		add	a,a
		add	a,a
		add	a,a
		ld	c,a
		ld	a,(0xaf1d)
		add	a,c
		ld	(0xaf1d),a
		ld	hl,qz_vb28
		ld	a,(0xaf2b)
		cp	0x28
		jp	z,qz_vb1
		ld	hl,qz_vb1e
qz_vb1:		call	qz_params
		ld	a,1
		ld	(vo_band),a
		call	sub_be38h
		xor	a
		ld	(vo_band),a
		ld	hl,qz_psave
		call	qz_params
		ld	hl,(qz_cam)
		ld	(0xaf1c),hl
		pop	af
		ret
qz_vb28:	db	0,0x20,0x58,0x40,0,0,0x03,0xFF,0,0
qz_vb1e:	db	0,0x20,0x58,0x40,0,88,0xED,0x15,0,0
qz_psave:	ds	10
qz_cam:		dw	0

; HL -> DE, B байт
qz_copyn:	ld	a,(hl)
		ld	(de),a
		inc	hl
		inc	de
		dec	b
		jp	nz,qz_copyn
		ret

; полная перерисовка при текущей камере (для проверки прокрутки стендом: run_vec.js QZ_VERIFY)
qz_redraw:	ld	a,(0xaf2b)
		push	af
		xor	a
		ld	(0xaf2b),a
		ld	hl,0xaf36
		call	qz_params
		call	sub_be38h
		pop	af
		ld	(0xaf2b),a
qz_redraw_done:	jp	qz_main

; HL = блок 10 байт параметров -> AF2C..AF35
qz_params:	ld	de,0xaf2c
		ld	b,10
		jp	qz_copyn
; HL = qz_frames - DE
qz_elapsed:	ld	hl,(qz_frames)
		ld	a,l
		sub	e
		ld	l,a
		ld	a,h
		sbc	a,d
		ld	h,a
		ret

; прерывание кадра: счётчик, палитра (каждый кадр), ряд 0 клавиатуры
isr:		push	af
		push	bc
		push	hl
		ld	hl,(qz_frames)
		inc	hl
		ld	(qz_frames),hl
		ld	hl,qz_pal+15
		ld	c,15
isr_pal:	ld	a,c
		out	(2),a
		ld	a,(hl)
		dec	hl
		out	(0x0C),a
		out	(0x0C),a
		out	(0x0C),a
		out	(0x0C),a
		dec	c
		jp	p,isr_pal
		ld	a,0x8A
		out	(0),a
		ld	a,0xFE
		out	(3),a
		in	a,(2)
		ld	(qz_kbd),a
		ld	a,0x88
		out	(0),a
		ld	a,0xFF
		out	(3),a
		xor	a
		out	(2),a
		pop	hl
		pop	bc
		pop	af
		ei
		ret

qz_pal:		db	PAPER,INK,PAPER,INK,PAPER,INK,PAPER,INK
		db	PAPER,INK,PAPER,INK,PAPER,INK,PAPER,INK
qz_kbd:		db	0xFF
qz_frames:	dw	0
qz_t0:		dw	0
qz_t_full:	dw	0
qz_t_scroll:	dw	0
qz_nscroll:	dw	0
; ячейки эмуляции Z80 для переведённого кода
il_tmp:		dw	0
il_tmp2:	dw	0
il_a:		dw	0
z80_af_alt:	dw	0

		include	"blit.asm"
		include	"vecout.asm"
		include	"../build/demo/render_8080.asm"
qz_code_end:
		ASSERT	qz_code_end <= 0x4000

		org	0x4000
		incbin	"../build/demo/shift_tables.bin"
		ASSERT	$ <= 0x6000 - 0x100	; место под стек

		org	0x61A9
		incbin	"../build/demo/zxdata.bin"	; 0x61A9-0xDFFF из снимка ОЗУ игры
		ASSERT	$ == 0xE000

		SAVEBIN	"../build/demo/qzdemo.r0m",0,0x10000
		SAVEBIN	"../build/demo/qzdemo.rom",0x100,0xE000-0x100
