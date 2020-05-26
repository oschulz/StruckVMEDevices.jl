# This file is a part of SIS3316Digitizers.jl, licensed under the MIT License (MIT).

function multiple_tries(thunk, n_tries::Integer, error_types::NTuple{N,Type}, action_description::String) where N
    for i in 1:n_tries
        # i > 1 && @info "$action_description, retry no $(i - 1)"
        try
            return thunk()
        catch err
            if !(typeof(err) in error_types)
                @error "$action_description failed with error $err, does not qualify for retry"
                rethrow()
            elseif i < n_tries
                @info "$action_description failed with error $err, retrying $((n_tries - i)) more times"
            else
                @error "$action_description failed with error $err, giving up after $n_tries tries"
                rethrow()
            end
        end
    end
    @assert false "Shouldn't have reached this part of code"
end
export multiple_tries



const MemAddr = UInt32
const RegVal = UInt32


struct RegisterReadOperation{A<:Unsigned,V<:Unsigned}
    addr::A
    val_ch::Channel{V}
end

struct RegisterWriteOperation{A<:Unsigned,V<:Unsigned}
    addr::A
    op::BitWriteOperation{V}
    ack_ch::Channel{Nothing}
end

const RegisterOperation{A<:Unsigned,V<:Unsigned} = Union{RegisterReadOperation{A,V}, RegisterWriteOperation{A,V}}

const OpsChannel = Channel{RegisterOperation{MemAddr, RegVal}}



mutable struct SIS3316Memory{GW<:AbstractVMEGateway}
    gw::GW
    ops_queue::OpsChannel
    fifo_lock::ReentrantLock
end

export SIS3316Memory


function SIS3316Memory(gw::AbstractVMEGateway)
    ops_queue = start_rwtask(gw)
    fifo_lock = ReentrantLock()
    SIS3316Memory(gw, ops_queue, fifo_lock)
end

Base.show(io::IO, mem::SIS3316Memory) = print(io, "SIS3316Memory($(repr(mem.gw)))")

Base.deepcopy(mem::SIS3316Memory) = SIS3316Memory(deepcopy(mem.gw))

@inline Base.Broadcast.broadcastable(mem::SIS3316Memory) = Ref(mem)


Base.isopen(mem::SIS3316Memory) = isopen(mem.ops_queue)

function Base.close(mem::SIS3316Memory)
    if isopen(mem.ops_queue)
        # @info "Closing $mem" # logging causes trouble in finalizers
        close(mem.ops_queue)
        # close(mem) # Could possibly cause race condition with rwtask shutdown
        # @info "Closed $mem" # logging causes trouble in finalizers
    end
end


function Base.getindex(mem::SIS3316Memory, addr::Integer)
    conv_addr = convert(MemAddr, addr)
    val_ch = Channel{RegVal}(1)
    push!(mem.ops_queue, RegisterReadOperation(conv_addr, val_ch))
    x = take!(val_ch)
    close(val_ch)
    x
end

function Base.getindex(mem::SIS3316Memory, ref::Union{Register,BitSelRef})
    x = mem[getaddress(ref)]
    getval(x, getlayout(ref))
end


function Base.setindex!(mem::SIS3316Memory, value::Integer, addr::Integer)
    conv_addr = convert(MemAddr, addr)
    conv_value = convert(RegVal, value)
    setindex!(mem, BitWriteOperation(conv_value, ~zero(conv_value), false), conv_addr)
end

function Base.setindex!(mem::SIS3316Memory, value::BitWriteOperation{RegVal}, addr::Integer)
    conv_addr = convert(MemAddr, addr)
    ack_ch = Channel{Nothing}(1)
    push!(mem.ops_queue, RegisterWriteOperation(conv_addr, value, ack_ch))
    take!(ack_ch)
    close(ack_ch)
    mem
end

function Base.setindex!(mem::SIS3316Memory, value, ref::Union{Register,BitSelRef})
    op = setval(BitWriteOperation{UInt32}(getaccessmode(ref)), getlayout(ref), value)
    setindex!(mem, op, getaddress(ref))
end


