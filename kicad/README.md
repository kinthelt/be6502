# KiCad schematic

Schematic for the W65C816S breadboard computer, as built. Open
`be6502.kicad_pro` in KiCad 7 or newer. `be6502.pdf` is a plot of all sheets.

## Sheets

| Sheet | Contents |
|-------|----------|
| `be6502.kicad_sch` | Root: sheet index, memory map |
| `cpu.kicad_sch` | U1 W65C816S, U2 74HC573 bank latch, U3 ATF22V10C (816DEC02), X1 12 MHz oscillator, reset |
| `memory.kicad_sch` | U4 AT28C256 ROM, U5 AS6C4008 RAM |
| `io.kicad_sch` | U6 74HC138, U7 W65C22N VIA with Port B LEDs, U8 W65C51N ACIA, X2 1.8432 MHz oscillator, U9 MAX232N, J2 DB9 |
| `power.kicad_sch` | J1 bench supply, C1 |

Sheets connect through global labels.

## Signal names

Active-low signals use KiCad's overbar notation in both net labels and pin
names: `~{IOSEL}`, `~{ROMCE}`, `~{RAMCE}`, `~{OEGATE}`, `~{WEGATE}`, `~{RES}`,
`~{IRQ}`, `R/~{W}`, and so on.

| Schematic | decode.pld | WDC datasheet |
|-----------|------------|---------------|
| `~{IOSEL}` | `/IOSEL` | — |
| `R/~{W}` | `RWB` | RWB |
| `~{RES}` | — | RESB |
| `~{IRQ}` | — | IRQB |
| `~{CS2}` (VIA) | — | CS2B |
| `~{CS1}` (ACIA) | — | CS1B |

KiCad stores `/` in a net name as `{slash}`, so the read/write net is
`R{slash}~{W}` in the files. It still displays as R/W with a bar over the W.

The project library `be6502.kicad_sym` contains every symbol the schematic
uses. The W65C816S, W65C22, W65C51N and the programmed ATF22V10C are drawn
from the WDC and Microchip pinouts. The other parts are copied from the stock
KiCad libraries, with pins such as `OE`, `Load` and `CE#` renamed to `~{OE}`,
`LE` and `~{CE}`.

## Wiring

**CPU (U1)**
- `~{ABORT}`, BE, RDY and `~{NMI}` are tied directly to +5V.
- VDA, VPA, `~{VP}`, `~{ML}`, E and MX are not connected.
- `~{RES}` has a pull-up (R1) and a push button (SW1) to GND.
- `~{IRQ}` has a pull-up (R2). It is shared by the VIA and the ACIA, both open drain, with no diode.

**Clock**
- X1 is a 12 MHz DIP-14 oscillator driving GAL pin 1 (CLK2). The GAL divides it to PHI2 = 6 MHz.
- X1 pin 1 is not connected.

**Bank latch and decode (U2, U3)**
- The GAL pins are exactly as in the `PIN ASSIGNMENT` section of `pld/decode.pld`.
- `~{VRAMCE}` (GAL pin 17) is not connected, because the video RAM is future expansion.
- GAL pins 11, 13, 15 and 16 are spare.
- On the 74HC573, `~{OE}` goes to GND and LE comes from GAL pin 14.
- Q0–Q2 drive A16–A18 and Q7 drives A23. Q3–Q6 are not connected.

**Memory (U4, U5)**
- The ROM and RAM share `~{OEGATE}`.
- `~{WEGATE}` goes only to the RAM's `~{WE}`. The ROM's `~{WE}` is tied high.

**I/O decoder (U6, 74HC138)**
- A/B/C = A10/A11/A12.
- `~{E0}` = `~{IOSEL}`, `~{E1}` = GND, E2 = +5V.
- Y0 goes to the VIA's `~{CS2}` and Y4 to the ACIA's `~{CS1}`. The other outputs are not connected.

**VIA (U7, W65C22N6TPG-14)**
- CS1 = +5V, RS0–RS3 = A0–A3.
- Port A, CA1, CA2, CB1 and CB2 are not connected.
- Each PBn drives an LED (D1–D8) and a resistor (R3–R10) to GND: PBn → LED → resistor → GND.

**ACIA (U8)**
- CS0 = +5V, RS0–RS1 = A0–A1.
- X2 is a 1.8432 MHz DIP-8 oscillator driving XTLI. X2 pin 1 (EN) is tied to +5V.
- XTLO, RxC and `~{DTR}` are not connected. `~{CTS}`, `~{DSR}` and `~{DCD}` are tied to GND.

**RS-232 (U9 MAX232N, J2 DB9 female)**
- ACIA TxD → T1IN → T1OUT → DB9 pin 2.
- DB9 pin 3 → R1IN → R1OUT → ACIA RxD.
- ACIA `~{RTS}` → T2IN → T2OUT → DB9 pin 8.
- DB9 pin 5 = GND. DB9 pins 1, 4, 6, 7 and 9 are not connected.
- R2IN and R2OUT are not connected.
- The charge-pump capacitors are 1 µF electrolytics: C2 across C1+/C1−, C3 across C2+/C2−, C4 from VS+ to GND, C5 from VS− to GND.

**Power**
- J1 represents the leads from the +5V bench supply.
- C1 (0.1 µF electrolytic) across +5V and GND at the supply connection is the only decoupling capacitor.

**Resistor values**
- R1–R10 are shown as 1k. This is an estimate, because the markings can't be read.

## Verification

The project was generated with KiCad 7.0 and checked with `kicad-cli sch
export netlist`. Every net matches the wiring above, and the only unconnected
pins are the ones marked no-connect. ERC has not been run, because
`kicad-cli` 7 has no ERC command. Run it in the GUI.
