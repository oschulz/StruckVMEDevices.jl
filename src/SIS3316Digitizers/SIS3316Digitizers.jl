# This file is a part of StruckVMEDevices.jl, licensed under the MIT License (MIT).

module SIS3316Digitizers

using Base.Threads

using ArgCheck
using ArraysOfArrays
using BitOperations
using ElasticArrays
using Observables
using ParallelProcessingTools
using UnsafeArrays
using Sockets
using Tables
using TypedTables

using ..MemRegisters
using ..VMEGateways

include("evtformat.jl")
include("read_data.jl")
include("memory.jl")
include("memregs.jl")
include("memfifo.jl")
include("sis3316_digitizer.jl")

end # module
