; XMODEM/CRC Sender/Receiver for the 65C02
;
; By Daryl Rictor Aug 2002
;
; A simple file transfer program to allow transfers between the SBC and a 
; console device utilizing the x-modem/CRC transfer protocol.
;
;**************************************************************************
; This implementation of XMODEM/CRC does NOT conform strictly to the 
; XMODEM protocol standard in that it (1) does not accurately time character
; reception or (2) fall back to the Checksum mode.
;
; (1) For timing, it uses a timing loop to provide approximate delays,
; calibrated from PHI2_HZ in bios.s.
;
; (2) Most modern terminal programs support XMODEM/CRC which can detect a
; wider range of transmission errors so the fallback to the simple checksum
; calculation was not implemented to save space.
;**************************************************************************
;
; Changes for this build (W65C816S, BIOS in ROM):
;
;   - Addresses are 24 bits (bank:offset) and transfers run across bank
;     boundaries ($01:FFFF -> $02:0000).
;   - Files are raw memory images. There is no load address in the first
;     block: the caller says where a received file goes, and a sent file
;     holds only the bytes asked for.
;   - XModemSend takes a byte count rather than an end address, and ends
;     the transfer with a proper EOT/ACK handshake.
;   - Both routines return carry set on success and carry clear on failure
;     or cancel (ESC from the keyboard, or CAN from the other end), instead
;     of executing BRK.
;   - The receiver ACKs and drops a repeated block (its ACK was lost),
;     NAKs a block with a damaged header, and gives up after 10 errors in
;     a row, sending CAN to the other end.
;   - The sender ignores stray characters (such as extra "C"s) while it
;     waits for an ACK or NAK.
;
; Like any XMODEM transfer, a file is sent in whole 128 byte blocks. The
; sender pads the last block with zeros, and the receiver writes every
; byte of every block, so loading a file may write up to 127 bytes of
; padding past its end.
;
;-------------------------- The Code ----------------------------
;
; zero page variables
;
blkno		=	$36		; block number 
errcnt		=	$37		; error counter 10 is the limit

crc		=	$38		; CRC lo byte  (two byte variable)
crch		=	$39		; CRC hi byte  

ptr		=	$3a		; data pointer (three byte variable)
ptrh		=	$3b		;   "    "
ptrb		=	$3c		;   "    "	bank

count		=	$3d		; bytes left to send (three byte variable)
counth		=	$3e		;   "    "
countb		=	$3f		;   "    "

retry		=	$40		; timing loop, inner counter
retryh		=	$41		; timing loop, middle counter
retry2		=	$42		; timing loop, ticks of ~0.1 second

;
; non-zero page variables and buffers
;
.pushseg
.segment "XMODEM_BUFFER"
Rbuff:		.res	$84		; <blk #> <~blk #> <128 bytes> <CRCH> <CRCL>
.popseg

;
; Timing. GetByte polls CHRIN in a loop of 54 cycles; XM_TICK runs of
; 256 polls take about 0.1 second at PHI2_HZ.
;
XM_TICK		=	(PHI2_HZ / 10 + 6912) / 13824
.if XM_TICK < 1 .or XM_TICK > 255
.error "PHI2_HZ out of range for the XMODEM timing loop"
.endif

TICKS_1S	=	10		; ~1 second, in GetByte ticks
TICKS_3S	=	30		; ~3 seconds
TICKS_10S	=	100		; ~10 seconds

;
; XMODEM Control Character Constants
SOH		=	$01		; start block
EOT		=	$04		; end of text marker
ACK		=	$06		; good block acknowledged
NAK		=	$15		; bad block acknowledged
CAN		=	$18		; cancel
.ifndef CR
CR		=	$0d		; carriage return
.endif
.ifndef LF
LF		=	$0a		; line feed
.endif
ESC		=	$1b		; ESC to exit

;
;^^^^^^^^^^^^^^^^^^^^^^ Start of Program ^^^^^^^^^^^^^^^^^^^^^^
;
; Xmodem/CRC transfer routines
; By Daryl Rictor, August 8, 2002
;
; v1.0  released on Aug 8, 2002.
;
;
; XModemSend: send count/counth/countb bytes starting at ptr/ptrh/ptrb.
; Returns carry set on success, clear on failure or cancel.
;
XModemSend:	jsr	PrintMsg	; send prompt and info
		lda	#$01		;
		sta	blkno		; set block # to 1
