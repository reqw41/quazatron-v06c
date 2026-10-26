; Добавки сборки i8080, четвёртая часть: поле T_FIELD (32 x 152 = 4864 байта, 2300-35FF) — кольцо. Логический байт
; L (0..4863, строка * 32 + столбец) лежит по адресу T + ((L + ring_off) mod 4864). Сдвиги поля (scr_shift_*, scroll_step:
; ldir/lddr на 2 или 256 байт) не копируют 4,8 КБ, а меняют ring_off — для всех байтов, кроме 2 / 256 на краю, это ровно
; ldir ZX; краевые байты сразу перекрывает новая полоса (strip_put, копия BAND). Поле читают и пишут только strip_put,
; bg_restore (port/i8080_ring2.asm), перекладка в экран (vec_scr_copy) и копия BAND — они здесь знают кольцо.

RING_T		equ	0x2300
RING_END	equ	0x3600
RING_N		equ	RING_END - RING_T

ring_off:	dw	0			; смещение кольца (чётное, 0..4862)

; ---- сдвиги (вместо ldir/lddr поля): регистры как после ldir (HL, DE + BC) / lddr (− BC), BC = 0; A и флаги сохраняются
ring_l80:	push	af			; влево (ldir 2302 -> 2300)
		push	de
		ld	de,2
		jp	ring_adv
ring_u80:	push	af			; вверх (ldir 2400 -> 2300)
		push	de
		ld	de,256
ring_adv:	call	ring_add
		pop	de
		add	hl,bc
		ex	de,hl
		add	hl,bc
		ex	de,hl
		ld	bc,0
		pop	af
		ret
ring_r80:	push	af			; вправо (lddr)
		push	de
		ld	de,RING_N - 2
		jp	ring_back
ring_d80:	push	af			; вниз (lddr)
		push	de
		ld	de,RING_N - 256
ring_back:	call	ring_add
		pop	de
		ld	a,l
		sub	c
		ld	l,a
		ld	a,h
		sbc	a,b
		ld	h,a
		ld	a,e
		sub	c
		ld	e,a
		ld	a,d
		sbc	a,b
		ld	d,a
		ld	bc,0
		pop	af
		ret
ring_add:	push	hl			; ring_off = (ring_off + DE) mod 4864
		ld	hl,(ring_off)
		add	hl,de
		ld	de,-RING_N
		add	hl,de
		jp	c,.s
		ld	de,RING_N
		add	hl,de
.s:		ld	(ring_off),hl
		pop	hl
		ret

; логический адрес поля HL (T + L) -> адрес в кольце; вне поля — без изменений. Портит A, флаги
ring_phys:	ld	a,h
		cp	high RING_T
		ret	c
		cp	high RING_END
		ret	nc
		push	de
		push	hl
		ld	hl,(ring_off)
		ex	de,hl
		pop	hl
		add	hl,de
		ld	a,h
		cp	high RING_END
		jp	c,.x
		ld	de,-RING_N
		add	hl,de
.x:		pop	de
		ret

; ---- strip_put (C1A5): полоса v_blt_buf (4 байта на строку) -> поле с (v_strip_row, v_strip_col), v_strip_h строк,
; 2 байта (v_scr_wide = 1) или 4; приёмник — sp_dst (поле или BAND склейки — тогда без кольца). Строки до разрыва
; кольца и после — подряд (sp_rows), строка, через которую проходит разрыв, — по байту. Выход как у ZX:
; HL — логический адрес за последней строкой, DE — буфер + 4 * h, BC = 1F / 1D, A = 0 (Z), v_tmp = 0
V_SCR_WIDE8	equ	0xAF2D
strip_put_80:	ld	a,(V_SCR_WIDE8)
		cp	1
		ld	hl,sp_r2
		ld	a,0x1F
		jp	z,.w
		ld	hl,sp_r4
		ld	a,0x1D
