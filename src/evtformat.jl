# This file is a part of StruckVMEDevices.jl, licensed under the MIT License (MIT).

if ENDIAN_BOM == 0x01020304
    _ltoh!(x) = bswap!(x)
elseif ENDIAN_BOM == 0x04030201
    _ltoh!(x) = x
end


import Base.read, Base.write, Base.time

export eachchunk


module RegisterBits
    using BitOperations

    export RegBit, RegBits

    struct RegBit
        bit::Int
    end

    (regbit::RegBit)(x::Integer) = bget(x, regbit.bit)


    struct RegBits
        bits::UnitRange{Int64}
    end

    (regbits::RegBits)(x::Integer) = bget(x, regbits.bits)
end



module EventFormat
    using BitOperations

    export evt_data_hdr1
    module evt_data_hdr1
        using StruckVMEDevices.RegisterBits
        const timestamp_high    = RegBits(16:31)  # Timestamp, high bits
        const ch_id             = RegBits( 4:15)  # Channel ID
        const have_energy       = RegBit(3)  # Event contains Start Energy MAW value and Max. Energy MAW value
        const have_ft_maw       = RegBit(2)  # Event contains 3 x Fast Trigger MAW values (max value, value before Trigger, value with Trigger)
        const have_acc_78       = RegBit(1)  # Event contains 2 x Accumulator values (Gates 7,8)
        const have_ph_acc16     = RegBit(0)  # Event contains Peak High values and 6 x Accumulator values (Gates 1,2, ..,6)
    end

    export evt_data_hdr2
    module evt_data_hdr2
        using StruckVMEDevices.RegisterBits
        const timestamp_low     = RegBits(0:31)  # Timestamp, low bits
    end

    export evt_data_peak_height
    module evt_data_peak_height
        using StruckVMEDevices.RegisterBits
        const peak_heigh_idx    = RegBits(16:31)  # Index of Peakhigh value
        const peak_heigh_val    = RegBits( 0:15)  # Peakhigh value
    end

    export evt_data_acc_sum_g1
    module evt_data_acc_sum_g1
        using StruckVMEDevices.RegisterBits
        const overflow_flag     = RegBit(24 + 7)  # Overflow flag
        const underflow_flag    = RegBit(24 + 6)  # Underflow flag
        const repileup_flag     = RegBit(24 + 5)  # RePileup flag
        const pileup_flag       = RegBit(24 + 4)  # Pileup flag
        const acc_sum_g1        = RegBits(0:23)  # Accumulator sum of Gate 1
    end

    export evt_data_acc_sum
    module evt_data_acc_sum
        using StruckVMEDevices.RegisterBits
        const acc_sum           = RegBits(0:27)  # Accumulator sum of Gate (for Gates 2 to 8)
    end

    export evt_data_maw_value
    module evt_data_maw_value
        using StruckVMEDevices.RegisterBits
        # Note: Documentation says bit 0..27, but for some reason bit 27 seems
        # to (always?) be set:
        const maw_val           = RegBits(0:26)  # MAW value (maximum or value before or after trigger)
    end

    export evt_samples_hdr
    module evt_samples_hdr
        using StruckVMEDevices.RegisterBits
        const const_tag         = RegBits(28:31)  # Always 0xE
        const maw_test_flag     = RegBit(27)  # MAW Test Flag
        const any_pileup_flag   = RegBit(26)  # RePileup or Pileup Flag
        const n_sample_words    = RegBits(0:25) # number of raw samples (x 2 samples, 32-bit words)
    end
end

using StruckVMEDevices.EventFormat



const multievt_buf_header = UInt32(0xdeadbeef)


@enum FirmwareType FW250=0 FW125=1


sample_clock(fw::FirmwareType) = begin
    if fw == FW250
        250E6
    elseif fw == FW125
        125E6
    else
        error("Unsupported firmware type")
    end
end


struct BankChannelHeaderInfo
    firmware_type::FirmwareType
    bufferno::Int
    channel::Int
    nevents::Int
    nwords_per_event::Int
    nmawvalues::Int
    reserved::Int
end


read(io::IO, ::Type{BankChannelHeaderInfo}) = begin
    @assert ltoh(read(io, UInt32)) == multievt_buf_header
    BankChannelHeaderInfo(
        FirmwareType(ltoh(read(io, UInt32))),
        Int(ltoh(read(io, UInt32))),
        Int(ltoh(read(io, UInt32))) + 1,
        Int(ltoh(read(io, UInt32))),
        Int(ltoh(read(io, UInt32))),
        Int(ltoh(read(io, UInt32))),
        Int(ltoh(read(io, UInt32))),
    )
