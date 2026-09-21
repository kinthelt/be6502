  .org $8000
reset:
  lda #$ff
  sta $6002
  ldx #$00

loop:
  stx $6000
  inx
  jmp loop

  .org $fffc
  .word reset
  .word $0000
