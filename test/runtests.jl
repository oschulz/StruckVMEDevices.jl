# This file is a part of SIS3316.jl, licensed under the MIT License (MIT).

import Compat.Test
Test.@testset "Package SIS3316" begin
	include("../src/evtformat.jl")
	include("../src/sortevents.jl")
	include("../src/filters.jl")
end
