# This file is a part of SIS3316.jl, licensed under the MIT License (MIT).

import Base.read, Base.write

export eachchunk


module RegisterBits
    using BitManip

    import Base.call
    export RegBit, RegBits

    immutable RegBit
        bit::Int
    end

    call(regbit::RegBit, x::Integer) = bget(x, regbit.bit)


    immutable RegBits
        bits::UnitRange{Int64}
    end

    call(regbits::RegBits, x::Integer) = bget(x, regbits.bits)
end



module EventFormat
    export evt_data_hdr1
    module evt_data_hdr1
        using SIS3316.RegisterBits
        const timestamp_high    = RegBits(16:31)  # Timestamp, high bits
        const ch_id             = RegBits( 4:15)  # Channel ID
        const have_energy       = RegBit(3)  # Event contains Start Energy MAW value and Max. Energy MAW value
        const have_ft_maw       = RegBit(2)  # Event contains 3 x Fast Trigger MAW values (max value, value before Trigger, value with Trigger)
        const have_acc_78       = RegBit(1)  # Event contains 2 x Accumulator values (Gates 7,8)
        const have_ph_acc16     = RegBit(0)  # Event contains Peak High values and 6 x Accumulator values (Gates 1,2, ..,6)
    end

    export evt_data_hdr2
    module evt_data_hdr2
        using SIS3316.RegisterBits
        const timestamp_low     = RegBits(0:31)  # Timestamp, low bits
    end

    export evt_data_peak_height
    module evt_data_peak_height
        using SIS3316.RegisterBits
        const peak_heigh_idx    = RegBits(16:31)  # Index of Peakhigh value
        const peak_heigh_val    = RegBits( 0:15)  # Peakhigh value
    end

    export evt_data_acc_sum_g1
    module evt_data_acc_sum_g1
        using SIS3316.RegisterBits
        const overflow_flag     = RegBit(24 + 7)  # Overflow flag
        const underflow_flag    = RegBit(24 + 6)  # Underflow flag
        const repileup_flag     = RegBit(24 + 5)  # RePileup flag
        const pileup_flag       = RegBit(24 + 4)  # Pileup flag
        const acc_sum_g1        = RegBits(0:23)  # Accumulator sum of Gate 1
    end

    export evt_data_acc_sum
    module evt_data_acc_sum
        using SIS3316.RegisterBits
        const acc_sum           = RegBits(0:27)  # Accumulator sum of Gate (for Gates 2 to 8)
    end

    export evt_data_maw_value
    module evt_data_maw_value
        using SIS3316.RegisterBits
        # Note: Documentation says bit 0..27, but for some reason bit 27 seems
        # to (always?) be set:
        const maw_val           = RegBits(0:26)  # MAW value (maximum or value before or after trigger)
    end

    export evt_samples_hdr
    module evt_samples_hdr
        using SIS3316.RegisterBits
        const const_tag         = RegBits(28:31)  # Always 0xE
        const maw_test_flag     = RegBit(27)  # MAW Test Flag
        const any_pileup_flag   = RegBit(26)  # RePileup or Pileup Flag
        const n_sample_words    = RegBits(0:25) # number of raw samples (x 2 samples, 32-bit words)
    end
end

using SIS3316.EventFormat



const multievt_buf_header = UInt32(0xdeadbeef)

@enum FirmwareType FW250=0 FW125=1


immutable BankChannelHeaderInfo
    firmware_type::FirmwareType
    bufferno::Int
    channel::Int
    nevents::Int
    nwords_per_event::Int
    nmawvalues::Int
    reserved::Int
end


