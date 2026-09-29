.setcpu "65816"
.debuginfo
.segment "BIOS"

VIA_IORB    = $6000 ; VIA port B I/O register
VIA_IORA    = $6001 ; VIA port A I/O register
VIA_DDRB    = $6002 ; VIA port B data direction register
VIA_DDRA    = $6003 ; VIA port A data direction register
VIA_T1CL    = $6004 ; VIA T1 latches/counter
VIA_T1CH    = $6005 ; VIA T1 high-order counter
VIA_T1LL    = $6006 ; VIA T1 low-order latches
VIA_T1LH    = $6007 ; VIA T1 high-order latches
VIA_T2CL    = $6008 ; VIA T2 latches/counter
VIA_T2CH    = $6009 ; VIA T2 high-order counter
VIA_SR      = $600a ; VIA shift register
VIA_ACR     = $600b ; VIA auxiliary control register
VIA_PCR     = $600c ; VIA peripheral control register
VIA_IFR     = $600d ; VIA interrupt flag register
VIA_IER     = $600e ; VIA interrupt enable register
VIA_NHIORA  = $600f ; VIA no-handshake port A I/O register

ACIA_DR     = $7000 ; ACIA data register
ACIA_SR     = $7001 ; ACIA status/reset
ACIA_CMDR   = $7002 ; ACIA command register
ACIA_CTLR   = $7003 ; ACIA control register

BANK_FIRST  = $01
BANK_LAST   = $07

PHI2_HZ     = 6000000
;PHI2_HZ     = 1000000
BAUD        = 19200
TX_CYCLES = (PHI2_HZ * 10 / BAUD * 105 + 99) / 100
;TX_CYCLES = 3282

; Input a character from the serial interface.
; On return, carry flag indicates whether a key was pressed
; If a key was pressed, the key value will be in the A register
;
; Modifies: flags, A
CHRIN:
  lda ACIA_SR
  and #$08
  beq @no_keypressed
  lda ACIA_DR
  jsr CHROUT
  sec
  rts
@no_keypressed:
  clc
  rts

; Output a character (from the A register) to the serial interface.
;
; Modifies: flags
CHROUT:
    sta     ACIA_DR
    pha
    lda     #<TX_CYCLES
    sta     VIA_T1CL
    lda     #>TX_CYCLES
    sta     VIA_T1CH        ; start timer, clear flag
    pla
@tx_wait:
    bit     VIA_IFR         ; V = T1 timed out
    bvc     @tx_wait
    rts

.include "wozmon.s"

.segment "RESETVEC"
                .word   $0F00          ; NMI vector
                .word   RESET          ; RESET vector
                .word   $0000          ; IRQ vector
