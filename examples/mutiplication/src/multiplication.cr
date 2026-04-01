require "cr6502"
require "cry-bus"

module Multiplication
  class Memory < Crybus::Circuit
    @bytes : Array(UInt8)

    def write_byte(address : UInt32, data : UInt8)
      @bytes[address - @connector.segments[0].start_adr] = data
    end

    def read_byte(address : UInt32) : UInt8
      return @bytes[address - @connector.segments[0].start_adr]
    end

    def initialize(size : UInt32, address : UInt32, bus : Crybus::Bus, random : Bool = false)
      bus.connect(@connector)
      @bytes = random ? Array(UInt8).new(size, Random.rand(UInt8)) : Array(UInt8).new(size, 0)
      @connector.segments << Crybus::Connector::Segment.new(address, address + size, ->read_byte(UInt32), ->write_byte(UInt32, UInt8))
    end
  end

  class MyCPU < CPU
    def poke(mem_location : UInt32 | Int32 | UInt16 | UInt8, data : UInt8 | UInt16)
      if data.is_a?(UInt16)
        Multiplication.bus.write(mem_location.to_u32, (data & 0xff).to_u8)
        Multiplication.bus.write(mem_location.to_u32 + 1, (data >> 8 & 0xff).to_u8)
      else
        Multiplication.bus.write(mem_location.to_u32, data.to_u8)
      end
    end

    def peek(mem_location : UInt32 | Int32 | UInt16 | UInt8, two_byte : Bool = false) : UInt8 | UInt16
      return Multiplication.bus.read(mem_location.to_u32).to_u16 + (Multiplication.bus.read(mem_location.to_u32 + 1).to_u16 << 8) if two_byte
      return Multiplication.bus.read(mem_location.to_u32)
    end
  end

  class_getter bus = Crybus::Bus.new
  Memory.new(65536, 0, Multiplication.bus)

  cpu = MyCPU.new(1.0, 0x0600_u16, CPU::RES_LOCATION - 2)

  tmp = 0x00_u8
  result = 0x01_u8

  mpd = 0x03_u8
  mpr = 0x04_u8

  cpu.poke(mpd.to_u32, 2_u8)
  cpu.poke(mpr.to_u32, 3_u8)

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
end