Wait4CRC:	lda	#TICKS_3S	; 3 seconds
		sta	retry2		;
		jsr	GetByte		;
		bcc	Wait4CRC	; wait for something to come in...
		cmp	#$43		; is it the "C" to start a CRC xfer?
		beq	LdBuffer	; yes
		cmp	#ESC		; is it a cancel? <Esc> Key
		beq	SCancel		; yes
		cmp	#CAN		; cancelled by the receiver?
		bne	Wait4CRC	; No, wait for another character
SCancel:	jmp	Cancel		; send CAN, print abort msg and exit

LdBuffer:	lda	count		; anything left to send?
		ora	counth		;
		ora	countb		;
		beq	SendEOT		; no, end the transfer
		lda	blkno		; 
		sta	Rbuff		; save in 1st byte of buffer
		eor	#$FF		; 
		sta	Rbuff+1		; save 1's comp of blkno next
		ldx	#$02		; init buffer index
LdBuff1:	lda	[ptr]		; get a data byte
		sta	Rbuff,x		; save it in the buffer
		inc	ptr		; Inc address pointer
		bne	LdBuff2		;
		inc	ptrh		;
		bne	LdBuff2		;
		inc	ptrb		; carry into the bank
LdBuff2:	lda	count		; decrement the byte count
		bne	LdBuff3		;
		lda	counth		;
		bne	LdBuff4		;
		dec	countb		;
LdBuff4:	dec	counth		;
LdBuff3:	dec	count		;
		inx			;
		cpx	#$82		; last byte in block?
		beq	SCalcCRC	; yes, calc CRC
		lda	count		; any bytes left?
		ora	counth		;
		ora	countb		;
		bne	LdBuff1		; yes, get the next
LdBuff5:	stz	Rbuff,x		; Fill rest of 128 bytes with $00
		inx			;
		cpx	#$82		; Are we at the end of the 128 byte block?
		bne	LdBuff5		; no, keep filling
SCalcCRC:	jsr 	CalcCRC
		lda	crch		; save Hi byte of CRC to buffer
		sta	Rbuff,y		;
		iny			;
		lda	crc		; save lo byte of CRC to buffer
		sta	Rbuff,y		;
		stz	errcnt		; error counter set to 0
Resend:		ldx	#$00		;
		lda	#SOH
		jsr	CHROUT		; send SOH
SendBlk:	lda	Rbuff,x		; Send 132 bytes in buffer to the console
		jsr	CHROUT		;
		inx			;
		cpx	#$84		; last byte?
		bne	SendBlk		; no, get next
		jsr	GetReply	; Wait for Ack/Nack
		bcc	Seterror	; No reply after 10 seconds, or NAK
		inc	blkno		; ACK, send next block
		bra	LdBuffer	;
Seterror:	jsr	CountErr	; Inc error counter
		bcc	Resend		; under 10 errors, resend block
SCancel2:	jmp	Cancel		; too many errors or cancelled

SendEOT:	stz	errcnt		; error counter set to 0
SendEOT1:	lda	#EOT		; tell the receiver we're done
		jsr	CHROUT		;
		jsr	GetReply	; Wait for Ack/Nack
		bcs	SDone		; ACK, all done
		jsr	CountErr	; NAK or no reply, inc error counter
		bcc	SendEOT1	; under 10 errors, send EOT again
		bra	SCancel2	; too many errors or cancelled
SDone:		jmp	Print_Good	; All Done..Print msg and exit (carry set)

;
; Wait up to 10 seconds for the receiver's reply to a block or EOT.
; Returns carry set for ACK; carry clear for NAK or a timeout, with A=NAK;
; and pulls the return address and cancels for ESC or CAN. Anything else
; is ignored.
;
GetReply:	lda	#TICKS_10S	; 10 second delay
		sta	retry2		;
GetReply1:	jsr	GetByte		; Wait for Ack/Nack
		bcc	GetReply3	; No chr received after 10 seconds
		cmp	#ACK		; Chr received... is it:
		beq	GetReply2	; ACK, return carry set
		cmp	#NAK		; 
		beq	GetReply3	; NAK, return carry clear
		cmp	#ESC		;
		beq	GetReply4	; Esc pressed to abort
		cmp	#CAN		;
		beq	GetReply4	; cancelled by the receiver
		dec	retry2		; anything else: ignore it, but let it
		bne	GetReply1	; use up a tick of the 10 seconds