.w:		ld	(sp_wj+1),hl
		ld	(sp_bc),a
		ld	a,(V_STRIP_ROW8)	; HL = приёмник + строка * 32 + столбец (логический)
		ld	l,a
		ld	h,0
		add	hl,hl
		add	hl,hl
		add	hl,hl
		add	hl,hl
		add	hl,hl
		ld	a,(V_STRIP_COL8)
		ld	e,a
		ld	d,0
		add	hl,de
		ex	de,hl
		ld	hl,(sp_dst)
		add	hl,de
		ld	(sp_l0),hl
		push	hl
		ld	hl,(V_BLT_BUF)
		ex	de,hl			; DE — полоса
		pop	hl
		ld	a,(V_STRIP_H8)
		ld	b,a
		ld	a,h			; не поле (BAND) — все строки подряд
		cp	high RING_T
		jp	c,.all
		cp	high RING_END
		jp	nc,.all
		call	ring_phys		; HL — первая строка в кольце
		push	de
		ld	a,low RING_END		; DE = 3600 − HL — байтов до разрыва
		sub	l
		ld	e,a
		ld	a,high RING_END
		sbc	a,h
		ld	d,a
		ld	a,(sp_bc)		; строк целиком до разрыва: (D + 32 − w) / 32; 32 − w = BC − 1 (1F -> 30, 1D -> 28)
		dec	a
		push	hl
		ld	l,a
		ld	h,0
		add	hl,de			; D + 32 − w
		add	hl,hl
		add	hl,hl
		add	hl,hl			; H = (D + 32 − w) / 32
		ld	a,h
		pop	hl
		pop	de
		ld	c,a			; C = строк до разрыва
		ld	a,b
		and	a
		jp	z,.n1			; h = 0 (256) — больше любого C
		ld	a,c
		cp	b
		jp	nc,.all			; все строки до разрыва
.n1:		ld	a,b
		sub	c
		ld	(sp_n),a		; строк после
		ld	b,c
		ld	a,b
		and	a
		call	nz,sp_rows
		ld	a,h			; начало следующей строки уже за 3600 — разрыв между строками
		cp	high RING_END
		jp	nc,.wr
		ld	a,(sp_bc)		; строка через разрыв — по байту
		cp	0x1F
		ld	c,2
		jp	z,.sb
		ld	c,4
.sb:		ld	a,(de)
		ld	(hl),a
		inc	de
		inc	hl
		ld	a,h
		cp	high RING_END
		jp	nz,.s1
		ld	h,high RING_T
.s1:		dec	c
		jp	nz,.sb
		ld	a,(sp_bc)		; к началу следующей строки: + (32 − w) = BC − 1, полоса + (4 − w)
		dec	a
		ld	c,a
		ld	b,0
		add	hl,bc
		cp	0x1E
		jp	nz,.s4
		inc	de
		inc	de
.s4:		ld	a,(sp_n)
		dec	a
		jp	z,.x
		ld	b,a
		jp	.rest
.wr:		ld	bc,-RING_N
		add	hl,bc
		ld	a,(sp_n)
		and	a
		jp	z,.x
		ld	b,a
.rest:		call	sp_rows
		jp	.x
.all:		call	sp_rows
.x:		ld	a,(V_STRIP_H8)		; HL = логическое начало + 32 * h
		ld	l,a
		ld	h,0
		and	a
		jp	nz,.h1
		inc	h
.h1:		add	hl,hl
		add	hl,hl
		add	hl,hl
		add	hl,hl
		add	hl,hl
		push	de
		ex	de,hl
		ld	hl,(sp_l0)
		add	hl,de
		pop	de
		ld	a,(sp_bc)
		ld	c,a
		ld	b,0
		xor	a
		ld	(V_TMP8),a
		ret
; B строк (0 — 256) подряд: HL — приёмник, DE — полоса; на выходе оба за последней строкой
sp_rows:	ld	a,(de)
		ld	(hl),a
		inc	de
		inc	hl
		ld	a,(de)
		ld	(hl),a
		inc	de
sp_wj:		jp	0
sp_r4:		inc	hl
		ld	a,(de)
		ld	(hl),a
		inc	de
		inc	hl
		ld	a,(de)
		ld	(hl),a
		inc	de
		ld	a,l
		add	a,29
		jp	sp_st
sp_r2:		inc	de
		inc	de
		ld	a,l
		add	a,31
sp_st:		ld	l,a
		jp	nc,.n
		inc	h
.n:		dec	b
		jp	nz,sp_rows
		ret
sp_bc:		db	0
sp_n:		db	0
sp_l0:		dw	0
sp_dst:		dw	RING_T			; приёмник (vband_render склейки ставит BAND − R0 * 32)

