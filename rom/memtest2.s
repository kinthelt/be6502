; memtest2.s
;
; Bank-byte latch race diagnostic for the be6502 build (W65C816S).
;
; Investigates whether the 74HC573 bank-byte latch's LE input can rise
; while PHI2 is still high, letting stray bus data reach the RAM's
; A16-A18 address inputs (and A23 into the GAL) mid-access. If that
; happens, a write meant for bank 0 can partially land in a different
; bank, or a bank-0 read can be corrupted or contended.
;
; Test plan:
;   1. Write a distinct, per-bank sentinel byte at a fixed offset in
;      each of banks $01-$07, chosen not to collide with any bank-0
;      fill pattern below.
;   2. Repeatedly fill all of bank 0's general RAM ($0200-$5FFF) with
;      each of three patterns that exercise D0-D2 and D7 -- $FF, $87,
;      $07 -- the bits the latch feeds to A16-A18 and A23. After each
;      fill, read every byte back to confirm bank 0 is self-consistent,
;      then re-check the bank $01-$07 sentinels are untouched.
;   3. Loop this indefinitely (a soak test -- the race is timing
;      dependent and may not show on every pass), so it can be left
;      running at the target clock speed. The first mismatch, in
;      either direction, halts immediately with $40 on VIA port B so
;      the failure is caught at the moment it happens.
;
; Zero page ($0000-$01FF) holds this program's own pointers and the
; stack, so the bank-0 sweep only covers $0200-$5FFF -- overwriting
; our own state or return addresses would make the test meaningless.
;
; VIA port B: $40 on failure; otherwise it shows a rotating pass
; counter as a heartbeat, since there's no defined "done" for a soak
; test that's meant to be left running.
;
; Assemble with vasm (6502 backend, oldstyle syntax):
;   vasm6502_oldstyle -816 -Fbin -dotdir -o memtest2.bin memtest2.s

VIA_ORB     = $6000            ; VIA port B output register
VIA_DDRB    = $6002            ; VIA port B data direction register

STATUS_FAIL = $40

BANK_FIRST  = $01
BANK_LAST   = $07
BANK_LIMIT  = BANK_LAST+1

SENTINEL_OFFSET_LO = $34       ; fixed offset within each bank $01-$07
SENTINEL_OFFSET_HI = $12       ;   ($1234) -- arbitrary, just non-zero
SENTINEL_BASE      = $e0       ; sentinel byte = SENTINEL_BASE + bank,
                                ;   so $E1-$E7: distinct from every
                                ;   fill pattern below

B0_FIRST_PAGE = $02             ; bank 0 general RAM: $0200-$5FFF
B0_LAST_PAGE  = $5f
B0_PAGE_LIMIT = B0_LAST_PAGE+1

; Direct-page (zero page) working storage.
b0ptr_lo    = $00              ; 16-bit pointer for (dp),y sweeps of
b0ptr_hi    = $01              ;   bank 0's general RAM
lptr_lo     = $02              ; 24-bit pointer for [dp] addressing:
lptr_hi     = $03              ;   lptr_lo/lptr_hi/lptr_bank, low to
lptr_bank   = $04              ;   high -- reaches banks $01-$07
bank_idx    = $05              ; current bank, $01-$07, while setting
                                ;   up or checking sentinels
pattern     = $06              ; current bank-0 fill pattern
expect      = $07              ; expected sentinel value, scratch
pass_count  = $08              ; heartbeat counter shown on the LEDs

    .org $8000

reset:
.as                             ; 8-bit accumulator (emulation-mode reset state)
.xs                             ; 8-bit index registers (emulation-mode reset state)

    sei
    cld
    ldx     #$ff
    txs

    lda     #$ff
    sta     VIA_DDRB
    lda     #$00
    sta     VIA_ORB

    ; Sentinels only need writing once: a real corruption event
    ; destroys one and it stays destroyed until we notice.
    jsr     write_sentinels

    lda     #$00
    sta     pass_count

soak_loop:
    lda     #$ff
    sta     pattern
    jsr     fill_and_check

    lda     #$87
    sta     pattern
    jsr     fill_and_check

    lda     #$07
    sta     pattern
    jsr     fill_and_check

    inc     pass_count
    lda     pass_count
    sta     VIA_ORB
    jmp     soak_loop

; ---------------------------------------------------------------------
; write_sentinels: write SENTINEL_BASE+bank at the fixed offset in
; each of banks $01-$07.
write_sentinels:
    lda     #SENTINEL_OFFSET_LO
    sta     lptr_lo
    lda     #SENTINEL_OFFSET_HI
    sta     lptr_hi
    lda     #BANK_FIRST
    sta     bank_idx

ws_loop:
    lda     bank_idx
    sta     lptr_bank

    lda     #SENTINEL_BASE
    clc
    adc     bank_idx
    sta     [lptr_lo]

    inc     bank_idx
    lda     bank_idx
    cmp     #BANK_LIMIT
    bne     ws_loop
    rts

; ---------------------------------------------------------------------
; check_sentinels: confirm each bank $01-$07 still holds
; SENTINEL_BASE+bank at the fixed offset. Jumps to fail on the first
; mismatch (a plain branch could be out of range from here).
check_sentinels:
    lda     #SENTINEL_OFFSET_LO
    sta     lptr_lo
    lda     #SENTINEL_OFFSET_HI
    sta     lptr_hi
    lda     #BANK_FIRST
    sta     bank_idx

cs_loop:
    lda     bank_idx
    sta     lptr_bank

    lda     #SENTINEL_BASE
    clc
    adc     bank_idx
    sta     expect

    lda     [lptr_lo]
    cmp     expect
    beq     cs_ok
    jmp     fail
cs_ok:
    inc     bank_idx
    lda     bank_idx
    cmp     #BANK_LIMIT
    bne     cs_loop
    rts

; ---------------------------------------------------------------------
; fill_and_check: fill bank 0's general RAM ($0200-$5FFF) with
; `pattern`, read every byte back to confirm it stuck, then confirm
; the bank $01-$07 sentinels are still intact. Jumps to fail on the
; first mismatch, in either direction.
fill_and_check:
    lda     #$00
    sta     b0ptr_lo
    lda     #B0_FIRST_PAGE
    sta     b0ptr_hi

fac_fill_page:
    ldy     #$00
    lda     pattern
fac_fill_byte:
    sta     (b0ptr_lo),y
    iny
    bne     fac_fill_byte

    inc     b0ptr_hi
    lda     b0ptr_hi
    cmp     #B0_PAGE_LIMIT
    bne     fac_fill_page

    lda     #$00
    sta     b0ptr_lo
    lda     #B0_FIRST_PAGE
    sta     b0ptr_hi

fac_check_page:
    ldy     #$00
fac_check_byte:
    lda     (b0ptr_lo),y
    cmp     pattern
    beq     fac_check_ok
    jmp     fail
fac_check_ok:
    iny
    bne     fac_check_byte

    inc     b0ptr_hi
    lda     b0ptr_hi
    cmp     #B0_PAGE_LIMIT
    bne     fac_check_page

    jsr     check_sentinels
    rts

fail:
    lda     #STATUS_FAIL
    sta     VIA_ORB

halt:
    jmp     halt

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
