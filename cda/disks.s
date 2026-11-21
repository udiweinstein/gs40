; Disks - a IIgs Classic Desk Accessory (Ctrl-Cmd-Esc) for GS40
;
; Lists the drives (S5D1-S5D2, S6D1-S6D2, S7D1-S7D8) with the disk image in
;  each, and lets you choose a disk image from the GS40 disk images folder
;  (F4 > Disk images folder) for a drive, or eject one.  It uses the GS40
;  disk image API (WDM $EA,$D8, see src/diskapi.c), version 2 or later: the
;  parameter block and buffers are in this CDA's own bank (B register).
;
; Keys: arrows to move, Return to choose, E to eject, Esc to go back.
;
; Build: cda/build.sh (ca65/ld65 from cc65, then tools/mkomf.py makes the
;  OMF load file, ProDOS file type $B9 = CDA).  Install: copy it into
;  SYSTEM/DESK.ACCS on the GS/OS boot disk.
;
; The Desk Manager calls Main with JSL.  We switch to native mode, keep the
;  accumulator 8 bits and the index registers 16 bits, use only absolute
;  (data bank = ours) and long addressing, no direct page, and return with
;  RTL.  Note: with 16-bit index registers TAX/TAY copy all 16 bits of the
;  accumulator, so A8 values go to X/Y only through AtoX/AtoY.

	.p816
	.smart	-

	.segment "CODE"

; ---- CDA header: name, start routine, shut down routine ----
Header:	.byte	5, "Disks"
	.dword	Main		; offset 6: relocated by mkomf.py
	.dword	ShutDown	; offset 10: relocated by mkomf.py

ShutDown:
	rtl

SCREEN	= $E00000		; text page 1 as the video sees it (+$400..)
KBD	= $00C000
KBDSTRB	= $00C010
CLR80COL = $00C00C
SET80COL = $00C00D
CLRALTCH = $00C00E
SETALTCH = $00C00F
RDALTCH	= $00C01E
RD80COL	= $00C01F
TXTSET	= $00C051
TXTPAGE1 = $00C054

LIST_MAX = 128			; disk images listed at once
FROWS	= 16			; rows in the disk image list
FTOP_ROW = 3

K_LEFT	= $08
K_DOWN	= $0A
K_UP	= $0B
K_RET	= $0D
K_RIGHT	= $15
K_ESC	= $1B

Main:
	clc
	xce			; native mode; carry = the caller's E
	php			; (the saved carry keeps it)
	phb
	phk
	plb
	rep	#$30
	.a16
	.i16
	lda	#0		; clear the high byte of the accumulator
	sep	#$20
	.a8
	lda	f:RD80COL
	sta	save80
	lda	f:RDALTCH
	sta	savealt
	sta	f:CLR80COL
	sta	f:SETALTCH
	sta	f:TXTSET
	sta	f:TXTPAGE1

	lda	#0		; ID: A = 'K', X = version, if the API is there
	jsr	DoApi
	cmp	#'K'
	bne	@noapi
	txa
	cmp	#2		; version 2 or later: B = bank
	bcc	@noapi
	jsr	DrvScreen
	bra	@exit
@noapi:
	jsr	ClrScr
	jsr	Title
	ldy	#10
	ldx	#2
	jsr	SetPos
	ldy	#msg_noapi
	jsr	PutStr
	ldy	#12
	ldx	#2
	jsr	SetPos
	ldy	#msg_anykey
	jsr	PutStr
	jsr	GetKey
@exit:
	lda	save80
	bpl	:+
	sta	f:SET80COL
:	lda	savealt
	bmi	:+
	sta	f:CLRALTCH
:	plb
	plp
	xce			; back to the caller's E
	rtl

; ---- API call: A = command, block at blk.  Returns A, carry = error ----
DoApi:
	pha
	rep	#$20
	.a16
	lda	#blk
	tax			; the API uses X & $FF = low byte
	xba
	and	#$00FF
	tay			; and Y & $FF = high byte
	sep	#$20
	.a8
	pla
	.byte	$42, $EA, $D8	; WDM $EA ; CLD  (elsewhere: 2-byte NOP, CLD)
	rts

; Y = A, X = A (A8, zero extended)
AtoY:
	rep	#$20
	.a16
	and	#$00FF
	tay
	sep	#$20
	.a8
	rts
AtoX:
	rep	#$20
	.a16
	and	#$00FF
	tax
	sep	#$20
	.a8
	rts

; ==== Drives screen ====
DrvScreen:
	stz	dsel