; 8 строк из BAND в поле (вместо ldir 256 байт в vec_cam_draw): HL — BAND, DE — логическое начало строк поля.
; Кусок до конца кольца и остаток с начала — z_ldir. Выход как у ldir: HL, DE + 256, BC = 0; A и флаги сохраняются
ring_band80:	push	af
		push	hl
		ld	hl,256
		add	hl,de
		ld	(rb_de),hl
		ex	de,hl
		call	ring_phys
		ex	de,hl			; DE — приёмник в кольце
		ld	hl,RING_END		; BC = min(256, 3600 − DE)
		ld	a,l
		sub	e
		ld	c,a
		ld	a,h
		sbc	a,d
		ld	b,a
		and	a
		jp	z,.cut
		ld	bc,256
.cut:		ld	a,c
		ld	(rb_n),a
		pop	hl
		call	z_ldir
		ld	a,(rb_n)		; остаток 256 − первый кусок (0, если первый — 256: тогда rb_n = 0)
		and	a
		jp	z,.x
		cpl
		inc	a
		ld	c,a
		ld	b,0
		ld	de,RING_T
		call	z_ldir
.x:		push	hl
		ld	hl,(rb_de)
		ex	de,hl
		pop	hl
		ld	bc,0
		pop	af
		ret
rb_de:		dw	0
rb_n:		db	0

; ---- перекладка поля в плоскость (vec_scr_copy склейки): 152 строки по 16 pop подряд из кольца; на строке разрыва
; (логический байт 4864 − off) — два куска: до 3600 и с 2300. Блоки по 4 строки при di. Затем атрибуты (scr_copy ZX)
; и классы (vec_scr_copy_end), как у склейки
vec_scr_copy_80:
		ld	hl,0
		add	hl,sp
		ld	(g_vsc_sp),hl
		ld	hl,(ring_off)		; HL = 4864 − off (байтов до разрыва)
		ld	a,low RING_N
		sub	l
		ld	l,a
		ld	a,high RING_N
		sbc	a,h
		ld	h,a
		ld	a,l			; J = (HL & 31) / 2 пар до разрыва в строке разрыва
		and	31
		rrca
		ld	b,a
		add	a,a			; h второго куска = PLANE + 2J
		add	a,PLANE8
		ld	(vs_h2+1),a
		add	hl,hl
		add	hl,hl
		add	hl,hl			; H = (4864 − off) / 32 — строка разрыва W
		ld	a,152			; счётчик строк на ней: 152 − W (W = 152 — разрыва нет: 0 не встретится)
		sub	h
		ld	(vs_wb+1),a
		ld	a,b
		add	a,a
		add	a,a
		add	a,b			; 5J
		ld	e,a
		ld	d,0
		ld	hl,vs_blk
		add	hl,de
		ld	(vs_e2+1),hl		; второй кусок: 16 − J пар (вход после J пар)
		ld	hl,vs_blk + 80
		ld	a,l
		sub	e
		ld	l,a
		ld	a,h
		sbc	a,d
		ld	h,a
		ld	(vs_e1+1),hl		; первый кусок: J пар (вход за 16 − J пар до конца)
		ld	hl,(ring_off)
		ld	de,RING_T
		add	hl,de
		ld	c,ROW08			; строка плоскости
		ld	b,152
		di
		ld	sp,hl
vs_row:		ld	a,b
vs_wb:		cp	0
		jp	z,vs_split
		ld	l,c
		ld	h,PLANE8
vs_blk:		REPT	16
		pop	de
		ld	(hl),e
		inc	h
		ld	(hl),d
		inc	h
		ENDR
vs_cj:		jp	vs_nx
vs_nx:		dec	c
		dec	b
		jp	z,vs_end
		ld	a,b
		and	3
		jp	nz,vs_row
		ld	hl,0			; окно для прерывания
		add	hl,sp
		ex	de,hl
		ld	hl,(g_vsc_sp)
		ld	sp,hl
		ei
		nop
		di
		ex	de,hl
		ld	sp,hl
		jp	vs_row
vs_split:	ld	hl,vs_p2		; строка разрыва: J пар до 3600, затем 16 − J с 2300
		ld	(vs_cj+1),hl
		ld	l,c
		ld	h,PLANE8
vs_e1:		jp	0
vs_p2:		ld	hl,vs_nx
		ld	(vs_cj+1),hl
		ld	hl,RING_T
		ld	sp,hl
		ld	l,c
