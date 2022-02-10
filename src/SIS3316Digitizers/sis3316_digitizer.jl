# This file is a part of SIS3316Digitizers.jl, licensed under the MIT License (MIT).


new_sis3316_data_table() = Table(
    daqevtno = Vector{Int32}(),
    bufferno = Vector{Int32}(),
    channel = Vector{Int32}(),
    timestamp = Vector{Int64}(),
    energy = Vector{Int32}(),
    trigmax = Vector{Int32}(),
    samples = VectorOfVectors{UInt16}(),
    mawvalues = VectorOfVectors{Int32}(),
)

const SIS3316Data = typeof(new_sis3316_data_table())
export SIS3316Data

SIS3316Data() = new_sis3316_data_table()


Base.@kwdef struct EvtFormat
    save_mawvals::Bool = false              # Save (Energy or Trigger) MAW Test Data
    save_energy::Bool = false               # Save energy values (at trigger and maximum during trigger window)
    save_ft_maw::Bool = false               # Save fast trigger MAW values (max value, value before Trigger, value with Trigger)
    save_acc_78::Bool = false               # Save accumulator values for gates 7 and 8
    save_ph_acc16::Bool = false             # Save peak height and accumulator values for gates 1,2, ..,6
    n_samples::Int = 0                      # Number of raw samples to save
    n_mawvals::Int = 0                      # Number of MAW test data words to save

    # require n_samples % 2 == 0
end
export EvtFormat


function raw_event_data_size(fmt::EvtFormat)
    @argcheck fmt.n_samples % 2 == 0
    nEvtWords =
        2 +
        (fmt.save_ph_acc16  ? 7 : 0) +
        (fmt.save_acc_78    ? 2 : 0) +
        (fmt.save_ft_maw    ? 3 : 0) +
        (fmt.save_energy    ? 2 : 0) +
        1 +
        div(fmt.n_samples, 2) +
        (fmt.save_mawvals ? fmt.n_mawvals : 0)

    nEvtWords * sizeof(Int32)
end
export raw_event_data_size


Base.@kwdef struct ReadoutConfig
    channels::Vector{Int} = Vector{Int}(all_channels)
    buf_fill_threshold::Float64 = 0.5
    readout_interval::Float64 = 2.0
end
export ReadoutConfig


"""
    SIS3316Digitizer

Struck SIS 3316 VME Digitizer.

Constructors:

```julia
SIS3316Digitizer(mem::SIS3316Memory)
SIS3316Digitizer(hostname::AbstractString, port::Integer = 0xE000)
```
"""
mutable struct SIS3316Digitizer{Mem<:SIS3316Memory}
    mem::Mem
    fifo_mem_lock::ReentrantLock
    events::Observable{SIS3316Data}
    evtrate::Observable{Vector{Float64}}
    readout_config::ReadoutConfig
    readout_reqs::Channel{Bool}
end

export SIS3316Digitizer


function SIS3316Digitizer(hostname::AbstractString, port::Integer = 0xE000)
    gw = SIS3316Gateway(hostname, port)
    mem = SIS3316Memory(gw)
    fifo_mem_lock = ReentrantLock()
    events = Observable(SIS3316Data())
    evtrate = Observable(fill(0.0, length(all_channels)))
    readout_config = ReadoutConfig()
    readout_reqs = Channel{Bool}(); close(readout_reqs)

    dev = SIS3316Digitizer(mem, fifo_mem_lock, events, evtrate, readout_config, readout_reqs)
    dev.readout_reqs = readout_task(dev)

    finalizer(x -> close(x), dev)

    dev
end


Base.show(io::IO, dev::SIS3316Digitizer) = print(io, "SIS3316Digitizer($(repr(dev.mem)))")

@inline Base.Broadcast.broadcastable(dev::SIS3316Digitizer) = Ref(dev)


Base.isopen(dev::SIS3316Digitizer) = isopen(dev.mem)

function Base.close(dev::SIS3316Digitizer)
    close(dev.mem)
end


function readout_task(dev::SIS3316Digitizer; sleep_interval_ns::Integer = 50 * 10^6)
    Channel{Bool}(0; taskref = nothing, spawn = true) do readout_reqs
        try
            @debug "SIS3316Digitizer readout task started"
            while isopen(dev)
                if take!(readout_reqs) == true
                    @info "Sampling starting" 
                    sampling_loop(dev, readout_reqs; sleep_interval_ns = sleep_interval_ns)
                end
                @info "Sampling stopped"
            end
            @debug "SIS3316Digitizer readout task terminating"
        catch err
            @error err
            close(dev)
        end
    end