DrvReload:
	rep	#$20
	.a16
	lda	#drvbuf
	sta	blk
	sep	#$20
	.a8
	lda	#4		; DRIVES
	jsr	DoApi
	bcc	:+
	rts
:	sta	dcount
	lda	dsel
	cmp	dcount
	bcc	DrvRedraw
	stz	dsel
DrvRedraw:
	jsr	ClrScr
	jsr	Title
	stz	line
:	lda	line
	cmp	dcount
	bcs	:+
	jsr	DrawDrive
	inc	line
	bra	:-
:	ldy	#22
	ldx	#1
	jsr	SetPos
	ldy	#msg_drvkeys
	jsr	PutStr
DrvKey:
	jsr	GetKey
	cmp	#K_ESC
	bne	:+
	rts
:	cmp	#K_UP
	bne	:+
	lda	dsel
	beq	DrvKey
	dec	dsel
	jmp	DrvRedraw
:	cmp	#K_DOWN
	bne	:+
	lda	dsel
	inc	a
	cmp	dcount
	bcs	DrvKey
	sta	dsel
	jmp	DrvRedraw
:	cmp	#K_RET
	beq	DrvChoose
	cmp	#K_RIGHT
	beq	DrvChoose
	and	#$DF		; upper case
	cmp	#'E'
	bne	DrvKey
	lda	dsel		; EJECT
	jsr	DrvEntry
	lda	a:0,y		; +0 drive
	sta	blk+1
	lda	#3
	jsr	DoApi
	jmp	DrvReload
DrvChoose:
	lda	dsel
	jsr	DrvEntry
	lda	a:0,y
	sta	curdrv
	jsr	FileScreen
	jmp	DrvReload

; Y = address of drive entry A
DrvEntry:
	rep	#$20
	.a16
	and	#$00FF
	asl	a
	asl	a
	asl	a
	asl	a
	asl	a		; * 32
	clc
	adc	#drvbuf
	tay
	sep	#$20
	.a8
	rts

; Draw drive line number 'line' on row 3 + line
DrawDrive:
	lda	line
	jsr	SetInv
	lda	line
	clc
	adc	#3
	jsr	AtoY
	ldx	#1
	jsr	SetPos
	lda	#' '
	jsr	PutCh
	lda	line
	jsr	DrvEntry
	phy
	lda	a:0,y		; drive: slot*16 + drive
	jsr	PutDrive
	lda	#' '
	jsr	PutCh
	jsr	PutCh
	ply
	lda	a:1,y		; flags: 1 = a disk is in it
	and	#1
	bne	:+
	ldy	#msg_empty
	jsr	PutStr
	bra	:++
:	iny
	iny
	iny
	iny			; +4: name
	jsr	PutName
:	lda	#39
	jsr	PadTo
	stz	inv
	rts

; inv = 1 if A is the selected line (dsel or fsel, in cursel)
SetInv:
	stz	inv
	cmp	cursel
	bne	:+
	inc	inv
:	rts

; Print drive A as "S6D1"
PutDrive:
	pha
	lda	#'S'
	jsr	PutCh
	pla
	pha
	lsr	a
	lsr	a
	lsr	a
	lsr	a
	ora	#'0'
	jsr	PutCh
	lda	#'D'
	jsr	PutCh
	pla
	and	#$0F
	ora	#'0'
	jmp	PutCh

; ==== Disk images screen, for drive curdrv ====
FileScreen:
	stz	path		; start in the disk images folder itself
FileReload:
	rep	#$20
	.a16
	lda	#listbuf
	sta	blk
	sep	#$20
	.a8
	lda	#LIST_MAX
	sta	blk+2
	ldx	#0		; blk+3: the sub-folder (length + chars)
:	lda	path,x
	sta	blk+3,x
	inx
	cpx	#64
	bcc	:-
	lda	#1		; LIST
	jsr	DoApi
	bcc	:+
	jmp	ShowErr
:	sta	fcount
	stz	fsel
	stz	ftop
FileRedraw:
	jsr	ClrScr
	jsr	Title
	lda	fsel		; after Title, which sets it to dsel
	sta	cursel
	ldy	#1		; title: " S6D1: folder/"
	ldx	#1
	jsr	SetPos
	lda	#1
	sta	inv
	lda	#' '
	jsr	PutCh
	lda	curdrv
	jsr	PutDrive
	lda	#':'
	jsr	PutCh
	lda	#' '
	jsr	PutCh
	ldy	#path
	jsr	PutName
	lda	#'/'
	jsr	PutCh
	lda	#39
	jsr	PadTo
	stz	inv
	lda	fcount
	bne	:+
	ldy	#FTOP_ROW
	ldx	#2
	jsr	SetPos
	ldy	#msg_nofiles
	jsr	PutStr
	bra	FileFoot
