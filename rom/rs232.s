; Assemble with vasm (6502 backend, oldstyle syntax):
;   vasm6502_oldstyle -816 -Fbin -dotdir -o memtest.bin memtest.s

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

    .org $8000

reset:
    ; Set stack to $0100-$01FF
    ldx     #$ff
    txs

    ; VIA port B is all outputs so the status byte can be written.
    lda     #$ff
    sta     VIA_DDRB

    ; VIA port A is all inputs
    lda     #$00
    sta     VIA_DDRA

    ; Blank out all the LEDs
    lda     #$00
    sta     VIA_IORB

    ; ACIA programmed reset
    lda     #$00
    sta     ACIA_SR

    ; ACIA control register
    ; N-8-1 115200 baud
    ;lda     #$10
    ; N-8-1 19200 baud
    lda     #$1f
    ; N-8-1 9600 baud
    ;lda     #$1e
    sta     ACIA_CTLR

    ; ACIA command register
    ; no parity, no echo, no interrupts
    lda     #$0b
    sta     ACIA_CMDR

rx_wait:
    lda     ACIA_SR
    and     #$08 ; Get bit 3 (rx buffer status)
    beq     rx_wait

    lda     ACIA_DR
    jsr     print_char
    jsr     tx ; echo
    jmp     rx_wait

tx:
    sta     ACIA_DR
    pha
tx_wait:
    ;lda     ACIA_SR ; Hardware bug, bit 4 (TDRE) is always 1
    jsr     tx_delay
    jsr     tx_delay
    jsr     tx_delay
    pla
    rts

tx_delay:
    phx
    ldx     #215
tx_delay_1:
    dex
    bne     tx_delay_1
    plx
    rts

print_char:
    sta     VIA_IORB
    rts

unreachable:
rx_wait_t:
    bit     VIA_IORA
    bvs     rx_wait_t

    ror     VIA_IORB
    jsr     half_bit_delay

    ldx     #8
read_bit:
    jsr     bit_delay
    bit     VIA_IORA
    bvs     recv_1
    clc
    jmp     rx_done
recv_1:
    sec
    nop
    nop
rx_done:
    ror
    dex
    bne     read_bit

    sta     VIA_IORB
    jsr     bit_delay
    jmp     rx_wait_t

bit_delay:
    phx
    ldx     #13
bit_delay_1:
    dex
    bne     bit_delay_1
    plx
    rts

half_bit_delay:
    phx
    ldx     #6
half_bit_delay_1:
    dex
    bne     half_bit_delay_1
    plx
    rts


halt:
    jmp     halt

irq:
    ; Clear ACIA interrupt flag
    lda     ACIA_SR
    rti

nmi_stub:
    rti

    .org $ffe4
    word nmi_stub      ; $FFE4 COP    (native)
    word nmi_stub      ; $FFE6 BRK    (native)
    word nmi_stub      ; $FFE8 ABORTB (native)
    word nmi_stub      ; $FFEA NMIB   (native)
    word $0000         ; $FFEC reserved
    word nmi_stub      ; $FFEE IRQB   (native)
    word $0000         ; $FFF0 reserved
    word $0000         ; $FFF2 reserved
    word nmi_stub      ; $FFF4 COP    (emulation)
    word $0000         ; $FFF6 reserved
    word nmi_stub      ; $FFF8 ABORTB (emulation)
    word nmi_stub      ; $FFFA NMIB   (emulation)
    word reset         ; $FFFC RESET
    word irq           ; $FFFE IRQB/BRK (emulation)
