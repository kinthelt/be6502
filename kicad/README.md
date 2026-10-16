# KiCad schematic

Schematic for the W65C816S computer, rev 2: the design for a printed circuit
board. Open `be6502.kicad_pro` in KiCad 7 or newer. `be6502.pdf` is a plot of
all sheets.

Rev 1 documented the breadboard as wired. It is at commit `2bfb76a` (`git show
2bfb76a:kicad/cpu.kicad_sch`, and so on). Rev 2 keeps the same parts and logic
and adds what a board needs: decoupling, a proper power input, sockets,
expansion headers, debugging aids, and VDA/VPA qualification of the I/O select.

No PCB layout exists yet. The planned board is 4 layers
(signal / GND / +5V / signal).

## Sheets

| Sheet | Contents |
|-------|----------|
| `be6502.kicad_sch` | Root: sheet index, memory map |
| `cpu.kicad_sch` | U1 W65C816S and pull-ups R11–R14, U2 74HC573 bank latch, U3 ATF22V10C (816DEC03), X1 12 MHz oscillator, reset |
| `memory.kicad_sch` | U4 AT28C256 ROM, U5 AS6C4008 RAM |
| `io.kicad_sch` | U6 74HC138, U7 W65C22N VIA with Port B LEDs, U8 W65C51N ACIA, X2 1.8432 MHz oscillator, U9 MAX232N, J2 DB9 |
| `power.kicad_sch` | J6 USB-C and J1 bench input, JP4 source select, SW2 power switch, F1 polyfuse, Q1 reverse-polarity FET, C1 bulk, D9 power LED, C6–C17 decoupling |
| `expansion.kicad_sch` | J3 expansion bus, J4 VIA header, JP1 clock source, J5 external clock, U10 PHI2 buffer and JP2, JP3 LED enable, test points, mounting holes |

Sheets connect through global labels.

## Changes from the breadboard (rev 1)

| Area | Breadboard | Rev 2 |
|------|------------|-------|
| RDY, `~{NMI}`, `~{ABORT}`, BE | Tied straight to +5V | 3.3k pull-ups R11–R14, and on J3. RDY is bidirectional: `WAI` drives it low |
| VDA, VPA | Not connected | To GAL pins 11 and 13 (816DEC03 `/IOSEL` qualifier) and to J3 |
| GAL | 816DEC02 | 816DEC03 (`pld/decode03.pld`) |
| Bank latch Q3–Q6 | Not connected | A19–A22, to J3 only |
| PHI2 | GAL pin 23 straight to the CPU | GAL pin 23 is `PHI2_GAL`. JP2 selects it directly or through U10A, a 74ACT08 buffer |
| CLK2 | X1 straight to the GAL | X1 is `CLK_OSC`. JP1 selects it or J5, an external clock |
| '138 Y1–Y3, Y5–Y7 | Not connected | `~{IO1}`–`~{IO7}`, to J3 |
| VIA Port A, CA1/CA2, CB1/CB2 | Not connected | To J4 (with Port B) |
| Port B LED returns | GND | `LED_GND`, which reaches GND through JP3 |
| Power | Bench leads, one 0.1 µF electrolytic | See the power sheet below |
| Decoupling | None per chip | 100 nF per package, C6–C17 |
| IC footprints | DIP | DIP `_Socket` footprints (socket every IC) |

## Jumpers

On the board, every jumper is a pin header and shunt. The schematic draws
them open, so set them on the board itself.

| Jumper | Normal setting | Other setting |
|--------|----------------|---------------|
| JP1 CLK SRC | 1-2: X1 oscillator | 2-3: external clock on J5. Two pulses per bus cycle, because the GAL divides by two |
| JP2 PHI2 SRC | 1-2: PHI2 direct from the GAL, as on the breadboard | 2-3: through the 74ACT08 buffer. See `decode03.pld` NOTE 8 |
| JP3 LED EN | Fitted: Port B LEDs work | Removed: LEDs disconnected, Port B free for J4 |
| JP4 SOURCE | 1-2: USB-C (J6) | 2-3: bench supply (J1) |

The board doesn't run with JP1 or JP2 open.

## Power

- J6 is a power-only USB-C receptacle. 5.1k on CC1 and CC2 (R15, R16)
  asks the source for default USB 5 V.
- J1 is a 2-way screw terminal for the bench supply.
- JP4 picks one source.
- After that, the chain is SW2 → F1 (Bourns MF-RHT050, 0.5 A hold) →
  Q1 → +5V.
- Q1 is an AO3401A P-channel MOSFET for reverse-polarity protection.
  Drain goes to the input, source to +5V, and the gate to GND through R17.
  It conducts with negligible drop the right way round and blocks a
  reversed bench supply.
- C1 is 47 µF of bulk capacitance.
- D9 is the power LED, with R18 (1k) in series.

Q1 is the only surface-mount part on the board (SOT-23), and J6's
contacts are surface-mount too. Everything else is through-hole.

## Expansion bus (J3, 2x30 IDC)