GetReply3:	lda	#NAK		;
		clc			;
GetReply2:	rts			;
GetReply4:	pla			; drop the return address
		pla			;
		jmp	Cancel		; and cancel the transfer

;
; Count an error. Returns carry set once there have been 10 in a row
; (Xmodem spec for failure).
;
CountErr:	inc	errcnt		; Inc error counter
		lda	errcnt		; 
		cmp	#$0A		; are there 10 errors?
		rts			; carry set if so

;
; XModemRcv: receive a file into memory starting at ptr/ptrh/ptrb.
; Returns carry set on success, clear on failure or cancel.
;
XModemRcv:	jsr	PrintMsg	; send prompt and info
		jsr	Flush		; drop anything left over from the command line
		lda	#$01
		sta	blkno		; set block # to 1
		stz	errcnt		; error counter set to 0
StartCrc:	lda	#$43		; "C" start with CRC mode
		jsr	CHROUT		; send it
		lda	#TICKS_3S	
		sta	retry2		; set loop counter for ~3 sec delay
		jsr	GetByte		; wait for input
               	bcs	GotByte		; byte received, process it
		bcc	StartCrc	; resend "C"

StartBlk:	lda	#TICKS_10S	; 
		sta	retry2		; set loop counter for ~10 sec delay
		jsr	GetByte		; get first byte of block
		bcc	BadCrc		; timed out, send NAK
GotByte:	cmp	#ESC		; quitting?
		beq	RCancel		; yes
		cmp	#CAN		; cancelled by the sender?
		beq	RCancel		; yes
		cmp	#SOH		; start of block?
		beq	BegBlk		; yes
		cmp	#EOT		;
		bne	BadCrc		; Not SOH or EOT, so flush buffer & send NAK	
		jmp	RDone		; EOT - all done!
BegBlk:		ldx	#$00
GetBlk:		lda	#TICKS_1S	; 1 sec window to receive characters
		sta 	retry2		;
GetBlk1:	jsr	GetByte		; get next character
		bcc	BadCrc		; chr rcv error, flush and send NAK
GetBlk2:	sta	Rbuff,x		; good char, save it in the rcv buffer
		inx			; inc buffer pointer	
		cpx	#$84		; <01> <FE> <128 bytes> <CRCH> <CRCL>
		bne	GetBlk		; get 132 characters
		lda	Rbuff		; get block # from buffer
		eor	Rbuff+1		; with its 1's comp the result is $FF
		inc	a		; and this makes it zero
		bne	BadCrc		; damaged header, send NAK
		jsr	CalcCRC		; calc CRC
		lda	Rbuff,y		; get hi CRC from buffer
		cmp	crch		; compare to calculated hi CRC
		bne	BadCrc		; bad crc, send NAK
		iny			;
		lda	Rbuff,y		; get lo CRC from buffer
		cmp	crc		; compare to calculated lo CRC
		bne	BadCrc		; bad crc, send NAK
		lda	Rbuff		; get block # from buffer
		cmp	blkno		; compare to expected block #	
		beq	GoodCrc		; matched!
		inc	a		; 
		cmp	blkno		; the previous block again?
		beq	SendAck		; yes, our ACK was lost: ACK and drop it
RCancel:	jmp	Cancel		; out of sequence - fatal error
BadCrc:		jsr	CountErr	; Inc error counter
		bcs	RCancel		; 10 errors, give up
		jsr	Flush		; flush the input port
		lda	#NAK		;
		jsr	CHROUT		; send NAK to resend block
		bra	StartBlk	; start over, get the block again			
GoodCrc:	ldx	#$02		;
CopyBlk3:	lda	Rbuff,x		; get data byte from buffer
		sta	[ptr]		; save to target
		inc	ptr		; point to next address
		bne	CopyBlk4	; did it step over page boundary?
		inc	ptrh		; adjust high address for page crossing
		bne	CopyBlk4	; did it step over bank boundary?
		inc	ptrb		; adjust bank for bank crossing
CopyBlk4:	inx			; point to next data byte
		cpx	#$82		; is it the last byte
		bne	CopyBlk3	; no, get the next one
IncBlk:		inc	blkno		; done.  Inc the block #
SendAck:	stz	errcnt		; error counter set to 0
		lda	#ACK		; send ACK
		jsr	CHROUT		;
		jmp	StartBlk	; get next block

