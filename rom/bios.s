.setcpu "65816"
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
BAUD        = 115200
;BAUD        = 19200
TX_CYCLES = (PHI2_HZ * 10 / BAUD * 110 + 99) / 100
;TX_CYCLES = 3282

.ifdef EATER
.include "eater_xmodem.s"
.else
.include "xmodem.s"
.endif

; Loads a file via XMODEM/CRC into memory.
; Interrupts must be enabled, as CHRIN is fed by the IRQ handler.
; A register contains the zero page address of a 3-byte (low-order,
; high-order, bank) table holding the address to load the file at.
; The whole file is written there, including the padding at the end of
; its last 128-byte block.
; On return, carry is set if the transfer succeeded, clear if it failed
; or was cancelled.
;
; Modifies: flags
XLOAD:
  pha
  phx
  phy
  tax
  lda 0,x
  sta ptr
  lda 1,x
  sta ptrh
  lda 2,x
  sta ptrb
  jsr XModemRcv
  ply
  plx
  pla
  rts

; Saves memory to a file via XMODEM/CRC.
; Interrupts must be enabled, as CHRIN is fed by the IRQ handler.
; A register contains the zero page address of a 3-byte (low-order,
; high-order, bank) table holding the address of the first byte to save.
; X register contains the zero page address of a 3-byte (low-order,
; high-order, bank) table holding the number of bytes to save.
; The file is padded with zeros to a whole number of 128-byte blocks.
; On return, carry is set if the transfer succeeded, clear if it failed
; or was cancelled.
;
; Modifies: flags
XSAVE:
  pha
  phx
  phy
  lda 0,x
  sta count
  lda 1,x
  sta counth
  lda 2,x
  sta countb
  lda 3,s             ; Caller's A
  tax
  lda 0,x
  sta ptr
  lda 1,x
  sta ptrh
  lda 2,x
  sta ptrb
  jsr XModemSend
  ply
  plx
  pla
  rts

; Sets ACIA's control and command registers
; No return value.
;
; Modifies: flags
ACIA_SETUP:
  ;lda #$1f         ; 8-N-1, 19200 baud
  pha
  lda #$10         ; 8-N-1, 115.2k baud
  sta ACIA_CTLR
  lda #$89         ; No parity, no echo, yes interrupts
  sta ACIA_CMDR
  lda VIA_ACR
  and #$1F         ; Clear T1 mode bits and T2 mode bits
  sta VIA_ACR
  jsr INIT_BUFFER
  cli
  pla
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
  pha
  jsr BUFFER_SIZE
  cmp #$B0 ; Buffer is at most 2/3 full
  bcs @mostly_full
  lda #$09
  sta ACIA_CMDR
@mostly_full:
  pla
  plx
  sec
  rts
@no_keypressed:
  plx
  clc
  rts

; Input a character from the serial interface.
; On return, carry flag indicates whether a key was pressed
; If a key was pressed, it is echoed and the key value will be
; in the A register
;
; Modifies: flags, A
CHRIN_ECHO:
  jsr CHRIN
  bcc @no_keypressed_echo
  jsr CHROUT
@no_keypressed_echo:
  rts

; Output a character (from the A register) to the serial interface.
;
; Modifies: flags
CHROUT:
  sta ACIA_DR
  pha
  lda #<TX_CYCLES
  sta VIA_T2CL
  lda #>TX_CYCLES
  sta VIA_T2CH        ; start timer, clear flag
  lda #$20            ; IFR5 = T2 timed out
@tx_wait:
  bit VIA_IFR         ; V = T1 timed out
  beq @tx_wait
  pla
  rts

; Initialize the read buffer
;
; Modifies: flags, A
INIT_BUFFER:
  lda READ_PTR
  sta WRITE_PTR
  rts

; Return the number of unread bytes in the circular input buffer
;
; Modifies: flags, A
BUFFER_SIZE:
  lda WRITE_PTR
  sec
  sbc READ_PTR
  rts


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; INTERNAL SUBROUTINES
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

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