:	stz	line
:	lda	line
	cmp	#FROWS
	bcs	FileFoot
	clc
	adc	ftop
	cmp	fcount
	bcs	FileFoot
	jsr	DrawFile
	inc	line
	bra	:-
FileFoot:
	ldy	#22
	ldx	#1
	jsr	SetPos
	ldy	#msg_filekeys
	jsr	PutStr
FileKey:
	jsr	GetKey
	cmp	#K_ESC
	beq	FileBack
	cmp	#K_LEFT
	beq	FileBack
	cmp	#K_RET
	beq	FileChoose
	cmp	#K_RIGHT
	beq	FileChoose
	cmp	#K_UP
	bne	:+
	lda	fsel
	beq	FileKey
	dec	fsel
	lda	fsel
	cmp	ftop
	bcs	:++
	sta	ftop
	bra	:++
:	cmp	#K_DOWN
	bne	FileKey
	lda	fsel
	inc	a
	cmp	fcount
	bcs	FileKey
	sta	fsel
	sec
	sbc	ftop
	cmp	#FROWS
	bcc	:+
	inc	ftop
:	jmp	FileRedraw
FileBack:
	lda	path
	bne	:+
	rts			; back to the drives screen
:	jsr	PathUp
	jmp	FileReload
FileChoose:
	lda	fcount
	beq	FileKey
	lda	fsel
	jsr	FileEntry
	lda	a:0,y		; +0 kind: 1 = folder, 2 = disk image
	cmp	#1
	bne	:+
	jsr	PathAdd		; into the folder (Y = its entry)
	jmp	FileReload
:	lda	fsel
	sta	blk		; +0 entry number
	lda	curdrv
	sta	blk+1		; +1 drive
	stz	blk+2		; +2 no drive to avoid
	lda	#2		; MOUNT
	jsr	DoApi
	bcc	:+
	jmp	ShowErr
:	rts

; Y = address of list entry A
FileEntry:
	rep	#$20
	.a16
	and	#$00FF
	asl	a
	asl	a
	asl	a
	asl	a
	asl	a		; * 32
	clc
	adc	#listbuf
	tay
	sep	#$20
	.a8
	rts

; Draw list entry ftop + line on row FTOP_ROW + line
DrawFile:
	lda	line
	clc
	adc	ftop
	sta	tmp
	jsr	SetInv
	lda	line
	clc
	adc	#FTOP_ROW
	jsr	AtoY
	ldx	#1
	jsr	SetPos
	lda	#' '
	jsr	PutCh
	lda	tmp
	jsr	FileEntry
	phy
	iny
	iny
	iny
	iny			; +4: name
	jsr	PutName
	ply
	lda	a:0,y
	cmp	#1
	bne	:+
	lda	#'/'		; a folder
	jsr	PutCh
:	lda	a:1,y		; +1: the drive it is in now, 0 = none
	beq	:+
	pha
	lda	#33
	jsr	PadTo
	pla
	jsr	PutDrive
:	lda	#39
	jsr	PadTo
	stz	inv
	rts

; path: add the name of folder entry Y, if it fits (63 chars)
PathAdd:
	lda	a:4,y		; name length
	sta	tmp
	lda	path
	beq	:+
	inc	a		; and a '/'
:	clc
	adc	tmp
	cmp	#64
	bcc	:+
	rts			; too long, stay here
:	lda	path
	jsr	AtoX
	beq	:+
	lda	#'/'
	sta	path+1,x
	inx
:	lda	tmp
	beq	:++
:	lda	a:5,y
	sta	path+1,x
	iny
	inx
	dec	tmp
	bne	:-
:	txa
	sta	path
	rts

; path: remove the last folder name
PathUp:
	lda	path
	jsr	AtoX
:	dex
	bmi	:+		; X is 16 bits: 0 - 1 = $FFFF
	lda	path+1,x
	cmp	#'/'
	bne	:-
	txa
	sta	path
	rts
:	stz	path
	rts

; Show "error $nn", wait for a key.  A = error code
ShowErr:
	pha
	stz	inv
	ldy	#20
	ldx	#2
	jsr	SetPos
	ldy	#msg_error
	jsr	PutStr
	pla
	jsr	PutHex
	ldy	#msg_anykey2
	jsr	PutStr
	jmp	GetKey