RDone:		lda	#ACK		; last block, send ACK and exit.
		jsr	CHROUT		;
		jsr	Flush		; get leftover characters, if any
		jmp	Print_Good	; print msg and exit (carry set)

;=========================================================================
;
; subroutines
;
;
;
; Wait up to retry2 ticks of ~0.1 second for a character.
; Returns carry set with the character in A, or carry clear on a timeout.
;
GetByte:	stz	retry		; 256 polls per pass of the middle loop
GetByte1:	lda	#XM_TICK	; passes per tick
		sta	retryh		;
StartCrcLp:	jsr	CHRIN		; get chr from serial port, don't wait 
		bcs	GetByte2	; got one, so exit
		dec	retry		; no character received, so dec counter
		bne	StartCrcLp	;
		dec	retryh		; dec middle byte of counter
		bne	StartCrcLp	;
		dec	retry2		; dec hi byte of counter
		bne	GetByte1	; look for character again
		clc			; if loop times out, CLC, else SEC and return
GetByte2:	rts			; with character in "A"
;
Flush:		lda	#TICKS_1S	; flush receive buffer
		sta	retry2		; flush until empty for ~1 sec.
Flush1:		jsr	GetByte		; read the port
		bcs	Flush		; if chr recvd, wait for another
		rts			; else done
;
; Cancel the transfer: tell the other end, wait for it to go quiet, then
; print the error message. Returns carry clear.
;
Cancel:		lda	#CAN		; two CANs cancel a transfer
		jsr	CHROUT		;
		jsr	CHROUT		;
		jsr	Flush		; drain whatever is still coming in
		ldx	#ErrMsg-Msg	; PRINT Error message
		jsr	PrtMsg1		;
		clc			; failed
		rts
;
Print_Good:	ldx	#GoodMsg-Msg	; PRINT Good Transfer message
		jsr	PrtMsg1		;
		sec			; succeeded
		rts
;
PrintMsg:	ldx	#$00		; PRINT starting message
PrtMsg1:	lda   	Msg,x		
		beq	PrtMsg2			
		jsr	CHROUT
		inx
		bne	PrtMsg1
PrtMsg2:	rts
Msg:		.byte	CR, LF, "Begin XMODEM/CRC transfer.  Press <Esc> to abort..."
		.byte  	CR, LF
		.byte   0
ErrMsg:		.byte 	CR, LF, "Transfer Error!"
		.byte  	CR, LF
		.byte   0
GoodMsg:	.byte	CR, LF, "Transfer Successful!"
		.byte  	CR, LF
		.byte   0
.assert	* - Msg <= $100, error, "XMODEM messages must fit in 256 bytes"

;
;
;=========================================================================
;
;
;  CRC subroutines 
;
;
CalcCRC:	lda	#$00		; yes, calculate the CRC for the 128 bytes
		sta	crc		;
		sta	crch		;
		ldy	#$02		;
CalcCRC1:	lda	Rbuff,y		;
		eor 	crc+1 		; Quick CRC computation with lookup tables
       		tax		 	; updates the two bytes at crc & crc+1
       		lda 	crc		; with the byte send in the "A" register
       		eor 	crchi,X
       		sta 	crc+1
      	 	lda 	crclo,X
       		sta 	crc
		iny			;
		cpy	#$82		; done yet?
		bne	CalcCRC1	; no, get next
		rts			; y=82 on exit
