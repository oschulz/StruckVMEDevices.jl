# This file is a part of SIS3316.jl, licensed under the MIT License (MIT).

import Compat.Test
Test.@testset "Package SIS3316" begin
    include("io.jl")
    include("iter_view.jl")
    include("evtformat.jl")
    include("sortevents.jl")
    include("filters.jl")
end
