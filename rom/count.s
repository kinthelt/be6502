.segment "CODE"
reset:
  lda #$ff
  sta $6002
  ldx #$00

loop:
  stx $6000
  inx
  jmp loop