end


function sampling_loop(dev::SIS3316Digitizer, readout_reqs::Channel{Bool}; sleep_interval_ns::Integer = 50 * 10^6)
    nbuf::Int = 1
    last_check::UInt64 = time_ns()
    last_readout::UInt64 = last_check
    nbytes_filled_last = fill(0.0, length(all_channels))
    start_capture(dev)

    active::Bool = true
    while active && isopen(dev)
        if isready(readout_reqs) && take!(readout_reqs) == false
            stop_capture(dev)
            active = false
            #!!! TODO: Read out last buffer if necessary
        else
            bnkinfo = get_bank_info(dev, all_channels)
            curr_time = time_ns()

            delta_t_check = (curr_time - last_check) * 1e-9
            delta_t_readout = (curr_time - last_readout) * 1e-9
            nbytes_filled = map(x -> Int(x.sampling_nbytes), bnkinfo)
            evt_nbytes = map(x -> raw_event_data_size(x.event_format), bnkinfo)

            dev.evtrate[] = (nbytes_filled .- nbytes_filled_last) ./ evt_nbytes ./ delta_t_check

            readout_config = dev.readout_config
            buf_over_thresh = any(nbytes_filled ./ ch_buffer_size .>= readout_config.buf_fill_threshold)

            if buf_over_thresh || delta_t_readout > readout_config.readout_interval
                @debug "Swapping buffers and reading out"
                swap_banks(dev)
                events = readout_parsed(dev, nbuf, readout_config.channels)
                dev.events[] = events
                last_readout = curr_time
                nbuf += 1
            end
            last_check = curr_time
            nbytes_filled_last .= nbytes_filled
        end
    end
    nothing
end


function set_capture!(dev::SIS3316Digitizer, state::Bool)
    push!(dev.readout_reqs, state)
end
export set_capture!


function arm_bank(dev::SIS3316Digitizer, bank::Integer)
    @argcheck bank in all_banks
    # sync #!!!
    dev.mem[key_disarm_and_arm_bank_addr[bank]] = 1
end
export arm_bank


function swap_banks(dev::SIS3316Digitizer)
    # sync #!!!
    sampling_bank = dev.mem[actual_sample_address_regs[1].bank]
    arm_bank(dev, sampling_bank == 1 ? 2 : 1)
end
export swap_banks


function clear_and_arm(dev::SIS3316Digitizer)
    arm_bank(dev, 2)
    arm_bank(dev, 1)
end
export clear_and_arm


function disarm(dev)
    # sync #!!!
    dev.mem[key_disarm_addr] = 1
    nothing
end
export disarm


function start_capture(dev)
    @info "Starting capture"
    disarm(dev)
    clear_and_arm(dev)
end
export start_capture


function stop_capture(dev)
    @info "Stopping capture"
    disarm(dev)
end
export stop_capture


function event_format(dev::SIS3316Digitizer, ch::Integer)
    @argcheck ch in all_channels

    # TODO: Add support for extended sample length
    # TODO: Add support for averaging value data format

    mem = dev.mem
    group, grp_ch = fpga_num(ch), fpga_ch(ch)

    @mt_out_of_order begin
        cfg = mem[dataformat_config_regs[group].ch[grp_ch]]
        n_samples = mem[raw_data_buffer_config_regs[group].sample_length]
        n_mawvals = mem[maw_test_buffer_config_regs[group].buffer_len]
    end

    EvtFormat(
        save_mawvals = cfg.save_mawvals,
        save_energy = cfg.save_energy,
        save_ft_maw = cfg.save_ft_maw,
        save_acc_78 = cfg.save_acc_78,
        save_ph_acc16 = cfg.save_ph_acc16,
        n_samples = n_samples,
        n_mawvals = n_mawvals
    )
end
export event_format


Base.@kwdef struct BankInfo
    sampling_bank::Int = 0
    sampling_nbytes::Int = 0
    readout_bank::Int = 0
    readout_nbytes::Int = 0
    event_format::EvtFormat = EvtFormat()
end

export BankInfo

