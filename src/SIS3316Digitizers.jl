# This file is a part of SIS3316Digitizers.jl, licensed under the MIT License (MIT).

__precompile__(true)

module SIS3316Digitizers

using BitOperations

include("evtformat.jl")
include("sortevents.jl")
include("filters.jl")

end # module
