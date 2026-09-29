.setcpu "65C02"
.segment "CODE"
reset:
    lda #$ff
    sta $6002
    ldx #$00

loop:
    stx $6000
    inx
    jsr delay
    bra loop

delay:
    phx
    phy
    ldx #255
outer:
    ldy #255
inner:
    dey
    bne inner
    dex
    bne outer
    ply
    plx
    rts
