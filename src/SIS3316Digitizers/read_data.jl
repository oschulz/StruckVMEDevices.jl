# This file is a part of StruckVMEDevices.jl, licensed under the MIT License (MIT).


function read_data(input::IO; nbuffers = typemax(Int))
    daqevtno = Vector{Int32}()
    bufferno = Vector{Int32}()
    channel = Vector{Int32}()
    timestamp = Vector{Int64}()
    energy = Vector{Int32}()
    trigmax = Vector{Int32}()
    samples = VectorOfVectors{UInt32}()

    tmpbuffer = Vector{Int32}()
    tmpevtdata = Vector{UInt8}()

    evtno = 0
    nbufread = 0

    while !eof(input) && nbufread < nbuffers
        bufinfo = read(input, BankChannelHeaderInfo)
        nbufread += 1
        bufno = bufinfo.bufferno

        resize!(tmpevtdata, sizeof(UInt32) * bufinfo.nevents * bufinfo.nwords_per_event)
        read!(input, tmpevtdata)
        evtdatabuf = IOBuffer(tmpevtdata)

        for i in 1:bufinfo.nevents
            evtno += 1
            evt = read(evtdatabuf, RawChEvent, bufinfo.nmawvalues, bufinfo.firmware_type, tmpbuffer)

            push!(daqevtno, evtno)
            push!(channel, evt.chid + 1)
            push!(bufferno, bufno)
            push!(timestamp, evt.timestamp)
            push!(energy, isnothing(evt.energy) ? Int32(0) : evt.energy.maximum)
            push!(trigmax, isnothing(evt.trig_maw) ? Int32(0) : evt.trig_maw.maximum)
            push!(samples, evt.samples)
        end
        # info("Read buffer $bufno, channel $chno with $(length(buffer.events)) events")
    end
    # info("Read $nbufread buffers * channels")

    (
        daqevtno = daqevtno,
        bufferno = bufferno,
        channel = channel,
        timestamp = timestamp,
        energy = energy,
        trigmax = trigmax,
        samples = samples,
    )
end
