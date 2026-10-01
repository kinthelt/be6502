.setcpu "65816"
.segment "WOZMON"

; Wozmon, extended for the W65C816S.
;
; Wozmon is too large to fit below the native-mode vectors at $FFE4, so
; it now starts at $FE00 (FE00R restarts it) and the BIOS at $FD00.
;
; Addresses are 24 bits (bank:offset), entered as up to six hex digits.
; Four or fewer digits give bank $00, so classic Wozmon input behaves as
; before; the bank is the digits above the low four:
;
;   1000          examine $00:1000
;   21000         examine $02:1000
;   21000.2100F   block examine $02:1000-$02:100F
;   21000: A9 00  store into $02:1000, $02:1001
;   21000R        run $02:1000 in emulation mode
;   21000N        run $02:1000 in native mode
;
; Examine and store run across bank boundaries ($01:FFFF -> $02:0000).
; Addresses are printed as six hex digits (BBHHLL), so they can be typed
; straight back in.
;
; R runs the program in emulation mode with a JML, like the classic JMP.
; In emulation mode an interrupt forces the program bank to $00 and RTI
; does not restore it, so when the target is outside bank $00 R disables
; interrupts (SEI) before jumping. Such a program cannot use CHRIN, as
; the input buffer is filled by the IRQ handler.
;
; N switches to native mode (8-bit A, X, Y, and the stack, direct page
; and data bank unchanged) and calls the program as if by JSL. The
; program may return with RTL, in any register width and with any data
; bank or direct page; Wozmon then switches back to emulation mode,
; restores the data bank and direct page to $00/$0000, clears decimal
; mode, re-enables interrupts, and prompts for a new line. Interrupts stay enabled and are handled by the native-mode
; vectors in the BIOS.

XAML  = $24                            ; Last "opened" location Low
XAMH  = $25                            ; Last "opened" location High
XAMB  = $26                            ; Last "opened" location Bank
STL   = $27                            ; Store address Low
STH   = $28                            ; Store address High
STB   = $29                            ; Store address Bank
L     = $2A                            ; Hex value parsing Low
H     = $2B                            ; Hex value parsing High
BK    = $2C                            ; Hex value parsing Bank
YSAV  = $2D                            ; Used to see if hex value is given
MODE  = $2E                            ; $00=XAM, $7F=STOR, $AE=BLOCK XAM

IN    = $0200                          ; Input buffer

RESET:
                JSR     ACIA_SETUP
                LDA     #$1B           ; Begin with escape.

NOTCR:
                CMP     #$08           ; Backspace key?
                BEQ     BACKSPACE      ; Yes.
                CMP     #$1B           ; ESC?
                BEQ     ESCAPE         ; Yes.
                INY                    ; Advance text index.
                BPL     NEXTCHAR       ; Auto ESC if line longer than 127.

ESCAPE:
                LDA     #$5C           ; "\".
                JSR     ECHO           ; Output it.

GETLINE:
                LDA     #$0D           ; Send CR
                JSR     ECHO
                LDA     #$0A           ; Send LF
                JSR     ECHO

                LDY     #$01           ; Initialize text index.
BACKSPACE:      DEY                    ; Back up text index.
                BMI     GETLINE        ; Beyond start of line, reinitialize.

NEXTCHAR:
                JSR     CHRIN          ; From BIOS
                BCC     NEXTCHAR       ; Loop until ready.
                STA     IN,Y           ; Add to text buffer.
                CMP     #$0D           ; CR?
                BNE     NOTCR          ; No.

                LDY     #$FF           ; Reset text index.
                LDA     #$00           ; For XAM mode.
                TAX                    ; X=0.
SETBLOCK:
                ASL
SETSTOR:
                ASL                    ; Leaves $7B if setting STOR mode.
                STA     MODE           ; $00 = XAM, $74 = STOR, $B8 = BLOK XAM.
BLSKIP:
                INY                    ; Advance text index.
NEXTITEM:
                LDA     IN,Y           ; Get character.
                CMP     #$0D           ; CR?
                BEQ     GETLINE        ; Yes, done this line.
                CMP     #$2E           ; "."?
                BCC     BLSKIP         ; Skip delimiter.
                BEQ     SETBLOCK       ; Set BLOCK XAM mode.
                CMP     #$3A           ; ":"?
                BEQ     SETSTOR        ; Yes, set STOR mode.
                CMP     #$52           ; "R"?
                BEQ     RUNPROG        ; Yes, run user program.
                CMP     #$4E           ; "N"?
                BEQ     RUNNATIVE      ; Yes, run user program in native mode.
                STX     L              ; $00 -> L.
                STX     H              ;    and H.
                STX     BK             ;    and BK.
                STY     YSAV           ; Save Y for comparison

NEXTHEX:
                LDA     IN,Y           ; Get character for hex test.
                EOR     #$30           ; Map digits to $0-9.
                CMP     #$0A           ; Digit?
                BCC     DIG            ; Yes.
                ADC     #$88           ; Map letter "A"-"F" to $FA-FF.
                CMP     #$FA           ; Hex letter?
                BCC     NOTHEX         ; No, character not hex.
