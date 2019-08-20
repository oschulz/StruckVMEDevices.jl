# This file is a part of SIS3316Digitizers.jl, licensed under the MIT License (MIT).

__precompile__(true)

module SIS3316Digitizers

using ArraysOfArrays
using BitOperations
using ElasticArrays
using UnsafeArrays

include("evtformat.jl")
include("read_data.jl")
include("sortevents.jl")
include("filters.jl")

end # module
