# This file is a part of StruckVMEDevices.jl, licensed under the MIT License (MIT).

module SIS3316Digitizers

using ArraysOfArrays
using BitOperations
using ElasticArrays
using UnsafeArrays

include("evtformat.jl")
include("read_data.jl")

end # module
