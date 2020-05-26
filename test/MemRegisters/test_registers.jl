# This file is a part of SIS3316Digitizers.jl, licensed under the MIT License (MIT).

using StruckVMEDevices.MemRegisters
using Test

using Tables, TypedTables

@testset "registers" begin
    @enum SomeIntEnum::UInt8 begin
        SIE_FOO = 0 
        SIE_BAR = 1
        SIE_BAZ = 2
    end

    @enum SomeBoolEnum::Bool begin
        SBE_FOO = false
        SBE_BAR = true
    end

    shift_by_one = (x -> signed(x + 1), x -> unsigned(x) - 1)
    bool_to_3_4 = (x -> (x ? 4 : 3), x -> Bool(x - 3))

    @test bits_to_val(0x42, LiteralBits()) == 0x42
    @test val_to_bits(0x42, LiteralBits()) == 0x42

    @test bits_to_val(0x42, TransformedBits(shift_by_one...)) == 67
    @test val_to_bits(67, TransformedBits(shift_by_one...)) == 0x42

    @test bits_to_val(0x01, EnumBits(SomeIntEnum)) == SIE_BAR
    @test val_to_bits(SIE_BAR, EnumBits(SomeIntEnum)) == 0x01

    @test bits_to_val(true, EnumBits(SomeBoolEnum)) == SBE_BAR
    @test val_to_bits(SBE_BAR, EnumBits(SomeBoolEnum)) == true


    @test getraw(0x5a, Bit{RW}(1)) == true
    @test setraw(0x50, Bit{RW}(1), true) == 0x52

    @test getval(0x5a, Bit{RO}(1)) == true
    @test getval(0x5a, Bit{RO}(1, bool_to_3_4)) == 4
    @test getval(0x5a, Bit{RO}(1, SomeBoolEnum)) == SBE_BAR

    @test setval(0x50, Bit{WO}(1), true) == 0x52
    @test setval(0x50, Bit{WO}(1, bool_to_3_4), 4) == 0x52
    @test setval(0x50, Bit{WO}(1, SomeBoolEnum), SBE_BAR) == 0x52

    @test getraw(0xa5, BitRange{RO}(1:2)) == 0x02
    @test setraw(0xa0, BitRange{WO}(1:2), 0x02) == 0xa4

    @test getval(0xa5, BitRange{RW}(1:2)) == 0x02
    @test getval(0xa5, BitRange{RW}(1:2, shift_by_one)) == 3
    @test getval(0xa5, BitRange{RW}(1:2, SomeIntEnum)) == SIE_BAZ

    @test setval(0x50, BitRange{RW}(1:2), 0x02) == 0x54
    @test setval(0x50, BitRange{RW}(1:2, shift_by_one), 3) == 0x54
    @test setval(0x50, BitRange{RW}(1:2, SomeIntEnum), SIE_BAZ) == 0x54

    @test setraw(BitWriteOperation{UInt32}(0, 0, true), BitRange{JKRW}(4:7), 0x05) == BitWriteOperation{UInt32}(0x00a00050, 0xffffffff, true)
    @test setraw(BitWriteOperation{UInt32}(0x00a00050, 0xffffffff, true), Bit{JKRW}(1), true) == BitWriteOperation{UInt32}(0x00a00052, 0xffffffff, true)
    @test setraw(BitWriteOperation{UInt32}(0x00a00050, 0xffffffff, true), Bit{JKRW}(1), false) == BitWriteOperation{UInt32}(0x00a20050, 0xffffffff, true)
    @test_throws ArgumentError setraw(BitWriteOperation{UInt32}(0x0, 0x1, true), BitRange{JKRW}(4:7), 0x05)
    @test_throws ArgumentError setraw(BitWriteOperation{UInt32}(0, 0, false), BitRange{JKRW}(4:7), 0x05)

    @test @inferred(merge(
        BitWriteOperation{UInt32}(0x000000ff, 0x0f00ffff, false),
        BitWriteOperation{UInt32}(0xf000f000, 0xf000f00f, false)
    )) == BitWriteOperation{UInt32}(0xf000f0f0, 0xff00ffff, false)

    @test @inferred(merge(
        BitWriteOperation{UInt32}(0xff0000ff, 0xffffffff, true),
        BitWriteOperation{UInt32}(0x000ff000, 0xffffffff, true)
    )) == BitWriteOperation{UInt32}(0x0f0ff0f0, 0xffffffff, true)

    nbits = (a = Bit{RO}(5), b = BitRange{WO}(4:5, SomeIntEnum))

    @test @inferred(Register{RW,UInt32}(0x08, nbits)) isa Register
    @test isbits(Register{RW,UInt32}(0x08, nbits))

    reg = Register{RW,UInt32}(0x08, nbits)

    @test @inferred((r -> (;r...))(reg)) == nbits

    @test @inferred((x -> x.a)(reg)) == BitSelRef{UInt32}(0x08, Bit{RO}(5))

    @test @inferred(keys(reg)) == (:a, :b)
    @test reg[:b] == BitSelRef{UInt32}(0x08, BitRange{WO}(4:5, SomeIntEnum))
    
    @test @inferred(filter(Readable, getlayout(reg))) == (a = Bit{RO}(5),)
    @test @inferred(filter(Writeable, getlayout(reg))) == (b = BitRange{WO}(4:5, SomeIntEnum),)

    reg2 = Register{RW,UInt16}(UInt32(0x08), (a = Bit{RW}(3, SomeBoolEnum), b = BitRange{RW}(4:7, SomeIntEnum)));
end
