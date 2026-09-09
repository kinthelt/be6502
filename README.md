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