PutHex:
	pha
	lsr	a
	lsr	a
	lsr	a
	lsr	a
	jsr	@digit
	pla
	and	#$0F
@digit:
	cmp	#10
	bcc	:+
	adc	#6		; carry is set: + 7
:	adc	#'0'
	jmp	PutCh

; ==== Screen routines.  The next char goes to SCREEN + scr ====

; Title bar on row 1
Title:
	lda	#1
	sta	inv
	ldy	#1
	ldx	#1
	jsr	SetPos
	ldy	#msg_title
	jsr	PutStr
	lda	#39
	jsr	PadTo
	stz	inv
	lda	dsel
	sta	cursel
	rts

; Clear the 24 rows (40 columns each, the screen holes are left alone)
ClrScr:
	ldy	#0
:	phy
	ldx	#0
	jsr	SetPos
	ldx	scr
	ldy	#40
	lda	#$A0
:	sta	f:SCREEN,x
	inx
	dey
	bne	:-
	ply
	iny
	cpy	#24
	bcc	:--
	rts

; Y = row, X = column
SetPos:
	stx	col
	rep	#$20
	.a16
	tya
	asl	a
	tax
	lda	rowtab,x
	sta	rowbase
	clc
	adc	col
	sta	scr
	sep	#$20
	.a8
	rts

; Pad with spaces up to column A (not included)
PadTo:
	rep	#$20
	.a16
	and	#$00FF
	clc
	adc	rowbase
	sta	tmpw
	sep	#$20
	.a8
@loop:
	rep	#$20
	.a16
	lda	scr
	cmp	tmpw
	sep	#$20
	.a8
	bcs	:+
	lda	#' '
	jsr	PutCh
	bra	@loop
:	rts

; Print the 0-terminated string at Y
PutStr:
:	lda	a:0,y
	beq	:+
	jsr	PutCh
	iny
	bra	:-
:	rts

; Print the name at Y (length byte, then chars), at most 30 chars
PutName:
	lda	a:0,y
	cmp	#31
	bcc	:+
	lda	#30
:	sta	cnt
:	lda	cnt
	beq	:+
	iny
	lda	a:0,y
	jsr	PutCh
	dec	cnt
	bra	:-
:	rts

; Print char A (ASCII) at scr, normal or inverse (inv)
PutCh:
	phx
	and	#$7F
	pha
	lda	inv
	bne	@inv
	pla
	ora	#$80		; normal
	bra	@out
@inv:
	pla			; with alternate characters on:
	cmp	#$40		;  $00-$1F inverse capitals, $20-$3F inverse
	bcc	@out		;  digits and signs, $40-$5F MouseText,
	cmp	#$60		;  $60-$7F inverse lower case
	bcs	@out
	sbc	#$3F		; carry is clear: - $40
@out:
	ldx	scr
	sta	f:SCREEN,x
	inx
	stx	scr
	plx
	rts

GetKey:
:	lda	f:KBD
	bpl	:-
	sta	f:KBDSTRB
	and	#$7F
	rts

; ---- Data ----
rowtab:	.word	$0400, $0480, $0500, $0580, $0600, $0680, $0700, $0780
	.word	$0428, $04A8, $0528, $05A8, $0628, $06A8, $0728, $07A8
	.word	$0450, $04D0, $0550, $05D0, $0650, $06D0, $0750, $07D0

msg_title:	.byte	" Disks", 0
msg_drvkeys:	.byte	"RETURN:Choose  E:Eject  ESC:Exit", 0
msg_filekeys:	.byte	"RETURN:Choose  ESC:Back", 0
msg_empty:	.byte	"(empty)", 0
msg_nofiles:	.byte	"(no disk images here)", 0
msg_noapi:	.byte	"Disks needs GS40 (disk API 2)", 0
msg_anykey:	.byte	"Press any key", 0
msg_error:	.byte	"Could not do it, error $", 0
msg_anykey2:	.byte	" - a key", 0

save80:	.byte	0
savealt: .byte	0
inv:	.byte	0
line:	.byte	0
cursel:	.byte	0
dsel:	.byte	0
dcount:	.byte	0
curdrv:	.byte	0
fsel:	.byte	0
ftop:	.byte	0
fcount:	.byte	0
tmp:	.byte	0
cnt:	.byte	0
col:	.word	0
scr:	.word	0
rowbase: .word	0
tmpw:	.word	0
path:	.res	64		; length + up to 63 chars, under the folder
blk:	.res	68		; API parameter block
drvbuf:	.res	12*32
listbuf: .res	LIST_MAX*32
