AS       := ca65
LD       := ld65
LDFLAGS  := -C bios.cfg

.SUFFIXES: .s .bin

BIN=bios.sym count.bin memtest.bin memtest2.bin

all: $(BIN)

bios.sym: bios.o
	$(LD) $(LDFLAGS) -Ln $@ $<

bios.o: bios.s wozmon.s
	$(AS) $(ASFLAGS) -o $@ $<

%.o: %.s
	$(AS) $(ASFLAGS) -o $@ $<

%.bin: %.o bios.o
	$(LD) $(LDFLAGS) -o $@ $< bios.o

clean:
	rm -f $(BIN) *.o