IRQ_HANDLER:
  lda ACIA_SR
  ; For now, assume the only source of interrupts is
  ; incoming data from the UART
  lda ACIA_DR
  jsr WRITE_BUFFER
  jsr BUFFER_SIZE
  cmp #$EF ; Check if buffer is almost full
  bcc @not_full
  lda #$01
  sta ACIA_CMDR
@not_full:
  rts

; Interrupt request handler (emulation mode)
IRQ_HANDLER_E:
  pha
  phx
  jsr IRQ_HANDLER
  plx
  pla
  rti

; NMI request handler (emulation mode)
NMI_HANDLER_E:
  rti

; Interrupt request handler (native mode)
;
; The interrupted program may be using 16-bit registers, any data bank
; and any direct page, so save all of them, then switch to 8-bit
; registers, data bank $00 and direct page $0000 for the buffer code.
; The CPU has already pushed the program bank and set it to $00, and
; RTI restores the register widths along with the flags.
IRQ_HANDLER_N:
  rep #$30            ; 16-bit A, X, Y so the full registers are saved
.a16
.i16
  pha
  phx
  phy                 ; SEP #$30 below clears the high bytes of X and Y
  phb
  phd
  pea $0000
  pld                 ; Direct page = $0000
  sep #$30            ; 8-bit A, X, Y
.a8
.i8
  phk                 ; Program bank is $00 in an interrupt
  plb                 ; Data bank = $00
  jsr IRQ_HANDLER
  rep #$30
.a16
.i16
  pld
  plb
  ply
  plx
  pla
  rti
.a8
.i8

; NMI, BRK, COP and ABORT handler (native mode)
NMI_HANDLER_N:
  rti

