# This file is a part of SIS3316.jl, licensed under the MIT License (MIT).

export ediff, ediff!
export eintegrate, eintegrate!


ediff!{T <: Number, U <: Number}(dest::AbstractVector{T}, src::AbstractVector{U}, initial::U = zero(U)) = begin
    length(dest) != length(src) && throw(BoundsError())
    local last = initial
    @inbounds for i in eachindex(dest)
        const current = src[i]
        dest[i] = current - last
        last = current
    end
    dest
end

ediff!{T <: Number}(v::AbstractVector{T}, initial::T = zero(T)) =
    ediff!(v, v, initial)

ediff{T <: Number}(v::AbstractVector{T}, initial::T = zero(T)) =
    ediff!(Vector{T}(length(v)), v, initial)


eintegrate!{T <: Number, U <: Number}(dest::AbstractVector{T}, src::AbstractVector{U}, initial::U = zero(U)) = begin
    length(dest) != length(src) && throw(BoundsError())
    local total = initial
    @inbounds for i in eachindex(dest)
        total += src[i]
        dest[i] = total
    end
    dest
end

eintegrate!{T <: Number}(v::AbstractVector{T}, initial::T = zero(T)) =
    eintegrate!(v, v, initial)

eintegrate{T <: Number}(v::AbstractVector{T}, initial::T = zero(T)) =
    eintegrate!(Vector{T}(length(v)), v, initial)
