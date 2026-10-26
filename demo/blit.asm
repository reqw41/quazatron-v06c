; Вывод плитки/спрайта в буфер-полосу — замена B07D оригинала (i8080, вручную).
; Вход: HL = описатель: [число столбцов] { [dx со знаком] [dy] [флаги|высота] байты... }.
; Столбец — 8 точек шириной, по байту на строку. Флаги: б7 — стирание (cpl; and (hl)),
; б6 — запись, иначе — наложение (or (hl)). Высота 0 — конец описателя (ret, как в оригинале).
; Позиция: x = (AF0E) + dx + 7 (0..0x26), y = (AF10) + dy; отсечение по строкам (AF16)/(AF17).
; Буфер-полоса — раскладкой Вектора: байт k строки r по адресу (STRIP+k)*256 + r, k = 0..3
; (в оригинале 4 байта на строку подряд). Байтовый столбец cx = x>>3 даёт байты cx-1 (левый) и cx
; (правый); при x&7 = 7 байт один — cx, выровненный.
; Сдвиг — таблицами: страница TBL+2s — левый байт (b << (7-s)) >> 8, TBL+2s+1 — правый (младший).

blt_s:		db	0			; x & 7
blt_cx:		db	0			; x >> 3 (0..4)
blt_mode:	db	0xFF			; код режима, под который пропатчены циклы (0xFF — ни под какой)

sub_b07dh:
		ld	a,(hl)
		inc	hl
blt_col:
		ld	(0xaf04),a		; столбцов осталось
		ld	c,(hl)			; dx
		inc	hl
		ex	de,hl			; DE = данные
		ld	hl,(0xaf0e)
		ld	a,c
		rla
		sbc	a,a
		ld	b,a
		add	hl,bc
		ld	bc,7
		add	hl,bc
		ex	de,hl			; DE = x + 7, HL = данные
		ld	a,d
		or	a
		jp	nz,blt_skiphdr
		ld	a,0x26
		cp	e
		jp	c,blt_skiphdr
		ld	a,e
		and	7
		ld	(blt_s),a
		ld	a,e
		rrca
		rrca
		rrca
		and	7
		ld	(blt_cx),a
		ld	(0xaf1b),a
		ld	a,(0xaf10)
		add	a,(hl)
		ld	d,a			; D = y
		inc	hl
		ld	a,(hl)			; флаги | высота
		inc	hl
		ld	c,a
		; режим: коды 0xA6 (and (hl)) с cpl, 0x00 (запись), 0xB6 (or (hl))
		and	0x80
		jp	z,blt_m1
		ld	a,0xA6
		jp	blt_m3
blt_m1:		ld	a,c
		and	0x40
		jp	z,blt_m2
		xor	a
		jp	blt_m3
blt_m2:		ld	a,0xB6
blt_m3:		ld	e,a
		ld	a,(blt_mode)
		cp	e
		call	nz,blt_patch
		ld	a,c
		and	0x3F
		ld	c,a			; C = высота
		ret	z
		; отсечение сверху: y > (AF16) значит строка «выше нуля» (отрицательная)
		ld	a,(0xaf16)
		cp	d
		jp	nc,blt_v1
		ld	a,d
		add	a,c
		jp	nc,blt_skip		; весь столбец выше полосы
		jp	z,blt_skip
		ld	c,a			; видимых строк
		ld	a,d
		cpl
		inc	a			; -y
		add	a,l
		ld	l,a
		ld	a,0
		adc	a,h
		ld	h,a			; пропустить -y байт данных
		ld	d,0
blt_v1:		ld	a,(0xaf17)
		sub	d
		ld	b,a			; строк до низа полосы
		ld	a,c
		sub	b
		jp	nc,blt_v2
		ld	b,c
		xor	a
blt_v2:		ld	(0xaf05),a		; сколько байт пропустить после вывода
		ld	a,b
		or	a
		jp	z,blt_skipv		; нечего выводить (в оригинале было бы 256 строк — не бывает)
		ld	c,b			; C = строк
		ld	b,h
		ld	a,l
		ld	l,d			; L = строка
		ld	e,a			; BE = данные (временно)
		ld	a,(blt_cx)
		add	a,STRIP
		ld	h,a			; HL = приёмник (байт cx)
		ld	a,(blt_s)
		cp	7
		jp	z,blt_al
		dec	h			; левый байт — cx-1
		add	a,a
		add	a,TBL
		ld	d,a			; D = страница левых байт таблицы
		ld	a,c
		add	a,e			; младший байт конца данных
		ld	(blt_eb+1),a
		ld	(blt_el+1),a
		ld	(blt_er+1),a
		ld	c,e			; BC = данные
		ld	a,(blt_cx)
		or	a
		jp	z,blt_r
		cp	4
		jp	z,blt_l
		; ---- оба байта: BC — данные, D — таблица, HL — приёмник левого байта
blt_b_lp:	ld	a,(bc)
		inc	bc
		ld	e,a
		ld	a,(de)
blt_o1a:	nop
blt_o2a:	nop
		ld	(hl),a
		inc	d
		inc	h
		ld	a,(de)
blt_o1b:	nop
blt_o2b:	nop
		ld	(hl),a
		dec	d
		dec	h
		inc	l
		ld	a,c
blt_eb:		cp	0
		jp	nz,blt_b_lp
		jp	blt_done
		; ---- только левый байт (cx = 4: пишем байт 3)
blt_l:
blt_l_lp:	ld	a,(bc)
		inc	bc
		ld	e,a
		ld	a,(de)
blt_o1l:	nop
blt_o2l:	nop
		ld	(hl),a
		inc	l
		ld	a,c
blt_el:		cp	0
		jp	nz,blt_l_lp
		jp	blt_done
		; ---- только правый байт (cx = 0: пишем байт 0)
blt_r:		inc	d			; страница правых байт
		inc	h			; байт 0
blt_r_lp:	ld	a,(bc)
		inc	bc
		ld	e,a
		ld	a,(de)
blt_o1r:	nop
blt_o2r:	nop
		ld	(hl),a
		inc	l
		ld	a,c
blt_er:		cp	0
		jp	nz,blt_r_lp
		jp	blt_done
		; ---- выровненный (x&7 = 7): байт как есть; DE — данные, C — счётчик
blt_al:		ld	d,b
blt_a_lp:	ld	a,(de)
		inc	de
blt_o1x:	nop
blt_o2x:	nop
		ld	(hl),a
		inc	l
		dec	c
		jp	nz,blt_a_lp
		ld	b,d
		ld	c,e
blt_done:	ld	h,b
		ld	l,c
blt_skipv:	ld	a,(0xaf05)
		ld	c,a
blt_skip:	ld	b,0
		add	hl,bc
		ld	a,(0xaf04)
		dec	a
		jp	nz,blt_col
		ret
blt_skiphdr:	inc	hl
		ld	a,(hl)
		and	0x3F
		ld	c,a
		inc	hl
		jp	blt_skip

; пропатчить операции всех циклов под режим E (0xA6 / 0x00 / 0xB6)
blt_patch:	ld	a,e
		ld	(blt_mode),a
		ld	(blt_o2a),a
		ld	(blt_o2b),a
		ld	(blt_o2l),a
		ld	(blt_o2r),a
		ld	(blt_o2x),a
		cp	0xA6
		ld	a,0x2F			; cpl
		jp	z,blt_p1
		xor	a			; nop
blt_p1:		ld	(blt_o1a),a
		ld	(blt_o1b),a
		ld	(blt_o1l),a
		ld	(blt_o1r),a
		ld	(blt_o1x),a
		ret