end

write(io::IO, header::BankChannelHeaderInfo) = write(io,
    multievt_buf_header,
    UInt32(header.firmware_type),
    UInt32(header.bufferno),
    UInt32(header.channel - 1),
    UInt32(header.nevents),
    UInt32(header.nwords_per_event),
    UInt32(header.nmawvalues),
    UInt32(header.reserved)
)


struct EvtFlags
    overflow::Bool
    underflow::Bool
    repileup::Bool
    pileup::Bool
end


struct PSAValue
    index::Int32
    value::Int32
end


struct MAWValues
    maximum::Int32
    preTrig::Int32
    postTrig::Int32
end


struct EnergyValues
    initial::Int32
    maximum::Int32
end


struct RawChEvent
  chid::Int32
  firmware_type::FirmwareType
  timestamp::Int64
  flags::Union{EvtFlags, Nothing}
  accsums::Vector{Int32}
  peak_height::Union{PSAValue, Nothing}
  trig_maw::Union{MAWValues, Nothing}
  energy::Union{EnergyValues, Nothing}
  pileup_flag::Bool
  samples::Vector{Int32}
  mawvalues::Vector{Int32}
end

time(evt::RawChEvent) = evt.timestamp / sample_clock(evt.firmware_type)


const UnsortedEvents = Dict{Int, Vector{RawChEvent}}
const SortedEvents = Vector{Dict{Int, RawChEvent}}



read_samples!(io::IO, samples::Vector{Int32}, nsamplewords::Int, tmpbuffer::Vector{Int32}) = begin
    resize!(tmpbuffer, nsamplewords)
    read!(io, tmpbuffer)
    _ltoh!(tmpbuffer)
    resize!(samples, 2*length(tmpbuffer))

    idxs = eachindex(tmpbuffer)
    if !isempty(idxs)
        checkbounds(samples, 2*first(idxs) - 1)
        checkbounds(samples, 2*last(idxs)  - 0)
    end
    @inbounds @simd for i in idxs
        x = tmpbuffer[i]
        bitsel = Int32(0xFFFF)
        samples[2*i - 1] = (x >>>  0) & bitsel
        samples[2*i - 0] = (x >>> 16) & bitsel
    end
    nothing
end


read_mawvalues!(io::IO, mawvalues::Vector{Int32}, nmawvalues::Int) = begin
    resize!(mawvalues, nmawvalues)
    read!(io, mawvalues)
    _ltoh!(mawvalues)
    nothing
end


