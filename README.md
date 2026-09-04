# be6502
Notes on my Ben Eater 6502 build

Description

I've been having fun building a 6502 breadboard computer based on Ben Eater's design (https://www.youtube.com/playlist?list=PLowKtXNTBypFbtuVMUVXNR0z1mu7dp7eH)

I made the decision early on to mostly follow along with the videos, but tweak the design a bit so that I would be forced to sit and think rather than just follow a recipe.  One of the major decisions was to use a 65C816S CPU rather than a 65C02S.  The extra 8 bits of address space (called banks) add new problems for me to solve if I am to use them.

On boot, the '816 behaves the same as the '02 as it operates in "emulation mode".  This simplifies things for me as I can treat the build the same as an '02 in bank 00.  If I want to access other banks, I need to store the data line bits in a latch on PHI2 low.  This is the start of where my design differs.

On PHI2 low, I store the data lines in a 74HC573 latch.  This is the bank byte, which I will use later.

The bank byte allows up to 255 banks of 64k each.  A whopping 16MB of address space is available to us.  That being said, I plan on only using a single 512kB RAM chip in my final design.  To start, I will use a single 8kB RAM chip.

With the addition of multiple banks, I won't be able to use a single 7400 to decode addresses without significant shadowing.  So the plan is to use an ATF22V10C programmable logic device to decode addresses.  The PLD allows me to remove some of the "wasted" space in Ben Eater's design.
