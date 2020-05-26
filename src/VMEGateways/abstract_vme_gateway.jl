# This file is a part of SIS3316Digitizers.jl, licensed under the MIT License (MIT).


"""
    AbstractVMEGateway

Abstract type for VME Gateways.

Required functionality for subtypes:

* [`read_registers`](@ref)
* [`write_registers!`](@ref)
* [`read_fifo_space!`](@ref)
* [`Base.close`](@ref)
"""
abstract type AbstractVMEGateway end

export AbstractVMEGateway

@inline Base.Broadcast.broadcastable(gw::AbstractVMEGateway) = Ref(gw)


"""
    read_registers!(
        gw::AbstractVMEGateway,
        addrs::AbstractVector{<:Unsigned}, values::AbstractVector{<:Unsigned};
        timeout::Float64 = ...
    )::typeof(values)

Read VME register values via gateway `gw`.

Vectors `addrs` and `values` must have the same length. Returns `values`.

There is no guarantee on the order in which the read operations are executed.
Depending on the hardware, read operations may be executed in batches.
The `timeout` value is applied to each internal read operation.
"""
function read_registers! end
export read_registers!


"""
    write_registers!(
        gw::AbstractVMEGateway,
        addrs::AbstractVector{<:Unsigned}, values::AbstractVector{<:Unsigned};
        timeout::Float64 = ...
    )::Nothing

Write VME register values via gateway `gw`.

Vectors `addrs` and `values` must have the same length.

There is no guarantee on the order in which the write operations are executed.
Depending on the hardware, write operations may be executed in batches.
The `timeout` value is applied to each internal write operation.
"""
function write_registers! end
export write_registers!


"""
    read_bulk!(
        gw::AbstractVMEGateway,
        addr::Unsigned,
        data::AbstractVector{UInt32};
        timeout::Float64 = gw.default_timeout
    )

Fast bulk data read transfer.
"""
function read_bulk! end
export read_bulk!


"""
    struct DummyVMEGateway{Addr<:Unsigned,Value<:Unsigned} <: AbstractVMEGateway

Dummy VME Gateway.
"""
struct DummyVMEGateway{Addr<:Unsigned,Value<:Unsigned} <: AbstractVMEGateway
    state::IdDict{Addr,Value}
end

export DummyVMEGateway

function DummyVMEGateway{Addr,Value}() where {Addr<:Unsigned,Value<:Unsigned}
    DummyVMEGateway{Addr,Value}(IdDict{Addr,Value}())
end


Base.deepcopy(gw::DummyVMEGateway{Addr,Value}) where {Addr,Value} = DummyVMEGateway{Addr,Value}()


function read_registers!(
    gw::DummyVMEGateway{Addr,Value},
    addrs::AbstractVector{<:Addr},
    values::AbstractVector{<:Value};
    timeout::Float64 = 0.005
) where {Addr,Value}
    @debug "read_registers!(::DummyVMEGateway, $addrs, $values)"
    length(addrs) == length(values) || throw(ArgumentError("Number of addresses does not match number of values"))
    values .= [get(gw.state, a, zero(Value)) for a in addrs]
    values
end


function write_registers!(
    gw::DummyVMEGateway{Addr,Value},
    addrs::AbstractVector{<:Addr},
    values::AbstractVector{<:Value};
    timeout::Float64 = 0.005
) where {Addr,Value}
    @debug "write_registers!(::DummyVMEGateway, $addrs, $values)"
    length(addrs) == length(values) || throw(ArgumentError("Number of addresses does not match number of values"))
    for (a, v) in zip(addrs, values)
        gw.state[a] = v
    end
    nothing
end


Base.isopen(gw::DummyVMEGateway) = true

function Base.close(gw::DummyVMEGateway)
    empty!(gw.state)
    # @info "Closed $gw" # logging causes trouble in finalizers
end


function read_bulk!(gw::DummyVMEGateway, addr::UInt32, data::AbstractVector{UInt32})
    # @debug "read_bulk!(::DummyVMEGateway, $(repr(addr)), data)" 
    for i in eachindex(data)
        data[i] = addr + i - firstindex(data)
    end
    data
end
