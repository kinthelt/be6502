; Larson scanner with fading comet tail, 8 LEDs on VIA port B.
; Brightness via Bit Angle Modulation (BAM): 8 slices weighted 1,2,4..128.
; Assumes: VIA at $6000 (RS0-RS3 on A0-A3), DBR = 0, D = $0000.
; Load at $1000 and run from wozmon with 1000R. Never returns; reset to exit.

        .p816

VIA_ORB  = $6000
VIA_DDRB = $6002

UNIT     = 45       ; delay loop count per BAM unit (~234 cycles). 255 units
                    ; ~= 60k cycles/frame ~= 100 Hz at 6 MHz PHI2.
FPM      = 8        ; frames per head move (lower = faster sweep)

; zero page (clear of wozmon's $24-$2B)
W        = $08      ; current slice weight
CNT      = $09      ; units remaining in slice
POS      = $0A      ; head position 0-7
DIR      = $0B      ; +1 ($01) or -1 ($FF)
FCNT     = $0C      ; frames until next move
BR       = $10      ; 8 bytes: brightness per LED, 0-255
SL       = $18      ; 8 bytes: port pattern for each bit-slice

        .segment "CODE2"

start:  sei
        sep #$30            ; 8-bit A and X/Y (harmless in emulation mode)
        .a8
        .i8
        lda #$FF
        sta VIA_DDRB        ; port B all outputs

        ldx #7
        lda #0
@clr:   sta BR,x
        dex
        bpl @clr

        lda #255
        sta BR              ; head starts on LED 0
        stz POS
        lda #1
        sta DIR
        lda #FPM
        sta FCNT
        jsr build

main:   jsr frame
        dec FCNT
        bne main
        lda #FPM
        sta FCNT

        ldx #7              ; decay every LED to 1/4
@dcy:   lsr BR,x
        lsr BR,x
        dex
        bpl @dcy

        lda POS             ; advance head
        clc
        adc DIR
        sta POS
        cmp #7
        beq @flip
        cmp #0
        bne @set
@flip:  lda DIR
        eor #$FE            ; $01 <-> $FF
        sta DIR
@set:   ldx POS
        lda #255
        sta BR,x
        jsr build
        jmp main

; build: transpose BR[0..7] into SL[0..7].
; Bit k of BR[i] ends up as bit i of SL[k].
build:  ldy #0              ; LED index
@led:   lda BR,y
        ldx #0              ; slice index
@bit:   lsr a
        ror SL,x            ; after 8 LEDs, LED 0's bit lands in bit 0
        inx
        cpx #8
        bne @bit
        iny
        cpy #8
        bne @led
        rts

; frame: output the 8 slices, slice k held for 2^k units.
frame:  ldx #0
        lda #1
        sta W
@slc:   lda SL,x
        sta VIA_ORB
        lda W
        sta CNT
@unit:  ldy #UNIT
@dly:   dey
        bne @dly
        dec CNT
        bne @unit
        asl W
        inx
        cpx #8
        bne @slc
        rts
