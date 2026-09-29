AS      := ca65
LD      := ld65
LDFLAGS := -C mem.cfg

.SUFFIXES: .s .bin

BIN=count.bin memtest.bin

all: $(BIN)

%.o: %.s
	$(AS) $(ASFLAGS) -o $@ $<

%.bin: %.o
	$(LD) $(LDFLAGS) -o $@ $<

clean:
	rm -f $(BIN) *.o