function BankInfo(dev::SIS3316Digitizer, ch::Integer)
    @mt_out_of_order begin
        sampling_bank::Int = dev.mem[actual_sample_address_regs[ch].bank]
        sampling_nbytes::Int = dev.mem[actual_sample_address_regs[ch].sample_addr]
        readout_bank::Int = dev.mem[previous_bank_sample_address_regs[ch].bank]
        readout_nbytes::Int = dev.mem[previous_bank_sample_address_regs[ch].sample_addr]
        evtfmt::EvtFormat = event_format(dev, ch)
    end

    BankInfo(sampling_bank, sampling_nbytes, readout_bank, readout_nbytes, evtfmt)
end


function get_bank_info(dev::SIS3316Digitizer, channels::AbstractVector{<:Integer} = all_channels)
    result = fetch.(map(ch -> @mt_async(BankInfo(dev, ch)), all_channels))
    convert(Vector{BankInfo}, result)::Vector{BankInfo}
end
function get_bank_info end


function print_bank_info(dev::SIS3316Digitizer)
    bankinfo = get_bank_info(dev, all_channels)
    for ch in all_channels
        bi = bankinfo[ch]
        raw_event_size = raw_event_data_size(bi.event_format)

        sampling_n_events = bi.sampling_nbytes / raw_event_size
        readout_n_events = bi.readout_nbytes / raw_event_size

        @info "Channel $ch: Bank $(bi.sampling_bank) armed: bank $(bi.sampling_nbytes) bytes (sampling_n_events), bank $(bi.readout_bank) readout: $(bi.readout_nbytes) bytes (bi.readout_n_events events)"
    end
end
export print_bank_info


function read_ch_bank_data(dev::SIS3316Digitizer, ch::Integer, bank::Integer, from::Integer = 0, n_bytes::Integer = ch_buffer_size)
    group = fpga_num(ch)
    lock(dev.fifo_mem_lock) do
        read_ch_bank_data(dev.mem, ch::Integer, bank::Integer, from, n_bytes)
    end
end
export read_ch_bank_data



function readout_raw(dev::SIS3316Digitizer, channels::AbstractVector{<:Integer})
    binfo = get_bank_info(dev, channels)

    futures = map(channels) do ch
        @mt_async begin
            bi = binfo[ch]
            read_ch_bank_data(dev, ch, bi.readout_bank, 0, bi.readout_nbytes)
        end
    end

    fetch.(futures)
end
export readout_raw


function readout_parsed(dev::SIS3316Digitizer, bufno::Integer, channels::AbstractVector{<:Integer})
    binfo = get_bank_info(dev, channels)

    futures = map(channels) do ch
        @mt_async begin
            bi = binfo[ch]
            data = read_ch_bank_data(dev, ch, bi.readout_bank, 0, bi.readout_nbytes)
            parse_bank_data(data, ch, bufno, bi.event_format)
        end
    end

    vcat(fetch.(futures)...)::SIS3316Data
end
export readout_parsed


function parse_bank_data!(result::Table, data::AbstractVector{UInt8}, channel::Integer, bufno::Integer, fmt::EvtFormat)
    evt_nbytes = raw_event_data_size(fmt)
    total_nbytes = length(eachindex(data))
    mod(total_nbytes, evt_nbytes) == 0 || throw(ArgumentError("Length of data buffer not a multiple of event size"))
    nevents = div(total_nbytes, evt_nbytes)    

    nmawvalues = fmt.save_mawvals ? fmt.n_mawvals : 0
    firmware_type = FW250 # ToDo: auto-detect

    tmpbuffer = Vector{Int32}()
    evtdatabuf = IOBuffer(data)
    evtno = 0

    for i in 1:nevents
        evtno += 1
        evt = read(evtdatabuf, RawChEvent, nmawvalues, firmware_type, tmpbuffer)

        push!(result.daqevtno, evtno)
        push!(result.channel, channel)
        push!(result.bufferno, bufno)
        push!(result.timestamp, evt.timestamp)
        push!(result.energy, isnothing(evt.energy) ? Int32(0) : evt.energy.maximum)
        push!(result.trigmax, isnothing(evt.trig_maw) ? Int32(0) : evt.trig_maw.maximum)
        push!(result.samples, evt.samples)
        push!(result.mawvalues, evt.mawvalues)
    end

    result
end
parse_bank_data!


function parse_bank_data(data::AbstractVector{UInt8}, channel::Integer, bufno::Integer, fmt::EvtFormat)
    parse_bank_data!(SIS3316Data(), data, channel, bufno, fmt)
end
export parse_bank_data
