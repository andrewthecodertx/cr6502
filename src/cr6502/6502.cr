# ## The 6502 CPU
#
# NOTE: THESE EXAMPLES ASSUME A MEMORY BUS AND ARE NO LONGER VALID.
# PLEASE VIEW THE MULTIPLICATION EXAMPLE TO SHOW HOW TO CREATE A SYSTEM BUS
#
# ### Assembly:
# The main powerhouse of the emulator is the `CPU#load_asm()` method.
#
# The method allows you to type in 6502 asm code and run it through Crystal.<br>
# The assembler has the ability to use labels as well as a few custom instructions<br>
# It also uses a semicolon ';' for inline comments
#
# Example:
# ```
# ; Look at this cool comment!
# cpu = CPU.new(1.0, 0x0600_u16, CPU::RES_LOCATION - 2)
# cpu.load_asm("
# lda #$14
# ")
# cpu.execute
# puts cpu.accumulator
# ```
#
# To see all of the custom instructions, please see [custom_instructions.cr](https://github.com/D-Shwagginz/cr6502/blob/master/src/cr6502/instructions/custom_instructions.cr)
#
# Example:
# ```
# cpu.load_asm("
# prt 22
# ")
# cpu.execute # => puts "Type: UInt8 | Hex: 0x16 | Decimal: 22 | Binary: 0b00010110"
# ```
#
# The assembler also has some predefined labels:<br>
# `resvec:` will set the value at `RES_LOCATION` to the label's address location.<br>
# `brkvec:` will set the value at `BRK_LOCATION` to the label's address location.<br>
#
# Example:
# ```
# cpu = CPU.new(1.0, 0x0200_u16)
# cpu.load_asm("
# resvec:
# nop
# brkvec:
# ")
# puts cpu.peek(CPU::BRK_LOCATION, true).to_s(16) # => 200
# puts cpu.peek(CPU::RES_LOCATION, true).to_s(16) # => 201
# ```
#
# Being written in Crystal, you can use string interpolation when writing assembly code, giving access for any UInt8 and UInt16
# to be injected into the code.
#
# # Example:
# ```
# x = 0xa4
# cpu.load_asm("
# lda ##{x}
# ")
# cpu.execute
# puts cpu.accumulator.to_s(16) # => a4
# ```
#
# Note that the values are assigned at the assembler's compile time, therefore
#
# ```
# x = 0xa4_u8
# cpu.load_asm("
# lda ##{x}
# prt #{cpu.accumulator}
# ")
# cpu.execute                   # => puts "Type: UInt8 | Hex: 0x00 | Decimal: 0 | Binary: 0b00000000"
# puts cpu.accumulator.to_s(16) # => a4
# ```
#
# In the above example, at compile time, `cpu.accumulator` is set to 0. It only gets changed at the runtime of the code.<br>
# You can however achieve the hoped for effect by using multiple `CPU#load_asm` methods:
#
# ```
# x = 0xa4_u8
# cpu.load_asm("
# lda ##{x}
# ")
#
# cpu.execute
#
# cpu.load_asm("
# prt #{cpu.accumulator}
# ")
#
# cpu.execute # => puts "Type: UInt8 | Hex: 0xa4 | Decimal: 164 | Binary: 0b10100100"
# ```
#
# Be careful when doing this though as you must keep in mind that the memory has not reset, but using `CPU#load_asm` will reset the `CPU#program_counter`
# to its original value, or to the value of a `resvec:`
#
# This means that all the instructions set by any previous `CPU#load_asm`'s will still be there in memory.
#
# To counteract this issue, ensure that a brk is set at the end of any code
#
# You can however "append" code by setting the `start_location` of `CPU#load_asm` manually
#
# Example
# ```
# cpu = CPU.new(1.0, 0x0600_u16, CPU::RES_LOCATION - 2)
#
# cpu.load_asm("
# lda #01
# ")
#
# # Code = a9 01 #
#
# cpu.load_asm(0x0603"
# lda #01
# ")
#
# # Code = a9 01 a9 01 #
# ```
#
# You can also use `resvec:` to edit the default `CPU#program_counter` location when editing code
#
# Example
# ```
# cpu.load_asm("
# lda #01
# resvec:
# ")
#
# # Code = a9 01 #
#
# cpu.load_asm("
# lda #01
# ")
#
# # Code = a9 01 a9 01 #
# ```
#
class CPU
  # Vector address for RESET
  RES_LOCATION = 0xfffc_u16
  # Vector address for BRK
  BRK_LOCATION = 0xfffe_u16

  # The flags of the cpu
  enum Flags
    # ### The Sign Flag
    # Sign Flag serves TWO purposes
    # 1) 	To signify the sigN of the last mathematical or bitwise operation.
    # 	The sign is the bit-7 of the result value.
    # 	If the last operation was not a signed operation, P.N will still reflect bit-7 of the result, but will NOT be considered as a sign.
    # 2) 	As a result store for a `CPU#bit` instruction:
    # 	The `CPU#bit` instruction reads the contents of the specified memory address and copies bit-7 of that value to the Sign Flag
    Negative
    # ### The Overflow Flag
    # P.V serves TWO purposes
    # 1) 	To signify an oVerflow (a sign change) during a mathmatical operation. Caused by an `CPU#adc` or `CPU#sbc` instruction:
    # 	If an `CPU#adc` or `CPU#sbc` instruction generates a result that would require more than 8 bits to hold (that is, any number outside the range -128 to 127) then Overflow is SET; else Overflow is CLEARed.
    # 	This flag may be ignored if the programmer is NOT using signed arithmetic.
    # 2) 	As a result store for a `CPU#bit` instruction:
    # 	The `CPU#bit` instruction reads the contents of the specified memory address and copies bit-6 of that value to P.V
    Overflow
    # ### The Break Flag
    # The Break Flag and the `CPU#brk` instruction seem to me to be one very badly thought out bodge.
    # If you do not plan to use the `CPU#brk` instruction I would just ignore it!
    # P.B is never actually set in the Flags register!
    # When a `CPU#brk` instruction occurs the Flags are PUSHed onto the Stack along with a return address*
    # It is only this copy of the Flags (the one on the Stack) that has P.B set!
    #
    # * This return address is actually "Address_of_BRK_instruction+2".
    # 	Bearing in mind that the `CPU#brk` instruction is only ONE byte long...
    # 	This means that if you simply issue an `CPU#rti`,
    # 	The byte immediately following the `CPU#brk` instruction will be ignored.
    # 	I have read reasons as to WHY this is the case, but frankly they all stink! ...Just deal with it!
    Break
    # ### The Decimal Flag
    # P.D dictates whether Addition (`CPU#adc`) and Subtraction (`CPU#sbc`) operate in the classic Binary or the more obscure [Binary Coded Decimal (BCD)](https://www.csh.rit.edu/~moffitt/docs/6502.html#BCD) mode.
    DecimalMode
    # ### The Interrupt (disable) Flag
    # When P.I is SET, Interrupt ReQuest signals (IRQs) to the IRQ pin (classically pin-4) are IGNORED
    # When P.I is CLEAR, signals to the IRQ pin are acknowledged.
    InterruptDisable
    # ### The Zero Flag
    # P.Z is SET when a zero value is placed in a register
    # P.Z is CLEARed when a non-zero value is placed in a register
    Zero
    # ### The Carry Flag
    # P.C can be considered to be the 9th bit of an arithmetic operation.
    Carry
  end


  # The 8-bit accumulator. Used in arithmetic operations
  getter accumulator : UInt8 = 0
  # The 8-bit x index register
  getter x_index : UInt8 = 0
  # The 8-bit y index register
  getter y_index : UInt8 = 0
  # The 8-bit stack pointer which points to the current position in the Stack.
  #
  # The stack ranges from 0x100 to 0x1FF, starting at 0x1FF
  getter stack_pointer : UInt8 = 255
  # The 16-bit program counter which points to the next instruction in the data bus to execute.
  #
  # Gets set after a command is read, but before it is executed.
  #
  # Meaning it points to the next instruction to execute, not the one that is currently executing
  getter program_counter : UInt16 = 0
  # The previous value that the program counter was set to.
  #
  # Used when `CPU#execute` and `CPU#step` have `end_on_tight_loop` set to `true`
  @previous_program_counter = -1
  # The CPU's 7 flag bits
  getter flags : UInt8 = 0b00100000
  # The clock cycle in megahertz to run at.
  #
  # Defaults to the NES's 6502 speed, 1.79mhz.
  #
  # Set in `CPU#initialize`
  getter clock_cycle_mhz : Float64 = 0
  # The cycles that the previous instruction used up.
  #
  # Used when calculating how long to sleep the CPU between instructions for a cycle accurate CPU
  @instruction_cycles : Int32 = 0
  # The current array of labels with the name, value, and if it is has been parsed
  @labels = [] of {String, UInt8 | UInt16, Bool}
  # Set to true when using the `CPU#stp` instruction. Stops any active execution
  @stop_exec = false

  # Creates a 6502 CPU
  #
  # The clock cycle is set in megahertz
  #
  # `reset` is the value set at `RES_LOCATION` and is used to find where the `program_counter` should start
  #
  # `brk` is the value set at `BRK_LOCATION` and is used to find where `CPU#brk` should goto
  def initialize(@clock_cycle_mhz : Float = 1.79, reset : UInt16 = 0, brk : UInt16 = 0)
    set_flag(Flags::InterruptDisable, true)

    poke(RES_LOCATION, reset)
    poke(BRK_LOCATION, brk)
    @program_counter = peek(RES_LOCATION, true).to_u16
  end

  # Runs the next instruction
  #
  # if `end_on_tight_loop` is `true`, it will not step if the current instruction sets the `program_counter` to itself, creating a tight loop
  #
  # NOTE: A real 6502 does not end on tight loops, this is only used to ensure that a program doesn't run forever
  def step(end_on_tight_loop : Bool = true)
    if end_on_tight_loop
      if @program_counter != @previous_program_counter
        @previous_program_counter = @program_counter
        run_instruction
      end
    else
      run_instruction
    end
  end

  # Runs all instructions
  #
  # If `end_on_tight_loop` is `true`, it will not step if the current instruction sets the `program_counter` to itself, creating a tight loop
  #
  # NOTE: A real 6502 does not end on tight loops, this is only used to ensure that a program doesn't run forever
  #
  # If `reset` is true, it will set the `CPU#program_counter` to its original value. If `reset` is false, it simply continues the code
  # from the last instruction. This is only really matters when `end_on_tight_loop` is true or when using `CPU#stp`
  #
  def execute(end_on_tight_loop : Bool = true, reset : Bool = true)
    @stop_exec = false

    if reset
      @program_counter = peek(0xfffc, true).to_u16
    else
      @previous_program_counter = -1
    end

    if end_on_tight_loop
      while @program_counter != @previous_program_counter && !@stop_exec
        sleep(1/@clock_cycle_mhz/1000000 * @instruction_cycles)
        @previous_program_counter = @program_counter
        run_instruction
      end
    else
      until @stop_exec
        sleep(1/@clock_cycle_mhz/1000000 * @instruction_cycles)
        run_instruction
      end
    end
  end

  # Calculates a byte into a [Binary Coded Decimal (BCD)](https://www.csh.rit.edu/~moffitt/docs/6502.html#BCD)
  #
  # BCD is whereby the upper and lower nibbles (4-bits) of a byte (8-bits) are treated as two digits in a decimal number;
  #
  # The upper nibble contains the number from the 'tens column'; and the lower nibble, the number from the 'units column'
  def bcd(byte : UInt8 | Int8)
    tens = byte.bits(4..7)
    ones = byte.bits(0..3)
    return "#{tens}#{ones}".to_u8
  end

  # Pokes a value into the data bus
  def poke(mem_location : UInt32 | Int32 | UInt16 | UInt8, data : UInt8 | UInt16)
  end

  # Reads a value from the data bus
  def peek(mem_location : UInt32 | Int32 | UInt16 | UInt8, two_byte : Bool = false) : UInt8 | UInt16
    return 0_u8
  end

  # Gets a the value of a bit in `flags`
  def get_flag(flag : Flags) : Bool
    case flag
    when Flags::Negative
      return true if @flags.bit(7) == 1
    when Flags::Overflow
      return true if @flags.bit(6) == 1
    when Flags::Break
      return true if @flags.bit(4) == 1
    when Flags::DecimalMode
      return true if @flags.bit(3) == 1
    when Flags::InterruptDisable
      return true if @flags.bit(2) == 1
    when Flags::Zero
      return true if @flags.bit(1) == 1
    when Flags::Carry
      return true if @flags.bit(0) == 1
    end

    return false
  end

  # Sets the value of a bit in `flags`
  def set_flag(flag : Flags, set : Bool)
    if set
      case flag
      when Flags::Negative
        @flags = @flags | 0b10000000
      when Flags::Overflow
        @flags = @flags | 0b01000000
      when Flags::Break
        @flags = @flags | 0b00010000
      when Flags::DecimalMode
        @flags = @flags | 0b00001000
      when Flags::InterruptDisable
        @flags = @flags | 0b00000100
      when Flags::Zero
        @flags = @flags | 0b00000010
      when Flags::Carry
        @flags = @flags | 0b00000001
      end
    else
      case flag
      when Flags::Negative
        @flags = @flags & 0b01111111
      when Flags::Overflow
        @flags = @flags & 0b10111111
      when Flags::Break
        @flags = @flags & 0b11101111
      when Flags::DecimalMode
        @flags = @flags & 0b11110111
      when Flags::InterruptDisable
        @flags = @flags & 0b11111011
      when Flags::Zero
        @flags = @flags & 0b11111101
      when Flags::Carry
        @flags = @flags & 0b11111110
      end
    end
  end
end
