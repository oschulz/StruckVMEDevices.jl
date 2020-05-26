# This file is a part of StruckVMEDevices.jl, licensed under the MIT License (MIT).

module VMEGateways

using ArraysOfArrays
using BitOperations
using ElasticArrays
using Sockets
using StructArrays
using Tables
using TypedTables
using UnsafeArrays

using Base.Threads: Atomic

using ..MemRegisters

include("vme.jl")
include("abstract_vme_gateway.jl")
include("sis3316_gateway.jl")

end # module