;
; The following tables are used to calculate the CRC for the 128 bytes
; in the xmodem data blocks.  You can use these tables if you plan to 
; store this program in ROM.  If you choose to build them at run-time, 
; then just delete them and define the two labels: crclo & crchi.
;
; low byte CRC lookup table (should be page aligned)
;		*= $FD00
crclo:
 .byte $00,$21,$42,$63,$84,$A5,$C6,$E7,$08,$29,$4A,$6B,$8C,$AD,$CE,$EF
 .byte $31,$10,$73,$52,$B5,$94,$F7,$D6,$39,$18,$7B,$5A,$BD,$9C,$FF,$DE
 .byte $62,$43,$20,$01,$E6,$C7,$A4,$85,$6A,$4B,$28,$09,$EE,$CF,$AC,$8D
 .byte $53,$72,$11,$30,$D7,$F6,$95,$B4,$5B,$7A,$19,$38,$DF,$FE,$9D,$BC
 .byte $C4,$E5,$86,$A7,$40,$61,$02,$23,$CC,$ED,$8E,$AF,$48,$69,$0A,$2B
 .byte $F5,$D4,$B7,$96,$71,$50,$33,$12,$FD,$DC,$BF,$9E,$79,$58,$3B,$1A
 .byte $A6,$87,$E4,$C5,$22,$03,$60,$41,$AE,$8F,$EC,$CD,$2A,$0B,$68,$49
 .byte $97,$B6,$D5,$F4,$13,$32,$51,$70,$9F,$BE,$DD,$FC,$1B,$3A,$59,$78
 .byte $88,$A9,$CA,$EB,$0C,$2D,$4E,$6F,$80,$A1,$C2,$E3,$04,$25,$46,$67
 .byte $B9,$98,$FB,$DA,$3D,$1C,$7F,$5E,$B1,$90,$F3,$D2,$35,$14,$77,$56
 .byte $EA,$CB,$A8,$89,$6E,$4F,$2C,$0D,$E2,$C3,$A0,$81,$66,$47,$24,$05
 .byte $DB,$FA,$99,$B8,$5F,$7E,$1D,$3C,$D3,$F2,$91,$B0,$57,$76,$15,$34
 .byte $4C,$6D,$0E,$2F,$C8,$E9,$8A,$AB,$44,$65,$06,$27,$C0,$E1,$82,$A3
 .byte $7D,$5C,$3F,$1E,$F9,$D8,$BB,$9A,$75,$54,$37,$16,$F1,$D0,$B3,$92
 .byte $2E,$0F,$6C,$4D,$AA,$8B,$E8,$C9,$26,$07,$64,$45,$A2,$83,$E0,$C1
 .byte $1F,$3E,$5D,$7C,$9B,$BA,$D9,$F8,$17,$36,$55,$74,$93,$B2,$D1,$F0 

; hi byte CRC lookup table (should be page aligned)
;		*= $FE00
crchi:
 .byte $00,$10,$20,$30,$40,$50,$60,$70,$81,$91,$A1,$B1,$C1,$D1,$E1,$F1
 .byte $12,$02,$32,$22,$52,$42,$72,$62,$93,$83,$B3,$A3,$D3,$C3,$F3,$E3
 .byte $24,$34,$04,$14,$64,$74,$44,$54,$A5,$B5,$85,$95,$E5,$F5,$C5,$D5
 .byte $36,$26,$16,$06,$76,$66,$56,$46,$B7,$A7,$97,$87,$F7,$E7,$D7,$C7
 .byte $48,$58,$68,$78,$08,$18,$28,$38,$C9,$D9,$E9,$F9,$89,$99,$A9,$B9
 .byte $5A,$4A,$7A,$6A,$1A,$0A,$3A,$2A,$DB,$CB,$FB,$EB,$9B,$8B,$BB,$AB
 .byte $6C,$7C,$4C,$5C,$2C,$3C,$0C,$1C,$ED,$FD,$CD,$DD,$AD,$BD,$8D,$9D
 .byte $7E,$6E,$5E,$4E,$3E,$2E,$1E,$0E,$FF,$EF,$DF,$CF,$BF,$AF,$9F,$8F
 .byte $91,$81,$B1,$A1,$D1,$C1,$F1,$E1,$10,$00,$30,$20,$50,$40,$70,$60
 .byte $83,$93,$A3,$B3,$C3,$D3,$E3,$F3,$02,$12,$22,$32,$42,$52,$62,$72
 .byte $B5,$A5,$95,$85,$F5,$E5,$D5,$C5,$34,$24,$14,$04,$74,$64,$54,$44
 .byte $A7,$B7,$87,$97,$E7,$F7,$C7,$D7,$26,$36,$06,$16,$66,$76,$46,$56
 .byte $D9,$C9,$F9,$E9,$99,$89,$B9,$A9,$58,$48,$78,$68,$18,$08,$38,$28
 .byte $CB,$DB,$EB,$FB,$8B,$9B,$AB,$BB,$4A,$5A,$6A,$7A,$0A,$1A,$2A,$3A
 .byte $FD,$ED,$DD,$CD,$BD,$AD,$9D,$8D,$7C,$6C,$5C,$4C,$3C,$2C,$1C,$0C
 .byte $EF,$FF,$CF,$DF,$AF,$BF,$8F,$9F,$6E,$7E,$4E,$5E,$2E,$3E,$0E,$1E 
;
;
; End of File
;
