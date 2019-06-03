# This file is a part of SIS3316Digitizers.jl, licensed under the MIT License (MIT).

export sortevents!, sortevents


sortevents!(sorted::SortedEvents, unsorted::UnsortedEvents; merge_window::AbstractFloat = 100e-9) = begin
    getts(elem::Pair{Int, RawChEvent}) = elem.second.timestamp

    current = Vector{Pair{Int, RawChEvent}}()
    n_channel::Int = 0
    for (ch, events) in unsorted
        if !isempty(events) n_channel += 1 end
        for evt in events
            push!(current, Pair(ch, evt))
        end
    end

    sort!(current, by = getts)

    event_i = 0
    while !isempty(current)
        reftime = time(current[1].second)
        merged = Dict{Int, RawChEvent}()
        n = 0
        event_i += 1
        while n < n_channel && !isempty(current) && (time(first(current).second) - reftime <= merge_window)
            n += 1
            push!(merged, current[1])
            deleteat!(current, 1)
        end
        mc = copy(merged)
        push!(sorted, mc)
    end

    sorted
end


sortevents(unsorted::UnsortedEvents; merge_window::AbstractFloat = 100e-9) =
    sortevents!(SortedEvents(), unsorted, merge_window = merge_window)
