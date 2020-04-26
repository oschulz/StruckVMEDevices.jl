# This file is a part of StruckVMEDevices.jl, licensed under the MIT License (MIT).

export ediff, ediff!
export eintegrate, eintegrate!


ediff!(dest::AbstractVector{T}, src::AbstractVector{U}, initial::U = zero(U)) where {T <: Number, U <: Number} = begin
    length(dest) != length(src) && throw(BoundsError())
    last = initial
    @inbounds for i in eachindex(dest)
        current = src[i]
        dest[i] = current - last
        last = current
    end
    dest
end

ediff!(v::AbstractVector{T}, initial::T = zero(T)) where {T <: Number} =
    ediff!(v, v, initial)

ediff(v::AbstractVector{T}, initial::T = zero(T)) where {T <: Number} =
    ediff!(Vector{T}(length(v)), v, initial)


eintegrate!(dest::AbstractVector{T}, src::AbstractVector{U}, initial::U = zero(U)) where {T <: Number, U <: Number} = begin
    length(dest) != length(src) && throw(BoundsError())
    total = initial
    @inbounds for i in eachindex(dest)
        total += src[i]
        dest[i] = total
    end
    dest
end

eintegrate!(v::AbstractVector{T}, initial::T = zero(T)) where {T <: Number} =
    eintegrate!(v, v, initial)

eintegrate(v::AbstractVector{T}, initial::T = zero(T)) where {T <: Number} =
    eintegrate!(Vector{T}(length(v)), v, initial)
