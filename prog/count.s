; count.s
;
; Counts up on VIA port B, in 65816 native mode.
;
; Load at $1000 and start with 1000N. It also switches to native mode
; itself, so 1000R works too. It never returns to Wozmon.
;
; The counter stays in 8-bit A so each STA writes only port B. The delay
; uses 16-bit Y, so one DEY/BNE loop of 65535 passes replaces the nested
; 255 x 255 loop of the 65C02 version at about the same speed (~328k
; cycles per count).

.setcpu "65816"

VIA_ORB     = $6000            ; VIA port B output register
VIA_DDRB    = $6002            ; VIA port B data direction register

.segment "CODE"
reset:
    clc
    xce                        ; Native mode (already set if started with N)
    sep #$20                   ; 8-bit A
    rep #$10                   ; 16-bit X, Y
.a8
.i16

    lda #$ff
    sta VIA_DDRB               ; Port B all outputs
    lda #$00

loop:
    sta VIA_ORB
    inc a
    jsr delay
    bra loop

delay:
    phy
    ldy #$ffff
@wait:
    dey
    bne @wait
    ply
    rts
