.setcpu "65C02"

.segment "CODE"

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