function start_rwtask(gw::AbstractVMEGateway)
    OpsChannel(100; taskref = nothing, spawn = true) do ops_queue
        write_ops = Vector{RegisterWriteOperation{MemAddr,RegVal}}()
        read_ops = Vector{RegisterReadOperation{MemAddr,RegVal}}()

        store_op(op::RegisterWriteOperation) = push!(write_ops, op)
        store_op(op::RegisterReadOperation) = push!(read_ops, op)

        try
            @debug "SIS3316MemState r/w task started"
            while true
                # @debug "Waiting for operations"
                wait(ops_queue)
       
                while isready(ops_queue)
                    op = store_op(take!(ops_queue))
                end

                # Give other tasks a chance to push more operations
                yield()
                
                # Try to maximize ops merging, don't process while more ops incoming
                if !isready(ops_queue)
                    execute_mem_ops!(gw, write_ops, read_ops)
                    @assert isempty(write_ops)
                    @assert isempty(read_ops)
                end
            end
        catch err
            if err isa InvalidStateException && !isopen(ops_queue)
                @debug "SIS3316MemState r/w task closed and terminating"
            else
                @error err
                rethrow()
            end
        finally
            close(gw)
        end
    end
end


function execute_mem_ops!(
    gw::AbstractVMEGateway,
    write_ops::Vector{RegisterWriteOperation{MemAddr,RegVal}},
    read_ops::Vector{RegisterReadOperation{MemAddr,RegVal}}
)
    try
        # @debug "Operations to execute" write_ops read_ops
        
        if !isempty(write_ops)
            let
                # @debug "Executing write operations"
                combined_writes = IdDict{MemAddr,BitWriteOperation{RegVal}}()
                for reg_write in write_ops
                    if haskey(combined_writes, reg_write.addr)
                        combined_writes[reg_write.addr] = merge(combined_writes[reg_write.addr], reg_write.op)
                    else
                        combined_writes[reg_write.addr] = reg_write.op
                    end
                end
                @debug "To write:" combined_writes
    
                write_addrs = sort(collect(keys(combined_writes)))
                wrtops = getindex.(Ref(combined_writes), write_addrs)
                write_values = map(x -> x.value, wrtops)
                with_mask_idxs = findall(is_masked, wrtops)
                with_mask_addrs = write_addrs[with_mask_idxs]
                with_mask_ops = wrtops[with_mask_idxs]
                currvals = Vector{RegVal}(undef, length(with_mask_addrs))
                if !isempty(with_mask_addrs)
                    read_registers!(gw, with_mask_addrs, currvals)
                end
                # @debug "Read current values $(repr(currvals)) from addresses $(repr(with_mask_addrs)) before writing"
                write_values[with_mask_idxs] .= bset.(currvals, with_mask_ops)
                write_registers!(gw, write_addrs, write_values)

                while !isempty(write_ops)
                    op = first(write_ops)
                    result = nothing
                    push!(op.ack_ch, result)
                    popfirst!(write_ops)
                end
            end
        end

        if !isempty(read_ops)
            let
                # @debug "Executing read operations"
                combined_reads = sort(collect(Set(reg_read.addr for reg_read in read_ops)))
                @debug "To read:" combined_reads

                read_addrs = sort(collect(Set(reg_read.addr for reg_read in read_ops)))
                read_values = Vector{RegVal}(undef, length(read_addrs))
                read_registers!(gw, read_addrs, read_values)
                read_results = IdDict{MemAddr,RegVal}()
                for (a, v) in zip(read_addrs, read_values)
                    read_results[a] = v
                end

                # @debug "Read results" read_addrs read_values read_results
                while !isempty(read_ops)
                    op = first(read_ops)
                    result = read_results[op.addr]
                    @debug "Pushing to result channel: $(repr(result))"
                    push!(op.val_ch, result)
                    popfirst!(read_ops)
                end
            end
        end
    catch err
        if err isa EOFError
            @warn "UDP Timeout"
        else
            @warn err
        end

        # Cancel all pending operations:

        for op in write_ops
            close(op.ack_ch)
        end
        empty!(write_ops)

        for op in read_ops
            close(op.val_ch)
        end
        empty!(read_ops)
    finally
        @assert isempty(write_ops)
        @assert isempty(read_ops)
    end
end
