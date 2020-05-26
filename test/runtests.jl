# This file is a part of StruckVMEDevices.jl, licensed under the MIT License (MIT).

import Test
Test.@testset "Package StruckVMEDevices" begin

include("MemRegisters/runtests.jl")
include("VMEGateways/runtests.jl")
include("SIS3316Digitizers/runtests.jl")

end # testset