read(io::IO, ::Type{BankChannelHeaderInfo}) = begin
    assert(read(io, UInt32) == multievt_buf_header)
    BankChannelHeaderInfo(
        FirmwareType(read(io, UInt32)),
        Int(read(io, UInt32)),
        Int(read(io, UInt32)) + 1,
        Int(read(io, UInt32)),
        Int(read(io, UInt32)),
        Int(read(io, UInt32)),
        Int(read(io, UInt32)),
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


immutable EvtFlags
    overflow::Bool
    underflow::Bool
    repileup::Bool
    pileup::Bool
end


immutable PSAValue
    index::Int32
    value::Int32
end


immutable MAWValues
    maximum::Int32
    preTrig::Int32
    postTrig::Int32
end


immutable EnergyValues
    initial::Int32
    maximum::Int32
end


immutable RawChEvent
  chid::Int32
  timestamp::Int
  flags::Nullable{EvtFlags}
  accsums::Vector{Int32}
  peak_height::Nullable{PSAValue}
  trig_maw::Nullable{MAWValues}
  energy::Nullable{EnergyValues}
  pileup_flag::Bool
  samples::Vector{Int32}
  mawvalues::Vector{Int32}
end


typealias UnsortedEvents Dict{Int, Vector{SIS3316.RawChEvent}}
typealias SortedEvents Vector{Dict{Int, RawChEvent}}



read_samples!(io::IO, samples::Vector{Int32}, nsamplewords::Int, tmpbuffer::Vector{Int32}) = begin
    resize!(tmpbuffer, nsamplewords)
    const tmpsamples = reinterpret(UInt16, tmpbuffer)
    read!(io, tmpsamples)
    resize!(samples, length(tmpsamples))
    copy!(samples, tmpsamples)
    nothing
end


read_mawvalues!(io::IO, mawvalues::Vector{Int32}, nmawvalues::Int) = begin
    resize!(mawvalues, nmawvalues)
    read(io, mawvalues)
    nothing
end


read(io::IO, ::Type{RawChEvent}, nmawvalues::Int, tmpbuffer::Vector{Int32} = Vector{Int32}()) = begin
    # TODO: Add support for averaging value data format

    const hdr1 = read(io, UInt32)
    const hdr2 = read(io, UInt32)

    const chid = Int32(evt_data_hdr1.ch_id(hdr1))

    const ts_high = evt_data_hdr1.timestamp_high(hdr1)
    const ts_low = evt_data_hdr2.timestamp_low(hdr2)
    const timestamp = Int((UInt(ts_high) << 32) | (UInt(ts_low) << 0))

    local evtFlags = Nullable{EvtFlags}()
    local accsums = Vector{Int32}()
    local peak_height = Nullable{PSAValue}()
    local trig_maw = Nullable{MAWValues}()
    local energy = Nullable{EnergyValues}()


    if evt_data_hdr1.have_ph_acc16(hdr1)
        const ph_word = read(io, UInt32)
        const acc1_word = read(io, UInt32)
        const acc2_word = read(io, UInt32)
        const acc3_word = read(io, UInt32)
        const acc4_word = read(io, UInt32)
        const acc5_word = read(io, UInt32)
        const acc6_word = read(io, UInt32)

        peak_height = Nullable( PSAValue(
            Int32(evt_data_peak_height.peak_heigh_idx(ph_word)),
            Int32(evt_data_peak_height.peak_heigh_val(ph_word))
        ) )

        evtFlags = Nullable( EvtFlags(
            evt_data_acc_sum_g1.overflow_flag(acc1_word),
            evt_data_acc_sum_g1.underflow_flag(acc1_word),
            evt_data_acc_sum_g1.repileup_flag(acc1_word),
            evt_data_acc_sum_g1.pileup_flag(acc1_word)
        ) )

        resize!(accsums, 6)
        accsums[1] = Int32(evt_data_acc_sum_g1.acc_sum_g1(acc1_word))
        accsums[2] = Int32(evt_data_acc_sum.acc_sum(acc2_word))
        accsums[3] = Int32(evt_data_acc_sum.acc_sum(acc3_word))
        accsums[4] = Int32(evt_data_acc_sum.acc_sum(acc4_word))
        accsums[5] = Int32(evt_data_acc_sum.acc_sum(acc5_word))
        accsums[6] = Int32(evt_data_acc_sum.acc_sum(acc6_word))
    end


    if evt_data_hdr1.have_acc_78(hdr1)
        const acc7_word = read(io, UInt32)
        const acc8_word = read(io, UInt32)

        const oldlen = length(accsums)
        resize!(accsums, 8)
        fill!(sub(accsums, (oldlen+1):6), 0)
        accsums[7] = Int32(evt_data_acc_sum.acc_sum(acc7_word))
        accsums[8] = Int32(evt_data_acc_sum.acc_sum(acc8_word))
    end


    if evt_data_hdr1.have_ft_maw(hdr1)
        const maw_max_word = read(io, UInt32)
        const maw_pretrig_word = read(io, UInt32)
        const maw_posttrig_word = read(io, UInt32)

        trig_maw = Nullable( MAWValues(
            Int32(evt_data_maw_value.maw_val(maw_max_word)),
            Int32(evt_data_maw_value.maw_val(maw_pretrig_word)),
            Int32(evt_data_maw_value.maw_val(maw_posttrig_word))
        ) )
    end


    if evt_data_hdr1.have_energy(hdr1)
        const start_energy_word = read(io, UInt32) % Int32
        const max_energy_word = read(io, UInt32) % Int32

        energy = Nullable( EnergyValues(
            Int32(start_energy_word),
            Int32(max_energy_word)
        ) )
    end


    const samples_hdr_word = read(io, UInt32)

    assert(evt_samples_hdr.const_tag(samples_hdr_word) == 0xE)
    const mawTestFlag = evt_samples_hdr.maw_test_flag(samples_hdr_word)
    const pileup_flag = evt_samples_hdr.any_pileup_flag(samples_hdr_word)
    const nsamplewords = Int(evt_samples_hdr.n_sample_words(samples_hdr_word))

    # evtFlags foreach { flags => require( pileup_flag == (flags.pileup || flags.repileup) ) }

    local samples = Vector{Int32}()
    read_samples!(io, samples, nsamplewords, tmpbuffer)

    local mawvalues = Vector{Int32}()
    if mawTestFlag
        assert(nmawvalues % 2 == 0)
        read_mawvalues!(io, mawvalues, nmawvalues)
    end

    RawChEvent(
        chid,
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



immutable FileBuffer
    info::BankChannelHeaderInfo
    events::Vector{RawChEvent}
end


read(io::IO, ::Type{FileBuffer}, tmpevtdata::Vector{UInt8} = Vector{UInt8}()) = begin
    const tmpbuffer = Vector{Int32}()

    info = read(io, SIS3316.BankChannelHeaderInfo)
    events = Vector{SIS3316.RawChEvent}()
    sizehint!(events, info.nevents)

    resize!(tmpevtdata, sizeof(UInt32) * info.nevents * info.nwords_per_event)
    read!(io, tmpevtdata)
    const evtdatabuf = IOBuffer(tmpevtdata)

    for i in 1:info.nevents
        push!(events, read(evtdatabuf, SIS3316.RawChEvent, info.nmawvalues, tmpbuffer))
    end

    FileBuffer(info, events)
end


eachchunk(input::IO, ::Type{UnsortedEvents}) = @task begin
    local buffers = UnsortedEvents()
    local tmpevtdata = Vector{UInt8}()

    local bufcount = 0
    while !eof(input)
        const buffer = read(input, SIS3316.FileBuffer, tmpevtdata)
        bufcount += 1
        const ch = buffer.info.channel
        const events = buffer.events
        if ch in keys(buffers)
            produce(buffers)
            empty!(buffers)
        end

        buffers[ch] = events
    end
    !isempty(buffers) && produce(buffers)
end