read(io::IO, ::Type{RawChEvent}, nmawvalues::Int, firmware_type::FirmwareType, tmpbuffer::Vector{Int32} = Vector{Int32}()) = begin
    # TODO: Add support for averaging value data format

    hdr1 = ltoh(read(io, UInt32))
    hdr2 = ltoh(read(io, UInt32))

    chid = Int32(evt_data_hdr1.ch_id(hdr1))

    ts_high = evt_data_hdr1.timestamp_high(hdr1)
    ts_low = evt_data_hdr2.timestamp_low(hdr2)
    timestamp = Int((UInt(ts_high) << 32) | (UInt(ts_low) << 0))

    evtFlags::Union{Nothing, EvtFlags} = nothing
    accsums::Vector{Int32} = Vector{Int32}()
    peak_height::Union{Nothing, PSAValue} = nothing
    trig_maw::Union{Nothing, MAWValues} = nothing
    energy::Union{Nothing, EnergyValues} = nothing


    if evt_data_hdr1.have_ph_acc16(hdr1)
        ph_word = ltoh(read(io, UInt32))
        acc1_word = ltoh(read(io, UInt32))
        acc2_word = ltoh(read(io, UInt32))
        acc3_word = ltoh(read(io, UInt32))
        acc4_word = ltoh(read(io, UInt32))
        acc5_word = ltoh(read(io, UInt32))
        acc6_word = ltoh(read(io, UInt32))

        peak_height = PSAValue(
            Int32(evt_data_peak_height.peak_heigh_idx(ph_word)),
            Int32(evt_data_peak_height.peak_heigh_val(ph_word))
        ) 

        evtFlags = EvtFlags(
            evt_data_acc_sum_g1.overflow_flag(acc1_word),
            evt_data_acc_sum_g1.underflow_flag(acc1_word),
            evt_data_acc_sum_g1.repileup_flag(acc1_word),
            evt_data_acc_sum_g1.pileup_flag(acc1_word)
        ) 

        resize!(accsums, 6)
        accsums[1] = Int32(evt_data_acc_sum_g1.acc_sum_g1(acc1_word))
        accsums[2] = Int32(evt_data_acc_sum.acc_sum(acc2_word))
        accsums[3] = Int32(evt_data_acc_sum.acc_sum(acc3_word))
        accsums[4] = Int32(evt_data_acc_sum.acc_sum(acc4_word))
        accsums[5] = Int32(evt_data_acc_sum.acc_sum(acc5_word))
        accsums[6] = Int32(evt_data_acc_sum.acc_sum(acc6_word))
    end


    if evt_data_hdr1.have_acc_78(hdr1)
        acc7_word = ltoh(read(io, UInt32))
        acc8_word = ltoh(read(io, UInt32))

        oldlen = length(accsums)
        resize!(accsums, 8)
        fill!(sub(accsums, (oldlen+1):6), 0)
        accsums[7] = Int32(evt_data_acc_sum.acc_sum(acc7_word))
        accsums[8] = Int32(evt_data_acc_sum.acc_sum(acc8_word))
    end


    if evt_data_hdr1.have_ft_maw(hdr1)
        maw_max_word = ltoh(read(io, UInt32))
        maw_pretrig_word = ltoh(read(io, UInt32))
        maw_posttrig_word = ltoh(read(io, UInt32))

        trig_maw = MAWValues(
            Int32(evt_data_maw_value.maw_val(maw_max_word)),
            Int32(evt_data_maw_value.maw_val(maw_pretrig_word)),
            Int32(evt_data_maw_value.maw_val(maw_posttrig_word))
        )
    end


    if evt_data_hdr1.have_energy(hdr1)
        start_energy_word = ltoh(read(io, UInt32)) % Int32
        max_energy_word = ltoh(read(io, UInt32)) % Int32

        energy = EnergyValues(
            Int32(start_energy_word),
            Int32(max_energy_word)
        ) 
    end


    samples_hdr_word = ltoh(read(io, UInt32))

    @assert evt_samples_hdr.const_tag(samples_hdr_word) == 0xE
    mawTestFlag = evt_samples_hdr.maw_test_flag(samples_hdr_word)
    pileup_flag = evt_samples_hdr.any_pileup_flag(samples_hdr_word)
    nsamplewords = Int(evt_samples_hdr.n_sample_words(samples_hdr_word))

    # evtFlags foreach { flags => require( pileup_flag == (flags.pileup || flags.repileup) ) }

    samples = Vector{Int32}()
    read_samples!(io, samples, nsamplewords, tmpbuffer)

    mawvalues = Vector{Int32}()
    if mawTestFlag
        @assert nmawvalues % 2 == 0
        read_mawvalues!(io, mawvalues, nmawvalues)
    end

    RawChEvent(
        chid,
        firmware_type,
        timestamp,
        evtFlags,
        accsums,
        peak_height,
        trig_maw,
        energy,
        pileup_flag,
        samples,
        mawvalues
    )
end



struct FileBuffer
    info::BankChannelHeaderInfo
    events::Vector{RawChEvent}
end


read(io::IO, ::Type{FileBuffer}, tmpevtdata::Vector{UInt8} = Vector{UInt8}()) = begin
    tmpbuffer = Vector{Int32}()

    info = read(io, StruckVMEDevices.BankChannelHeaderInfo)
    events = Vector{StruckVMEDevices.RawChEvent}()
    sizehint!(events, info.nevents)

    resize!(tmpevtdata, sizeof(UInt32) * info.nevents * info.nwords_per_event)
    read!(io, tmpevtdata)
    evtdatabuf = IOBuffer(tmpevtdata)

    for i in 1:info.nevents
        push!(events, read(evtdatabuf, StruckVMEDevices.RawChEvent, info.nmawvalues, info.firmware_type, tmpbuffer))
    end

    FileBuffer(info, events)
end


eachchunk(input::IO, ::Type{UnsortedEvents}) = begin
    output = Channel{UnsortedEvents}(1)

    # @schedule begin # v0.6
    @async begin
        buffers = UnsortedEvents()
        tmpevtdata = Vector{UInt8}()

        bufcount = 0
        while !eof(input)
            buffer = read(input, StruckVMEDevices.FileBuffer, tmpevtdata)
            bufcount += 1
            ch = buffer.info.channel
            events = buffer.events
            if ch in keys(buffers)
                put!(output, buffers)
                buffers = UnsortedEvents()
            end

            buffers[ch] = events
        end
        !isempty(buffers) && put!(output, buffers)
        close(output)
    end

    output
end
