AS       := ca65
LD       := ld65
LDFLAGS  := -C bios.cfg

.SUFFIXES: .s .bin

BIN=bios.bin count.bin memtest.bin memtest2.bin

all: $(BIN) bios.sym

bios.bin bios.sym: bios.o
	$(LD) $(LDFLAGS) -o bios.bin -Ln bios.sym $<

bios.o: bios.s wozmon.s
	$(AS) $(ASFLAGS) -o $@ $<

%.o: %.s
	$(AS) $(ASFLAGS) -o $@ $<

%.bin: %.o bios.o
	$(LD) $(LDFLAGS) -o $@ $< bios.o

clean:
	rm -f $(BIN) *.o bios.sym
