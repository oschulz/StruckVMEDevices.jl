# This file is a part of SIS3316.jl, licensed under the MIT License (MIT).

import Base: read, write


immutable BigEndianIO{IOType <: IO}
    io::IOType
end

write(s::BigEndianIO, x::Integer) =
    write(s.io, bswap(x))

read{T <: Integer}(s::BigEndianIO, ::Type{T}) =
    bswap(read(s.io, T))
