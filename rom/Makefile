ASM=vasm6502_oldstyle

BIN=count.bin memtest.bin memtest2.bin

all: $(BIN)

count.bin: count.s
	$(ASM) -Fbin -dotdir $< -o count.bin

memtest.bin: memtest.s
	$(ASM) -816 -Fbin -dotdir $< -o memtest.bin

memtest2.bin: memtest2.s
	$(ASM) -816 -Fbin -dotdir $< -o memtest2.bin

clean:
	rm -f $(BIN)
