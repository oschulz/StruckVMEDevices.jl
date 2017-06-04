# This file is a part of SIS3316.jl, licensed under the MIT License (MIT).

@Base.Test.testset "Package SIS3316" begin
    include.([
        "io.jl",
        "iter_view.jl",
        "evtformat.jl",
        "sortevents.jl",
        "filters.jl",
    ])
end
