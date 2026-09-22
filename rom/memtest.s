; memtest.s
;
; Boot ROM memory test for the be6502 build (W65C816S).
;
; Exercises RAM banks $01-$07 (the AS6C4008, per README.md) in two
; separate passes, using 65C816 direct-page indirect long addressing
; ("[dp]") so a full 24-bit bank:offset address can be reached without
; leaving emulation mode:
;
;   Pass 1 (write): walk a maximal-length 16-bit Galois LFSR (taps
;   16/14/13/11, period 65535) through one full period per bank,
;   writing a pseudo-random byte to each address it lands on. No
;   reads happen during this pass.
;
;   Pass 2 (verify): reseed the LFSR to the same starting value and
;   walk the identical sequence of banks/addresses/bytes again, this
;   time reading each address back and comparing.
;
; Separating the passes this way means every write across every bank
; happens before any read does, rather than interleaving a read right
; after each write -- useful for catching faults that only show up
; when a write isn't immediately followed by an access to the same
; location.
;
; On completion, $80 is written to VIA port B if every comparison in
; pass 2 succeeded, or $40 as soon as the first mismatch is found.
; While a bank is under test (in either pass), its bank number
; ($01-$07) is shown on VIA port B.
;
; Assemble with vasm (6502 backend, oldstyle syntax):
;   vasm6502_oldstyle -816 -Fbin -dotdir -o memtest.bin memtest.s

VIA_ORB     = $6000            ; VIA port B output register
VIA_DDRB    = $6002            ; VIA port B data direction register

STATUS_OK   = $80
STATUS_FAIL = $40

BANK_FIRST  = $01
BANK_LAST   = $07
BANK_LIMIT  = BANK_LAST+1

; Direct-page (zero page) working storage.
ptr_lo      = $00              ; 24-bit pointer for [dp] addressing:
ptr_hi      = $01              ;   ptr_lo/ptr_hi/ptr_bank, low to high
ptr_bank    = $02
rng_lo      = $03              ; 16-bit LFSR state; also supplies the
rng_hi      = $04              ;   low/high bytes of the test offset
count_lo    = $05              ; tests remaining in the current bank
count_hi    = $06
data_byte   = $07              ; pseudo-random pattern under test
mode        = $08              ; $00 = write pass, $01 = verify pass

    .org $8000

reset:
.as                            ; 8-bit accumulator (emulation-mode reset state)
.xs                            ; 8-bit index registers (emulation-mode reset state)

    sei
    cld
    ldx     #$ff
    txs

    ; VIA port B is all outputs so the status byte can be written.
    lda     #$ff
    sta     VIA_DDRB

    ; Blank out all the LEDs
    lda     #$00
    sta     VIA_ORB

    ; Pass 1: write every test value to every bank. Nothing is
    ; checked yet.
    lda     #$00
    sta     mode
    jsr     run_pass

    ; Pass 2: reseed and regenerate the exact same address/data
    ; sequence, this time reading each one back and comparing.
    lda     #$01
    sta     mode
    jsr     run_pass

success:
    lda     #STATUS_OK
    sta     VIA_ORB
    jmp     halt

; ---------------------------------------------------------------------
; run_pass: walk one full LFSR period per bank across banks
; $01-$07, either writing data_byte to each address (mode = $00) or
; reading each address back and comparing against data_byte (mode =
; $01, jumps to fail on the first mismatch). The LFSR is reseeded to
; the same starting value on every call, so both passes visit the
; same banks, addresses, and data bytes in the same order.
run_pass:
    lda     #$ac
    sta     rng_hi
    lda     #$e1
    sta     rng_lo

    lda     #BANK_FIRST
    sta     ptr_bank

rp_bank_loop:
    ; A now holds the bank number about to be tested (BANK_FIRST on
    ; first entry, or ptr_bank as just incremented on later ones) --
    ; show it on the LEDs.
    lda     ptr_bank
    sta     VIA_ORB

    ; One full LFSR period ($FFFF tests) per bank.
    lda     #$ff
    sta     count_lo
    sta     count_hi

rp_test_loop:
    jsr     lfsr_advance

    lda     rng_lo
    sta     ptr_lo
    lda     rng_hi
    sta     ptr_hi

    ; Test pattern: a simple mix of the address bytes, inverted, so it
    ; never trivially matches the address it is stored at.
    lda     rng_lo
    eor     rng_hi
    eor     #$ff
    sta     data_byte

    lda     mode
    bne     rp_verify

    lda     data_byte
    sta     [ptr_lo]
    jmp     rp_next

rp_verify:
    lda     [ptr_lo]
    cmp     data_byte
    beq     rp_next
    jmp     fail

rp_next:
    lda     count_lo
    bne     rp_count_dec
    dec     count_hi
rp_count_dec:
    dec     count_lo
    lda     count_lo
    ora     count_hi
    bne     rp_test_loop

    inc     ptr_bank
    lda     ptr_bank
    cmp     #BANK_LIMIT
    bne     rp_bank_loop
    rts

fail:
    lda     #STATUS_FAIL
    sta     VIA_ORB

halt:
    jmp     halt

; 16-bit Galois LFSR (poly $B400, taps 16/14/13/11) over rng_hi:rng_lo.
lfsr_advance:
    lsr     rng_hi
    ror     rng_lo
    bcc     lfsr_done
    lda     rng_hi
    eor     #$b4
    sta     rng_hi
lfsr_done:
    rts

irq_nmi_stub:
    rti

    .org $ffe4
    word irq_nmi_stub      ; $FFE4 COP    (native)
    word irq_nmi_stub      ; $FFE6 BRK    (native)
    word irq_nmi_stub      ; $FFE8 ABORTB (native)
    word irq_nmi_stub      ; $FFEA NMIB   (native)
    word $0000             ; $FFEC reserved
    word irq_nmi_stub      ; $FFEE IRQB   (native)
    word $0000             ; $FFF0 reserved
    word $0000             ; $FFF2 reserved
    word irq_nmi_stub      ; $FFF4 COP    (emulation)
    word $0000             ; $FFF6 reserved
    word irq_nmi_stub      ; $FFF8 ABORTB (emulation)
    word irq_nmi_stub      ; $FFFA NMIB   (emulation)
    word reset             ; $FFFC RESET
    word irq_nmi_stub      ; $FFFE IRQB/BRK (emulation)
