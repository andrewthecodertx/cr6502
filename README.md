# cr6502

This is a simple 6502 emulator written in Crystal Lang.<br>
It's not the most modular emulator but you can easily bridge it to any other emulated chip.<br>
**cr6502** includes a simple asm interpreter to load instructions.<br>

## Installation

1. Add `cr6502` to your `shard.yml`:
```yml
dependencies:
  cr6502:
    github: D-Shwagginz/cr6502
```

2. Run `shards install`

## Usage

For a guide check out the [docs](https://d-shwagginz.github.io/cr6502/CPU.html)

Here is the example of a small multiplication program:

```crystal
require "cr6502"

cpu = CPU.new(1.0, 0x0600_u16, CPU::RES_LOCATION - 2)

tmp = 0x00_u8
result = 0x01_u8

mpd = 0x03_u8
mpr = 0x04_u8

cpu.poke(mpd, 2_u8)
cpu.poke(mpr, 3_u8)

cpu.load_asm("
START:
    LDA     #0       ; zero accumulator
    STA     #{tmp}      ; clear address
    STA     #{result}   ; clear
    STA     #{result + 1} ; clear
    LDX     #8       ; x is a counter
MULT:
    LSR     #{mpr}      ; shift mpr right - pushing a bit into C
    BCC     NOADD    ; test carry bit
    LDA     #{result}   ; load A with low part of result
    CLC
    ADC     #{mpd}      ; add mpd to res
    STA     #{result}   ; save result
    LDA     #{result + 1} ; add rest off shifted mpd
    ADC     #{tmp}
    STA     #{result + 1}
NOADD:
    ASL     #{mpd}      ; shift mpd left, ready for next 'loop'
    ROL     #{tmp}      ; save bit from mpd into temp
    DEX              ; decrement counter
    BNE     MULT     ; go again if counter 0
")

cpu.execute

puts cpu.peek(result, true)
```

## License

MIT, see [LICENSE](LICENSE).

## Contributing

PRs welcome. Please open an issue first for major changes.
