# be6502
Notes on my Ben Eater 6502 build

## Description

I've been having fun building a 6502 breadboard computer based on Ben Eater's design (https://www.youtube.com/playlist?list=PLowKtXNTBypFbtuVMUVXNR0z1mu7dp7eH)

I made the decision early on to mostly follow along with the videos, but tweak the design a bit so that I would be forced to sit and think rather than just follow a recipe.  One of the major decisions was to use a 65C816S CPU rather than a 65C02S.  The extra 8 bits of address space (called banks) add new problems for me to solve if I am to use them.

On boot, the '816 behaves the same as the '02 as it operates in "emulation mode".  This simplifies things for me as I can treat the build the same as an '02 in bank 00.  If I want to access other banks, I need to store the data line bits in a latch on PHI2 low.  This is the start of where my design differs.

On PHI2 low, I store the data lines in a 74HC573 latch.  This is the bank byte, which I will use later.

The bank byte allows up to 255 banks of 64k each.  A whopping 16MB of address space is available to us.  That being said, I plan on only using a single 512kB RAM chip in my final design.  To start, I will use a single 8kB RAM chip.

With the addition of multiple banks, I won't be able to use a single 7400 to decode addresses without significant shadowing.  So the plan is to use an ATF22V10C programmable logic device to decode addresses.  The PLD allows me to remove some of the "wasted" space in Ben Eater's design.

## The Ben Eater Address Space

| Range           | Size    | Device                          | Notes                                      |
|-----------------|---------|---------------------------------|--------------------------------------------|
| `$0000`–`$00FF` | 256 B   | RAM — zero page                 | 62256                                      |
| `$0100`–`$01FF` | 256 B   | RAM — stack                     | 62256                                      |
| `$0200`–`$3FFF` | 15.5 KB | RAM — general                   | 62256 (upper 16 KB of chip unusable)       |
| `$4000`–`$4FFF` | 4 KB    | unmapped                        |                                            |
| `$5000`         | 1 B     | 65C51 ACIA — data register      | read = RX, write = TX                      |
| `$5001`         | 1 B     | 65C51 ACIA — status / reset     | read = status, write = programmed reset    |
| `$5002`         | 1 B     | 65C51 ACIA — command register   |                                            |
| `$5003`         | 1 B     | 65C51 ACIA — control register   |                                            |
| `$5004`–`$5FFF` | ~4 KB   | ACIA register mirrors           | only A0–A1 decoded (RS0–RS1)               |
| `$6000`–`$600F` | 16 B    | 65C22 VIA — 16 registers        | RS0–RS3 = A0–A3                            |
| `$6010`–`$7FFF` | ~8 KB   | VIA register mirrors            | only A0–A3 decoded                         |
| `$8000`–`$FFFF` | 32 KB   | ROM                             | 28C256; vectors at `$FFFA`–`$FFFF`         |

### Address decode

| Device | Select logic |
|--------|--------------|
| ROM    | `/CE = NOT(A15)` |
| RAM    | `/CE = NOT(NOT(A15) AND Φ2)`, `/OE = A14` |
| VIA    | `/CS2 = NOT(NOT(A15) AND A14)`, `CS1 = A13` |
| ACIA   | `/CS1 = NOT(NOT(A15) AND A14 AND NOT(A13) AND A12)`, `CS0 = 1` |

**Quirks:** The 62256 is chip-enabled across `$0000`–`$7FFF`; only `/OE = A14` blocks reads above `$3FFF`. Writes to `$4000`–`$7FFF` still land in the RAM chip and cannot be read back, and writes in `$5000`–`$7FFF` hit RAM and the I/O device simultaneously.

## My Address Space

24-bit address space, notated `bank:offset`.

### Top level

| Range                 | Size   | Contents                                  |
|-----------------------|--------|-------------------------------------------|
| `$00:0000`–`$00:FFFF` | 64 KB  | Bank 0 — RAM, I/O, ROM (see below)        |
| `$01:0000`–`$07:FFFF` | 448 KB | RAM, full banks                           |
| `$08:0000`–`$7F:FFFF` | —      | Aliases of banks `$00`–`$07`              |
| `$80:0000`–`$80:7FFF` | 32 KB  | Video RAM (62256)                         |
| `$80:8000`–`$FF:FFFF` | —      | Aliases of `$80:0000`–`$80:7FFF`          |

RAM total: 472 KB reachable of 512 KB installed (AS6C4008). The 40 KB shortfall is
bank 0's I/O window and ROM window shadowing the SRAM.

### Bank 0

| Range                 | Size    | Contents                                 |
|-----------------------|---------|------------------------------------------|
| `$00:0000`–`$00:00FF` | 256 B   | RAM — direct page (reset default)        |
| `$00:0100`–`$00:01FF` | 256 B   | RAM — stack (reset default)              |
| `$00:0200`–`$00:5FFF` | 23.5 KB | RAM — general                            |
| `$00:6000`–`$00:7FFF` | 8 KB    | I/O window — 74HC138, 8 × 1 KB slots     |
| `$00:8000`–`$00:FFFF` | 32 KB   | ROM (AT28C256)                           |

Direct page and stack are shown at their reset defaults. In native mode both are
relocatable anywhere within bank 0.

### I/O window

74HC138 enabled by `/IO_SELECT` from the GAL, selects driven by A10–A12.

| Output | Range                 | Device       | Registers                          |
|--------|-----------------------|--------------|------------------------------------|
| Y0     | `$00:6000`–`$00:63FF` | W65C22 VIA   | `$6000`–`$600F`, mirrored (A0–A3)  |
| Y1     | `$00:6400`–`$00:67FF` | unallocated  |                                    |
| Y2     | `$00:6800`–`$00:6BFF` | unallocated  |                                    |
| Y3     | `$00:6C00`–`$00:6FFF` | unallocated  |                                    |
| Y4     | `$00:7000`–`$00:73FF` | W65C51N ACIA | `$7000`–`$7003`, mirrored (A0–A1)  |
| Y5     | `$00:7400`–`$00:77FF` | unallocated  |                                    |
| Y6     | `$00:7800`–`$00:7BFF` | unallocated  |                                    |
| Y7     | `$00:7C00`–`$00:7FFF` | unallocated  |                                    |

### Vectors

| Range                 | Mode      |
|-----------------------|-----------|
| `$00:FFE4`–`$00:FFEF` | Native    |
| `$00:FFF8`–`$00:FFFF` | Emulation |

Both sets are in ROM. ROM is fixed at `$00:8000` — no vector remap or bank switching.

### Decode

Bank byte A16–A23 is captured from D0–D7 by a 74HC573, LE driven by `/PHI2`.

GAL (ATF22V10C) inputs: A12–A15, A16–A18, A23, PHI2, RWB.
A19–A22 are deliberately left as don't-cares — hence the aliasing above. Tighten
this first if a second RAM or VRAM device is ever added.

A16–A18 feed the SRAM address pins directly; the GAL uses them only to identify
bank 0. A23 alone separates the RAM banks from the video bank.

`/WE_RAM` is gated `PHI2 AND /RWB`. Raw RWB would write during PHI2 low, when the
data bus still carries the bank byte.

# Pinout Reference — 75HC138 and W65C22

For the 65C816 breadboard build. I/O window `$00:6000–$00:7FFF`,
enabled by IOSEL from the ATF22V10C (816DEC01).

---

## 74HC138 — 3-to-8 Line Decoder, DIP-16

| Pin | Name | Connect to |
|----:|------|------------|
| 1 | A | A10 |
| 2 | B | A11 |
| 3 | C | A12 |
| 4 | /E1 (/G2A) | IOSEL, GAL pin 20 |
| 5 | /E2 (/G2B) | GND — reserved PHI2 hook |
| 6 | E3 (G1) | VCC |
| 7 | Y7 | $7C00 slot |
| 8 | GND | GND |
| 9 | Y6 | $7800 slot |
| 10 | Y5 | $7400 slot |
| 11 | Y4 | $7000 — ACIA |
| 12 | Y3 | $6C00 slot |
| 13 | Y2 | $6800 slot |
| 14 | Y1 | $6400 slot |
| 15 | Y0 | $6000 — VIA CS2B |
| 16 | VCC | +5V |

100 nF from pin 16 to pin 8, close to the package.

### Output behaviour

All eight outputs idle **high**. Exactly one goes low at a time, and
only when every enable is satisfied. Nothing is selected at rest.

| Condition | Outputs |
|-----------|---------|
| Any enable unsatisfied | all eight high |
| Enabled, CBA = 000 | Y0 low, rest high |
| Enabled, CBA = 100 | Y4 low, rest high |

### Enables

Mixed polarity. All three must be true at once:

- pin 4 — LOW
- pin 5 — LOW
- pin 6 — HIGH

Naming varies by manufacturer. TI uses /G2A, /G2B, G1; others use
/E1, /E2, E3. Same pins, same behaviour, different letters. A
schematic found online may not match the datasheet in hand.

Pin 6 is the trap — the only active-high enable, sitting next to the
two active-low ones. Tied low, the part has no outputs at all and no
obvious reason why.

### Slot mapping

C:B:A = A12:A11:A10, straight through.

| Output | Address range | Device |
|--------|---------------|--------|
| Y0 | $00:6000–$00:63FF | W65C22 VIA |
| Y1 | $00:6400–$00:67FF | unallocated |
| Y2 | $00:6800–$00:6BFF | unallocated |
| Y3 | $00:6C00–$00:6FFF | unallocated |
| Y4 | $00:7000–$00:73FF | W65C51N ACIA |
| Y5 | $00:7400–$00:77FF | unallocated |
| Y6 | $00:7800–$00:7BFF | unallocated |
| Y7 | $00:7C00–$00:7FFF | unallocated |

Unused outputs are totem-pole, not open-drain — nothing to pull.
Leave open, or run to a header row while breadboarding.

---

## W65C22 VIA — DIP-40

| Pin | Signal | Connect to |
|----:|--------|------------|
| 1 | VSS | GND |
| 2–9 | PA0–PA7 | peripheral, ascending |
| 10–17 | PB0–PB7 | peripheral, ascending |
| 18 | CB1 | peripheral / shift clock |
| 19 | CB2 | peripheral / serial data |
| 20 | VDD | +5V |
| 21 | IRQB | CPU IRQB — see note |
| 22 | RWB | CPU RWB |
| 23 | CS2B | 74HC138 Y0, pin 15 |
| 24 | CS1 | VCC |
| 25 | PHI2 | system PHI2 |
| 26–33 | D7–D0 | data bus, **descending** |
| 34 | RESB | system reset |
| 35–38 | RS3–RS0 | A3–A0, **descending** |
| 39 | CA2 | peripheral |
| 40 | CA1 | peripheral |

### Chip select

To access a register: CS1 = logic 1 AND CS2B = logic 0.

CS1 is the tie-high enable, not the main select. WDC's default for
unused pins says the same thing from the other side — hold CS1 high,
hold CS2B low.

Y0 is active low, so it must land on CS2B. Y0 on CS1 selects the chip
whenever the slot is *not* addressed, and the VIA fights RAM and ROM
on the data bus every cycle.

### Descending pin runs

Pin 26 = D7, pin 33 = D0.
Pin 35 = RS3, pin 38 = RS0.

Both numbered opposite to the PA and PB runs on the same package.
Reversing the data bus produces bit-mirrored reads and writes that
look like a dead chip.

### IRQB — check the part marking

| Variant | IRQB output | Wiring |
|---------|-------------|--------|
| W65C22N, older NMOS/CMOS | open drain, pull down only | wire-OR, one pullup on the common line |
| W65C22S | totem pole, drives both levels | logic OR gate, or a <0.5 V diode in series, forward biased when IRQB is low, plus a pullup |

The W65C22S IRQB was meant for logically ORing rather than wire ORing.
Tying an S variant directly to another driven IRQ line is a driver
fight.

With the ACIA on the same node, this decides the interrupt topology
for the whole system. Settle it before wiring either chip.

### Processor interface timing — 5 V, 14 MHz

| Symbol | Parameter | Min |
|--------|-----------|-----|
| tACR / tACW | CSx, RSx, RWB setup | 10 ns |
| tCAR / tCAW | CSx, RSx, RWB hold from PHI2 rising | 10 ns |
| tDCW | data bus setup (write) | 10 ns |
| tCDR | data bus delay (read) | 20 ns max |

The 10 ns setup is what the decode chain must beat:

    74HC573 → ATF22V10C → 74HC138 → CS2B

all settled 10 ns before PHI2 rises.

### W65C22S-specific

- **No output current limiting.** The S variant can overdrive
  connected circuitry. The NMOS 6522 and W65C22N have series
  resistors built in. Add external resistors on PA/PB when driving
  LEDs or an HD44780.
- **Bus holding on every pin except PHI2.** A floating input holds
  its last state rather than drifting — so a disconnected jumper can
  look like a working connection until something changes it.

---

## Signal chain

Active low end to end:

    IOSEL low  →  '138 enabled  →  one Y low  →  CS2B low  →  VIA selected

No inverters anywhere in the path.

---

## Sources

- WDC W65C22 datasheet (W65C22N and W65C22S), Sept 13 2010
- Standard 6522 DIP-40 pin numbering, which the W65C22 follows
