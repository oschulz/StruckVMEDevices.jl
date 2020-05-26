# This file is a part of SIS3316Digitizers.jl, licensed under the MIT License (MIT).


@enum VMEAddressSpace begin
    VME_A16 = 16
    VME_A24 = 24
    VME_A32 = 32
    VME_A64 = 64
end
export VMEAddressSpace


@enum VMEDataWidth begin
    VME_D8  =  8
    VME_D16 = 16
    VME_D32 = 32
    VME_D64 = 64
end
export VMEDataWidth


@enum VMECycle begin
    VME_SCT         = 0
    VME_BLT         = 1
    VME_MBLT        = 2
    VME_eeVME       = 3
    VME_eeSST160    = 4
    VME_eeSST267    = 5
    VME_eeSST320    = 6
end
export VMECycle


struct VMEMode
    space::VMEAddressSpace
    width::VMEDataWidth
    cycle::VMECycle
end
export VMEMode


const VME_A32_D32_SCT = VMEMode(VME_A32, VME_D32, VME_SCT)
const VME_A32_D32_BLT = VMEMode(VME_A32, VME_D32, VME_SCT)
const VME_A32_D64_MBLT = VMEMode(VME_A32, VME_D64, VME_MBLT)
const VME_A32_D64_2eVME = VMEMode(VME_A32, VME_D64, VME_eeVME)
