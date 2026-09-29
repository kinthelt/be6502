.setcpu "65C02"
.debuginfo

.zeropage
.ifdef ZP_START0
.org ZP_START0
.endif
READ_PTR:    .res 1
WRITE_PTR:   .res 1

.segment "INPUT_BUFFER"
INPUT_BUFFER: .res $100

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

; Dummy functions, to be completed later

LOAD:
  rts

SAVE:
  rts

; Sets ACIA's control and command registers
; No return value.
;
; Modifies: A
RS232_SETUP:
  ;lda #$1f         ; 8-N-1, 19200 baud
  lda #$10         ; 8-N-1, 115.2k baud
  sta ACIA_CTLR
  lda #$89         ; No parity, no echo, yes interrupts
  sta ACIA_CMDR
  cld              ; Clear decimal arithmetic mode
  jsr INIT_BUFFER
  cli
  rts

; Input a character from the serial interface.
; On return, carry flag indicates whether a key was pressed
; If a key was pressed, the key value will be in the A register
;
; Modifies: flags, A
CHRIN:
  phx
  jsr BUFFER_SIZE
  beq @no_keypressed
  jsr READ_BUFFER
  jsr CHROUT
  plx
  sec
  rts
@no_keypressed:
  plx
  clc
  rts

; Output a character (from the A register) to the serial interface.
;
; Modifies: flags
CHROUT:
  sta ACIA_DR
  pha
  lda #<TX_CYCLES
  sta VIA_T1CL
  lda #>TX_CYCLES
  sta VIA_T1CH        ; start timer, clear flag
  pla
@tx_wait:
  bit VIA_IFR         ; V = T1 timed out
  bvc @tx_wait
  rts

; Initialize the read buffer
;
; Modifies: flags, A
INIT_BUFFER:
  lda READ_PTR
  sta WRITE_PTR
  rts

; Write a character to the circular input buffer
;
; Reads: A
; Modifies: flags, X
WRITE_BUFFER:
  ldx WRITE_PTR
  sta INPUT_BUFFER,x
  inc WRITE_PTR
  rts

; Read a character from the circular input buffer
;
; Modifies: flags, A, X
READ_BUFFER:
  ldx READ_PTR
  lda INPUT_BUFFER,x
  inc READ_PTR
  rts

; Return the number of unread bytes in the circular input buffer
;
; Modifies: flags, A
BUFFER_SIZE:
  lda WRITE_PTR
  sec
  sbc READ_PTR
  rts

; Interrupt request handler (emulation mode)
IRQ_HANDLER_E:
  pha
  phx
  lda ACIA_SR
  ; For now, assume the only source of interrupts is
  ; incoming data from the UART
  lda ACIA_DR
  jsr WRITE_BUFFER
  plx
  pla
  rti

; NMI request handler (emulation mode)
NMI_HANDLER_E:
  rti

.include "wozmon.s"

.segment "RESETVEC"
                .word   NMI_HANDLER_E  ; NMI vector
                .word   RESET          ; RESET vector
                .word   IRQ_HANDLER_E  ; IRQ vector
