; Заставка 16 цветов на весь экран перед игрой (tools/mk_splash.py подставляет SPL_* и собирает образ).
; Память в момент старта: 8000-FFFF — четыре плоскости картинки, 0000-7FFF — этот код, поток U (игра A000-DFFF, сжата
; ZX0 classic) и поток L (игра 0000-7FFF) без последних delta байт: они — в ступени 2, перед распаковкой ложатся
; в 8000.. (поток кончается на delta байт за 8000 — распаковка на месте вперёд).
; Прерывание: палитра и опрос клавиатуры (порт 03h — FF сразу после опроса: он же регистр прокрутки).
; Клавиша нажата и отпущена -> палитра чёрная, di, ступень 2 — в 9F00 (плоскость 0: её загрузчик игры всё равно чистит):
; U -> A000, нули E000-FFFF, L -> 0000 на месте, jp 0 — обычный старт игры.
; Распаковщик: DeZX/ZX0/8080/dzx0.asm, Ivan Gorodetsky (ivagor), v4, ветка FORWARD, «Based on ZX0 z80 decoder by Einar
; Saukas» (ZX0 — BSD-3, tools/zx0/LICENSE); мнемоники — синтаксис Z80 (подмножество i8080), команда в команду.

		DEVICE	NOSLOT64K
		org	0
		di
		jp	spl_start
		org	0x38
		jp	spl_isr

spl_start:	ld	sp,spl_stack
		ld	a,0x88			; ВВ55: A, B — вывод, C — ввод/вывод
		out	(0),a
		xor	a
		out	(2),a			; бордюр — индекс 0 (чёрный), режим 256
		ld	a,0xFF
		out	(3),a			; прокрутка — стандартная
		ei
.w1:		ld	a,(spl_any)		; ждать нажатия ...
		and	a
		jp	z,.w1
.w2:		ld	a,(spl_any)		; ... и отпускания (иначе заставка игры примет её за огонь)
		and	a
		jp	nz,.w2
		di
		ld	c,15			; палитра чёрная: дальнейшая возня в плоскостях не видна
.pb:		ld	a,c
		out	(2),a
		xor	a
		out	(0x0C),a
		out	(0x0C),a
		out	(0x0C),a
		out	(0x0C),a
		dec	c
		jp	p,.pb
		xor	a
		out	(2),a
		ld	hl,s2_src		; ступень 2 -> 9F00
		ld	de,SPL_S2
		ld	bc,s2_end - s2_beg
.cp:		ld	a,(hl)
		ld	(de),a
		inc	hl
		inc	de
		dec	bc
		ld	a,b
		or	c
		jp	nz,.cp
		jp	SPL_S2

spl_isr:	push	af
		push	bc
		push	hl
		ld	hl,spl_pal + 15
		ld	c,15
.p:		ld	a,c
		out	(2),a
		ld	a,(hl)
		dec	hl
		out	(0x0C),a
		out	(0x0C),a
		out	(0x0C),a
		out	(0x0C),a
		dec	c
		jp	p,.p
		ld	a,0x8A			; клавиатура: ряды через порт 03h, чтение — порт 02h
		out	(0),a
		ld	b,0xFE
		ld	c,0
.k:		ld	a,b
		out	(3),a
		in	a,(2)
		cpl
		or	c
		ld	c,a
		ld	a,b
		rlca
		ld	b,a
		jp	c,.k
		ld	a,0x88
		out	(0),a
		ld	a,0xFF
		out	(3),a
		xor	a
		out	(2),a
		ld	a,c
		ld	(spl_any),a
		pop	hl
		pop	bc
		pop	af
		ei
		ret

spl_any:	db	0
spl_pal:	incbin	"SPL_PAL"			; 16 байт BBGGGRRR по индексу p0<<3 | p1<<2 | p2<<1 | p3
		ds	32
spl_stack:

s2_src:
		PHASE	SPL_S2
s2_beg:		ld	sp,SPL_S2
		ld	hl,SPL_U
		ld	bc,0xA000
		call	dzx0
		ld	hl,0xE000		; плоскость E000-FFFF — нули, как в образе игры
		ld	b,0
.z:		ld	(hl),b
		inc	l
		jp	nz,.z
		inc	h
		jp	nz,.z
		ld	hl,s2_tail		; хвост потока L (delta байт за 8000 — там были точки картинки) -> на место
		ld	de,0x8000
		ld	c,SPL_DELTA
.t:		ld	a,(hl)
		ld	(de),a
		inc	hl
		inc	de
		dec	c
		jp	nz,.t
		ld	hl,SPL_L
		ld	bc,0
		call	dzx0
		jp	0
dzx0:		ld	de,0xFFFF
		push	de
		inc	de
		ld	a,0x80
dzx0_lit:	call	dzx0_elias
		call	dzx0_ldir
		add	a,a
		jp	c,dzx0_new
		call	dzx0_elias
dzx0_copy:	ex	(sp),hl
		push	hl
		add	hl,bc
		call	dzx0_ldir
		pop	hl
		ex	(sp),hl
		add	a,a
		jp	nc,dzx0_lit
dzx0_new:	call	dzx0_elias
		ld	d,a
		pop	af
		xor	a
		sub	e
		ret	z
		ld	e,d
		ld	d,a
		ld	a,e
		push	bc
		ld	b,a
		ld	a,d
		rra
		ld	d,a
		ld	a,(hl)
		rra
		ld	e,a
		ld	a,b
		pop	bc
		inc	hl
		push	de
		ld	de,1
		call	nc,dzx0_back
		inc	de
		jp	dzx0_copy
dzx0_elias:	inc	e
dzx0_eloop:	add	a,a
		jp	nz,dzx0_eskip
		ld	a,(hl)
		inc	hl
		rla
dzx0_eskip:	ret	c
dzx0_back:	ex	de,hl
		add	hl,hl
		ex	de,hl
		add	a,a
		jp	nc,dzx0_eloop
		inc	e
		jp	dzx0_eloop
dzx0_ldir:	push	af
dzx0_ldl:	ld	a,(hl)
		ld	(bc),a
		inc	hl
		inc	bc
		dec	de
		ld	a,d
		or	e
		jp	nz,dzx0_ldl
		pop	af
		ret
s2_tail:	incbin	"SPL_TAIL"
s2_end:
		DEPHASE
spl_code_end:
		ASSERT	spl_code_end <= SPL_U
		org	SPL_U
		incbin	"SPL_UBIN"
spl_u_end:
		ASSERT	spl_u_end <= SPL_L
		org	SPL_L
		incbin	"SPL_LBIN"
		SAVEBIN	"SPL_OUT",0,0x8000