| Pins | Signals |
|------|---------|
| 1–2 | +5V |
| 3–4, 21–22, 39–40, 59–60 | GND |
| 5–20 | A0–A15 |
| 23–30 | A16–A23 (latched bank byte, valid while PHI2 is high) |
| 31–38 | D0–D7 |
| 41–44 | PHI2, R/`~{W}`, VDA, VPA |
| 45–50 | `~{RES}`, `~{IRQ}`, `~{NMI}`, RDY, `~{ABORT}`, BE |
| 51–56 | `~{IO1}`, `~{IO2}`, `~{IO3}`, `~{IO5}`, `~{IO6}`, `~{IO7}` (1 KB I/O slots) |
| 57–58 | `~{OEGATE}`, `~{WEGATE}` |

A19–A22 are not decoded. An expansion device in banks `$08`–`$7F` would
collide with the RAM aliases. Use the `~{IOn}` slots for expansion I/O. Drive
`~{IRQ}`, `~{NMI}`, RDY, `~{ABORT}` and BE open drain only, since they have
pull-ups on the board.

## VIA header (J4, 2x12)

| Pins | Signals |
|------|---------|
| 1–8 | PA0–PA7 |
| 9–10 | CA1, CA2 |
| 11–18 | PB0–PB7 |
| 19–20 | CB1, CB2 |
| 21, 23 | +5V |
| 22, 24 | GND |

## Debugging aids

- TP1–TP7 are test points for +5V, GND (two loops for scope grounds),
  PHI2, CLK2, `~{RES}` and `~{IRQ}`.
- J3 carries the whole bus, for a logic analyzer or an Arduino bus monitor.
- J5 takes an external or single-step clock. R19 pulls `CLK_EXT` low when
  nothing is plugged in.

## Footprints and sockets

Every part has a footprint from the stock KiCad libraries.

| Part | Footprint |
|------|-----------|
| ICs | `Package_DIP:DIP-nn_Wxx_Socket` |
| X1, X2 | `Oscillator:Oscillator_DIP-14` and `Oscillator_DIP-8` |
| Resistors | Axial, 7.62 mm pitch |
| LEDs | 3 mm |
| C2–C5 | 5 mm radial electrolytic |
| C1 | 6.3 mm radial electrolytic |
| C6–C17 | 2.5 mm pitch ceramic |
| J2 | `DSUB-9_Socket_Horizontal…` (female) |
| J3 | `Connector_IDC:IDC-Header_2x30` |

U4 (ROM) is meant for a 28-pin ZIF socket on the DIP-28 footprint. Leave room
around it for the lever when placing parts.

## Signal names

Active-low signals use KiCad's overbar notation in both net labels and pin
names: `~{IOSEL}`, `~{ROMCE}`, `~{RAMCE}`, `~{OEGATE}`, `~{WEGATE}`, `~{RES}`,
`~{IRQ}`, `R/~{W}`, and so on.

| Schematic | decode03.pld | WDC datasheet |
|-----------|--------------|---------------|
| `~{IOSEL}` | `/IOSEL` | — |
| `R/~{W}` | `RWB` | RWB |
| `PHI2_GAL` | `PHI2` (pin 23) | — |
| `~{RES}` | — | RESB |
| `~{IRQ}` | — | IRQB |
| `~{CS2}` (VIA) | — | CS2B |
| `~{CS1}` (ACIA) | — | CS1B |

KiCad stores `/` in a net name as `{slash}`, so the read/write net is
`R{slash}~{W}` in the files. It still displays as R/W with a bar over the W.

The project library `be6502.kicad_sym` contains every symbol the schematic
uses. The W65C816S, W65C22, W65C51N and the programmed ATF22V10C are drawn
from the WDC and Microchip pinouts. The other parts are copied from the stock
KiCad libraries. Pins such as `OE`, `Load` and `CE#` are renamed to `~{OE}`,
`LE` and `~{CE}`. The 74ACT08 uses the stock 74LS08 symbol, which has the
same pinout.

## Unchanged wiring

The following is the same as on the breadboard.

- **CPU:** VP, ML, E and MX are not connected. `~{RES}` has pull-up R1
  (1k) and push button SW1. `~{IRQ}` has pull-up R2 (1k) and is shared, open
  drain, by the VIA, the ACIA and J3.
- **Memory:** the ROM and RAM share `~{OEGATE}`. `~{WEGATE}` goes only to
  the RAM. The ROM's `~{WE}` is tied high.
- **I/O decoder (U6):** A/B/C = A10/A11/A12, `~{E0}` = `~{IOSEL}`,
  `~{E1}` = GND, E2 = +5V. Y0 is the VIA and Y4 the ACIA.
- **ACIA (U8):**
  - CS0 = +5V, RS0–RS1 = A0–A1.
  - X2 drives XTLI.
  - `~{CTS}`, `~{DSR}` and `~{DCD}` are tied to GND.
  - XTLO, RxC and `~{DTR}` are not connected.
- **RS-232:**
  - ACIA TxD → T1 → DB9 pin 2.
  - DB9 pin 3 → R1 → ACIA RxD.
  - ACIA `~{RTS}` → T2 → DB9 pin 8.
  - DB9 pin 5 = GND.
  - C2–C5 are 1 µF electrolytics.

## Verification

Checked with KiCad 9.0.4's `kicad-cli`:

- `sch erc` reports 0 errors and 0 warnings.
- `sch export netlist` was used to confirm every new connection, and that
  every IC's VCC and GND pins reach +5V and GND.

The files are written in the KiCad 7 file format (`version 20230121`), so
KiCad 7 and newer should open them. Only KiCad 9.0.4 has been tested.
