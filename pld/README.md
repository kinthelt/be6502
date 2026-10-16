I will be using the galette .pld to .jed converter.  From what I understand, the input format is mostly compatible with GALasm (see https://github.com/daveho/GALasm for documentation).

Feel free to use the ATF22V10C which is still being made instead of the GAL22V10.

## Files

| File | Name | Used on |
|------|------|---------|
| `decode.pld` | 816DEC02 | The breadboard, as wired today |
| `decode03.pld` | 816DEC03 | The PCB. Adds VDA (pin 11) and VPA (pin 13) and qualifies `/IOSEL` with them |
| `beneater.pld` | | Ben Eater's original 7400 decode, for reference |

Both 816DEC02 and 816DEC03 assemble without errors in Galette 0.3.0. Don't burn
816DEC03 into the breadboard's GAL unless VDA and VPA are wired to pins 11
and 13. Left floating, they make `/IOSEL` unpredictable.