; Long-call wrapper for a 6502-style BIOS routine.
;
; The routine is written for the 65C02: it expects 8-bit registers, the
; direct page at $0000, the data bank at $00, binary (not decimal)
; arithmetic, and to be called with JSR from bank $00. The wrapper lets
; a program call it with JSL instead, from emulation or native mode,
; with any register sizes, from any bank, and with any data bank or
; direct page. The program gets back exactly the state it called with,
; except for:
;
;   - the accumulator, which is passed to the routine and returned from
;     it unchanged by the wrapper. Only the low byte reaches the
;     routine. A native program using a 16-bit accumulator gets back its
;     own high byte with the routine's result in the low byte.
;   - the carry flag, which is the routine's carry result.
;
; Everything else, including the interrupt-disable and decimal flags,
; is put back the way the caller had it.
;
; The routine does not see the caller's carry flag, so it cannot take
; carry as an input. If it does not set carry itself, the carry handed
; back is meaningless (it is whatever the mode switch left there).
;
; The wrapper keeps two copies of the flags on the stack. The first is
; the caller's flags as they were; the routine's carry result is copied
; into it, and it is the last thing restored. The second is pushed
; after the carry flag has been exchanged with the emulation flag, so
; its carry records whether the caller was in emulation mode, and in
; native mode it also records the caller's register sizes. One byte
; cannot do both jobs: on the way out, carry has to hold the mode going
; into the second exchange, and comes out of it holding something else.
; The routine's carry result therefore has to be restored afterwards,
; from its own byte.
;
; Stack while the routine runs, newest first, below the caller's
; return address:
;
;   return address into the wrapper (2 bytes, pushed by JSR)
;   caller's direct page location (2 bytes)
;   caller's data bank (1 byte)
;   caller's Y index register (2 bytes)
;   caller's X index register (2 bytes)
;   mode byte: flags with the caller's mode in the carry bit
;   caller's flags, which will receive the routine's carry result
;
; Index registers are always saved at full 16-bit width. If the caller
; used 8-bit index registers their high bytes are zero, so restoring
; the full width changes nothing.
;
; The wrapper must sit in bank $00, because JSR only reaches routines
; in the bank the wrapper itself is running in.
;
; A caller in emulation mode has its stack in $0100-$01FF. In native
; mode the stack is no longer held to that page, so if it runs past
; $0100 it spills into the direct page instead of wrapping around. Such
; a caller needs 11 free bytes of stack for the wrapper, plus whatever
; the routine itself pushes.
.macro LONG_CALL target
  .local caller_carry_done

  ; Save the caller's mode and switch to native mode.
  php                 ; Caller's flags
  clc
  xce                 ; Native mode; carry now holds the old emulation flag
  php                 ; Mode byte (also holds the caller's register sizes)

  ; Save the caller's registers.
  rep #$10            ; 16-bit index registers, so both bytes are saved
.i16
  phx
  phy
  phb                 ; Caller's data bank
  phd                 ; Caller's direct page

  ; Set up the environment a 6502-style routine expects.
  pea $0000
  pld                 ; Direct page at $0000
  sep #$30            ; 8-bit accumulator and index registers
.a8
.i8
  cld                 ; Binary arithmetic
  phk                 ; The wrapper runs in bank $00...
  plb                 ; ...so this sets the data bank to $00

  jsr target

  ; Copy the routine's carry result into the caller's saved flags,
  ; which are now 10 bytes up the stack once the accumulator is pushed.
  ; Loading, masking and storing below do not change the carry flag.
  pha                 ; Keep the routine's accumulator result
  lda 10,s            ; Caller's saved flags
  and #$FE            ; Clear the saved carry
  bcc caller_carry_done
  ora #$01            ; The routine returned carry set
caller_carry_done:
  sta 10,s
  pla                 ; Routine's accumulator result

  ; Restore the caller's registers, at full 16-bit width.
  rep #$10
.i16
  pld                 ; Caller's direct page
  plb                 ; Caller's data bank
  ply
  plx

  ; Restore the caller's mode, then its flags.
  plp                 ; Mode byte: register sizes, and the mode in carry
  xce                 ; Back to the caller's mode
  plp                 ; Caller's flags, carrying the routine's carry result
  rtl
.a8
.i8
.endmacro

; Long-call entry points for programs in any bank or mode.
; Call with JSL. See LONG_CALL above for what is preserved.
;
; ACIA_SETUP has no entry point here on purpose. It enables interrupts
; as its last step, and the wrapper would put back the caller's
; interrupt-disable flag on the way out, undoing that.
.segment "BIOS_L"

XLOAD_L:
  LONG_CALL XLOAD

XSAVE_L:
  LONG_CALL XSAVE

CHRIN_L:
  LONG_CALL CHRIN

CHROUT_L:
  LONG_CALL CHROUT

INIT_BUFFER_L:
  LONG_CALL INIT_BUFFER

BUFFER_SIZE_L:
  LONG_CALL BUFFER_SIZE

.ifdef EATER
.include "eater_wozmon.s"
.else
.include "wozmon.s"
.endif

.segment "RESETVEC"
                ; Native mode
                .word   NMI_HANDLER_N  ; $FFE4 COP vector
                .word   NMI_HANDLER_N  ; $FFE6 BRK vector
                .word   NMI_HANDLER_N  ; $FFE8 ABORT vector
                .word   NMI_HANDLER_N  ; $FFEA NMI vector
                .word   $0000          ; $FFEC reserved
                .word   IRQ_HANDLER_N  ; $FFEE IRQ vector
                ; Emulation mode
                .word   $0000          ; $FFF0 reserved
                .word   $0000          ; $FFF2 reserved
                .word   NMI_HANDLER_E  ; $FFF4 COP vector
                .word   $0000          ; $FFF6 reserved
                .word   NMI_HANDLER_E  ; $FFF8 ABORT vector
                .word   NMI_HANDLER_E  ; $FFFA NMI vector
                .word   RESET          ; $FFFC RESET vector
                .word   IRQ_HANDLER_E  ; $FFFE IRQ/BRK vector