vs_h2:		ld	h,0
vs_e2:		jp	0
vs_end:		ld	hl,(g_vsc_sp)
		ld	sp,hl
		ei
		ld	hl,RING_END		; ячейки и регистры — как после цикла склейки
		ld	(g_vsc_src),hl
		ld	a,ROW08 - 152
		ld	(g_vsc_row),a
		ld	l,a
		ld	h,PLANE8 + 32
		ld	bc,0
		call	scr_attr_80
		jp	c_vec_scr_copy_end

; ---- атрибутная часть scr_copy (C0C3): 16 пар столбцов, строки 0..18 — по t_colattr [s, e]: строки < s — v_fieldattr,
; s..e−1 — v_fieldattr2 (e = FF — до низа), остальные — v_fieldattr (s = FF — весь столбец v_fieldattr; s = 0 — с верха).
; Строки — развёрнутые (sa_blk, вход по числу строк). Выход как у ZX: v_sc_ptr = t_colattr + 30, HL = 5A7E, DE = 1F,
; B — атрибут последнего куска, C = 0, A = 7E (Z = 1)
T_COLATTR8	equ	0xB024
V_FA8		equ	0xB044
V_FA28		equ	0xB045
V_SC_PTR8	equ	0xB046
scr_attr_80:	ld	hl,T_COLATTR8
		ld	(sa_p),hl
		ld	hl,0x5800
		ld	de,31
		ld	c,16
.pair:		push	hl
		ld	hl,(sa_p)
		ld	(V_SC_PTR8),hl
		ld	a,(hl)			; s
		inc	hl
		push	af
		ld	a,(hl)			; e
		inc	hl
		ld	(sa_p),hl
		ld	l,a
		pop	af
		ld	h,a			; H = s, L = e
		ld	a,(V_FA8)
		ld	(sa_v3),a		; низ — фон (если e = FF — пол)
		ld	a,h
		inc	a
		jp	z,.s19			; s = FF — весь столбец фон
		ld	a,l
		inc	a
		jp	nz,.e1
		ld	a,(V_FA28)		; e = FF: строки s..18 — пол
		ld	(sa_v3),a
		ld	l,h			; второй кусок пустой: e = s
		jp	.e2
.e1:		ld	a,l
		and	a
		jp	nz,.e2
		ld	l,h			; e = 0: без пола
.e2:		ld	a,h
		ld	(sa_n1),a
		ld	a,l
		sub	h
		ld	(sa_n2),a
		ld	a,19
		sub	l
		jp	.go
.s19:		ld	a,19
		ld	(sa_n1),a
		xor	a
		ld	(sa_n2),a
.go:		ld	(sa_n3),a
		pop	hl
		ld	a,(V_FA8)
		ld	b,a
		ld	a,(sa_n1)
		call	sa_seg
		ld	a,(V_FA28)
		ld	b,a
		ld	a,(sa_n2)
		call	sa_seg
		ld	a,(sa_v3)
		ld	b,a
		ld	a,(sa_n3)
		call	sa_seg
		ld	a,l			; к верху следующей пары: строка 19 -> строка 0, + 2
		sub	low (19 * 32 - 2)
		ld	l,a
		ld	a,h
		sbc	a,high (19 * 32 - 2)
		ld	h,a
		dec	c
		jp	nz,.pair
		ld	hl,T_COLATTR8 + 30
		ld	(V_SC_PTR8),hl
		ld	hl,0x5A7E
		ld	a,0x7E
		dec	c			; C = 0 (снова): Z = 1 нужен — dec 1 -> 0
		inc	c
		ret
; A строк (0 — ничего) атрибутом B с HL вниз (DE = 31); HL — за последней строкой
sa_seg:		and	a
		ret	z
		add	a,a
		add	a,a			; 4 байта на строку
		cpl
		inc	a			; −4n
		add	a,low sa_end
		ld	(.j+1),a
		ld	a,high sa_end
		adc	a,0xFF			; − (заём) — вход = sa_end − 4n
		ld	(.j+2),a
.j:		jp	0
sa_blk:		REPT	19
		ld	(hl),b
		inc	l
		ld	(hl),b
		add	hl,de
		ENDR
sa_end:		ret
sa_p:		dw	0
sa_n1:		db	0
sa_n2:		db	0
sa_n3:		db	0
sa_v3:		db	0
