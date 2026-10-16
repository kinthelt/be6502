# KiCad schematic

Schematic for the W65C816S breadboard computer, drawn from `../README.md` and
`../pld/decode.pld` (816DEC02). Open `be6502.kicad_pro` in KiCad 7 or newer.
`be6502.pdf` is a plot of all sheets.

## Sheets

| Sheet | Contents |
|-------|----------|
| `be6502.kicad_sch` | Root: sheet index, memory map |
| `cpu.kicad_sch` | U1 W65C816S, U2 74HC573 bank latch, U3 ATF22V10C (816DEC02), X1 clock, reset, pull-ups |
| `memory.kicad_sch` | U4 AT28C256 ROM, U5 AS6C4008 RAM, U6 62256 video RAM |
| `io.kicad_sch` | U7 74HC138 slot decoder, U8 W65C22 VIA, U9 W65C51N ACIA, port and serial headers |
| `power.kicad_sch` | +5 V input, power flags, bulk capacitor |

Sheets connect through global labels.

## Signal names

Active-low signals use KiCad's overbar notation in both net labels and pin
names: `~{IOSEL}`, `~{ROMCE}`, `~{RAMCE}`, `~{VRAMCE}`, `~{OEGATE}`,
`~{WEGATE}`, `~{RES}`, `~{IRQ}`, `R/~{W}`, and so on. Here is how they map to
the names used elsewhere:

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
KiCad libraries, and pins like `OE`, `Load`, `CE#` are renamed to `~{OE}`,
`LE`, `~{CE}`.

## Taken from README.md / decode.pld

- GAL pin assignment exactly as in the `PIN ASSIGNMENT` section of decode.pld.
- 74HC573 `~{OE}` tied to GND, LE from GAL pin 14. Q0–Q2 drive A16–A18, Q7 drives A23,
  and Q3–Q6 (A19–A22) are left unconnected.
- `~{OEGATE}` and `~{WEGATE}` are shared by the ROM, RAM and video RAM. The ROM's `~{WE}` is tied high.
- 74HC138: A/B/C = A10/A11/A12, `~{E0}` (pin 4) = `~{IOSEL}`, `~{E1}` (pin 5) = GND
  (reserved PHI2 hook), E2 (pin 6) = VCC. Y0 goes to the VIA `~{CS2}`, Y4 to the ACIA `~{CS1}`,
  and the other outputs are left open.
- VIA: CS1 = VCC, RS0–RS3 = A0–A3. ACIA: CS0 = VCC, RS0–RS1 = A0–A1.
- The VIA IRQ goes through a Schottky diode into the shared `~{IRQ}` line, which has a pull-up
  (README: works with both the W65C22S and the W65C22N).

## Assumptions (not specified in README.md or decode.pld)

Check these against the breadboard:

- X1 is a 12 MHz DIP-14 oscillator can, so PHI2 = 6 MHz (`PHI2_HZ` in `rom/bios.s`).
- Reset is a 10k pull-up plus a push button. RDY, `~{IRQ}` and `~{NMI}` have 3.3k pull-ups.
  `~{ABORT}` and BE are tied to VCC. VDA, VPA, `~{VP}`, `~{ML}`, E and MX are not connected.
- ACIA: a 1.8432 MHz crystal sits directly across XTLI/XTLO. `~{CTS}`, `~{DSR}` and `~{DCD}`
  are tied low, and `~{DTR}` and RxC are not connected.
- J4 is an FTDI-style 6-pin TTL serial header (1 GND, 2 CTS#, 3 VCC n/c, 4 TXD, 5 RXD,
  6 RTS# n/c). ACIA `~{RTS}` goes to the adapter's CTS# for the flow control in `bios.s`.
- The VIA ports go to two 1x10 headers (J2: PA0–7, CA1, CA2; J3: PB0–7, CB1, CB2).
- There is one 100 nF decoupling capacitor per package, plus a 10 µF bulk capacitor at J1.
- Footprints are DIP and through-hole parts, set for reference only.

## Verification

The project was generated with KiCad 7.0 and checked with `kicad-cli sch
export netlist`. Every net matches the connections listed above, and the only
unconnected pins are the ones marked no-connect. ERC has not been run, because
`kicad-cli` 7 has no ERC command. Run it in the GUI.
