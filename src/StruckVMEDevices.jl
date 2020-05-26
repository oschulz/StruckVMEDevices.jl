# This file is a part of StruckVMEDevices.jl, licensed under the MIT License (MIT).

__precompile__(true)

module StruckVMEDevices

include("MemRegisters/MemRegisters.jl")
include("VMEGateways/VMEGateways.jl")
include("SIS3316Digitizers/SIS3316Digitizers.jl")

end # module
