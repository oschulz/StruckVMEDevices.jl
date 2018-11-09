# This file is a part of SIS3316.jl, licensed under the MIT License (MIT).

import Base: iterate, length


struct IterView{Iterable, State}
    iter::Iterable
    state::State
end

function iterate(it::IterView, state = 1)
	if state > length(it) 
		return nothing
	else
		return ( it.iter[state], state + 1 )
	end
end

function length(it::IterView)
	return length(it.iter)
end