DIG:
                ASL
                ASL                    ; Hex digit to MSD of A.
                ASL
                ASL

                LDX     #$04           ; Shift count.
HEXSHIFT:
                ASL                    ; Hex digit left, MSB to carry.
                ROL     L              ; Rotate into LSD.
                ROL     H              ; Rotate into MSD's.
                ROL     BK             ; Rotate into bank.
                DEX                    ; Done 4 shifts?
                BNE     HEXSHIFT       ; No, loop.
                INY                    ; Advance text index.
                BNE     NEXTHEX        ; Always taken. Check next character for hex.

NOTHEX:
                CPY     YSAV           ; Check if L, H, BK empty (no hex digits).
                BEQ     ESCAPE         ; Yes, generate ESC sequence.

                BIT     MODE           ; Test MODE byte.
                BVC     NOTSTOR        ; B6=0 is STOR, 1 is XAM and BLOCK XAM.

                LDA     L              ; LSD's of hex data.
                STA     [STL]          ; Store at current 24-bit 'store index'.
                INC     STL            ; Increment store index.
                BNE     TONEXTITEM     ; Get next item (no carry).
                INC     STH            ; Add carry to 'store index' high order.
                BNE     TONEXTITEM     ; Get next item (no carry).
                INC     STB            ; Add carry to 'store index' bank.
TONEXTITEM:     JMP     NEXTITEM       ; Get next command item.

RUNPROG:
                LDA     XAMB           ; Target outside bank $00?
                BEQ     RUNJML         ; No, leave interrupts alone.
                SEI                    ; Yes, emulation IRQs would lose the bank.
RUNJML:         JML     [XAML]         ; Run at current XAM index.

RUNNATIVE:
                CLC
                XCE                    ; Native mode. A, X, Y stay 8-bit.
                PHK                    ; Push a JSL-style return address
                PEA     NATIVERET-1    ;  of $00:NATIVERET for RTL.
                JML     [XAML]         ; Run at current XAM index.
NATIVERET:
                SEC
                XCE                    ; Back to emulation mode, 8-bit registers.
                PHK
                PLB                    ; Data bank = $00.
                PEA     $0000
                PLD                    ; Direct page = $0000.
                CLD                    ; Hex parsing needs binary mode.
                CLI                    ; CHRIN needs the IRQ handler.
                JMP     GETLINE        ; Prompt for the next line.

NOTSTOR:
                BMI     XAMNEXT        ; B7 = 0 for XAM, 1 for BLOCK XAM.

                LDX     #$03           ; Byte count.
SETADR:         LDA     L-1,X          ; Copy hex data to
                STA     STL-1,X        ;  'store index'.
                STA     XAML-1,X       ; And to 'XAM index'.
                DEX                    ; Next of 3 bytes.
                BNE     SETADR         ; Loop unless X = 0.

NXTPRNT:
                BNE     PRDATA         ; NE means no address to print.
                LDA     #$0D           ; CR.
                JSR     ECHO           ; Output it.
                LDA     #$0A           ; Send LF
                JSR     ECHO
                LDA     XAMB           ; 'Examine index' bank byte.
                JSR     PRBYTE         ; Output it in hex format.
                LDA     XAMH           ; 'Examine index' high-order byte.
                JSR     PRBYTE         ; Output it in hex format.
                LDA     XAML           ; Low-order 'examine index' byte.
                JSR     PRBYTE         ; Output it in hex format.
                LDA     #$3A           ; ":".
                JSR     ECHO           ; Output it.

PRDATA:
                LDA     #$20           ; Blank.
                JSR     ECHO           ; Output it.
                LDA     [XAML]         ; Get data byte at 24-bit 'examine index'.
                JSR     PRBYTE         ; Output it in hex format.
XAMNEXT:        STX     MODE           ; 0 -> MODE (XAM mode).
                LDA     XAML
                CMP     L              ; Compare 'examine index' to hex data.
                LDA     XAMH
                SBC     H
                LDA     XAMB
                SBC     BK
                BCS     TONEXTITEM     ; Not less, so no more data to output.

                INC     XAML
                BNE     MOD8CHK        ; Increment 'examine index'.
                INC     XAMH
                BNE     MOD8CHK
                INC     XAMB

MOD8CHK:
                LDA     XAML           ; Check low-order 'examine index' byte
                AND     #$07           ; For MOD 8 = 0
                BPL     NXTPRNT        ; Always taken.

PRBYTE:
                PHA                    ; Save A for LSD.
                LSR
                LSR
                LSR                    ; MSD to LSD position.
                LSR
                JSR     PRHEX          ; Output hex digit.
                PLA                    ; Restore A.

PRHEX:
                AND     #$0F           ; Mask LSD for hex print.
                ORA     #$30           ; Add "0".
                CMP     #$3A           ; Digit?
                BCC     ECHO           ; Yes, output it.
                ADC     #$06           ; Add offset for letter.

ECHO:
                JSR     CHROUT         ; From BIOS
                RTS                    ; Return.
