# This file is a part of SIS3316.jl, licensed under the MIT License (MIT).

import Base: isempty, shift!, start, next, done


type IterView{Iterable, State}
    iter::Iterable
    state::State
end

IterView(iter) = IterView(iter, start(iter))


isempty(it::IterView) = done(it.iter, it.state)


shift!(it::IterView) = begin
    const result, state = next(it.iter, it.state)
    it.state = state
    result
end


start(it::IterView) = it.state


next{Iterable, State}(it::IterView{Iterable, State}, state::State) =
    next(it.iter, state)


done{Iterable, State}(it::IterView{Iterable, State}, state::State) =
    done(it.iter, state)
