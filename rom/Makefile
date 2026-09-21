ASM=vasm6502_oldstyle

BIN=count.bin memtest.bin

all: $(BIN)

count.bin: count.s
	$(ASM) -Fbin -dotdir $< -o count.bin

memtest.bin: memtest.s
	$(ASM) -816 -Fbin -dotdir $< -o memtest.bin

clean:
	rm -f $(BIN)
