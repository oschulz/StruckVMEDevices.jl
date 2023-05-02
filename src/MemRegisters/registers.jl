# This file is a part of SIS3316Digitizers.jl, licensed under the MIT License (MIT).

using BitOperations
using StructArrays, ArraysOfArrays
using Tables, TypedTables


function getraw() end
export getraw

function setraw() end
function setraw!() end
export setraw, setraw!

function getval() end
export getval

function setval() end
function setval!() end
export setval, setval!

function getaccessmode() end
export getaccessmode

function getlayout() end
export getlayout

function getaddress() end
export getaddress


abstract type AccessMode end
abstract type RO <: AccessMode end
abstract type WO <: AccessMode end
abstract type RW <: AccessMode end
const Readable = Union{RO,RW}
const Writeable = Union{WO,RW}
export AccessMode, RO, WO, RW, Readable, Writeable

abstract type JKRW <: RW end
abstract type GranularRW <: RW end
export JKRW, GranularRW


abstract type BitSemantics end
export BitSemantics

function bits_to_val() end
function val_to_bits() end
export bits_to_val, val_to_bits


struct LiteralBits <: BitSemantics end
export LiteralBits

@inline bits_to_val(b::Union{Bool,Unsigned}, semantics::LiteralBits) = b
@inline val_to_bits(v::Union{Bool,Unsigned}, semantics::LiteralBits) = v


struct TransformedBits{F<:Function,FInv<:Function} <: BitSemantics
    from_bits::F
    to_bits::FInv
end
export TransformedBits

@inline bits_to_val(b::Union{Bool,Unsigned}, semantics::TransformedBits) = semantics.from_bits(b)
@inline val_to_bits(v, semantics::TransformedBits) = semantics.to_bits(v)


struct EnumBits{E<:Enum} <: BitSemantics end
export EnumBits

@inline EnumBits(::Type{E}) where {E<:Enum} = EnumBits{E}()

@inline bits_to_val(b::Union{Bool,Unsigned}, semantics::EnumBits{E}) where E = E(b)
@inline val_to_bits(v, semantics::EnumBits) = Integer(v)


abstract type BitSelection{Acc<:AccessMode} end
export BitSelection

getval(x::Unsigned, bsel::BitSelection{<:Readable}) =
    bits_to_val(getraw(x, bsel), bsel.semantics)

setval(x::Unsigned, bsel::BitSelection{<:Writeable}, v) =
    setraw(x, bsel, val_to_bits(v, bsel.semantics))

@inline getaccessmode(reg::BitSelection{Acc}) where Acc = Acc


struct Bit{Acc<:AccessMode,i,S<:BitSemantics} <: BitSelection{Acc}
    i::Val{i}
    semantics::S
end
export Bit


@inline Bit{Acc}(i::Integer, semantics::BitSemantics = LiteralBits()) where {Acc<:AccessMode} =
    Bit{Acc,convert(Int, i),typeof(semantics)}(Val(convert(Int, i)), semantics)

Base.show(io::IO, bit::Bit{Acc,i}) where {Acc,i} = print(io, "Bit{$Acc}($i, $(repr(bit.semantics)))")

Base.show(io::IO, bit::Bit{Acc,i,LiteralBits}) where {Acc,i} = print(io, "Bit{$Acc}($i)")

@inline Bit{Acc}(i::Integer, ::Type{E}) where {Acc<:AccessMode,E<:Enum} =
    Bit{Acc}(i, EnumBits(E))

Base.show(io::IO, bit::Bit{Acc,i,EnumBits{E}}) where {Acc,i,E} = print(io, "Bit{$Acc}($i, $E)")

@inline Bit{Acc}(i::Integer, trafo::Tuple{Function,Function}) where {Acc<:AccessMode} =
    Bit{Acc}(i, TransformedBits(trafo[1], trafo[2]))

Base.show(io::IO, bit::Bit{Acc,i,<:TransformedBits}) where {Acc,i} = print(io, "Bit{$Acc}($i, $((bit.semantics.from_bits, bit.semantics.to_bits)))")

@inline Base.:<<(bit::Bit{Acc,i}, n::Integer) where {Acc,i} = Bit{Acc}(i + n, bit.semantics)

@inline BitOperations.bmask(::Type{T}, bit::Bit{Acc,i}) where {T<:Unsigned,Acc,i} = bmask(T, i)

@inline getraw(x::Unsigned, bit::Bit{<:Readable, i}) where i = bget(x, i)

@inline setraw(x::Unsigned, bit::Bit{<:Writeable, i}, v::Bool) where i = bset(x, i, v)



struct BitRange{Acc<:AccessMode,r,S<:BitSemantics} <: BitSelection{Acc}
    r::Val{r}
    semantics::S
end
export BitRange

@inline BitRange{Acc}(r::UnitRange{<:Integer}, semantics::BitSemantics = LiteralBits()) where {Acc<:AccessMode} =
    BitRange{Acc,convert(UnitRange{Int}, r),typeof(semantics)}(Val(convert(UnitRange{Int}, r)), semantics)

Base.show(io::IO, bits::BitRange{Acc,r}) where {Acc,r} = print(io, "BitRange{$Acc}($r, $(repr(bits.semantics)))")

Base.show(io::IO, bits::BitRange{Acc,r,LiteralBits}) where {Acc,r} =
    print(io, "BitRange($r)")

@inline BitRange{Acc}(r::UnitRange{<:Integer}, ::Type{E}) where {Acc<:AccessMode,E<:Enum} =
    BitRange{Acc}(r, EnumBits(E))

Base.show(io::IO, bits::BitRange{Acc,r,EnumBits{E}}) where {Acc,r,E} = print(io, "BitRange{$Acc}($r, $E)")

@inline BitRange{Acc}(r::UnitRange{<:Integer}, trafo::Tuple{Function,Function}) where {Acc<:AccessMode} =
    BitRange{Acc}(r, TransformedBits(trafo[1], trafo[2]))

Base.show(io::IO, bits::BitRange{Acc,r,<:TransformedBits}) where {Acc,r} =
    print(io, "BitRange{$Acc}($r, $((bits.semantics.from_bits, bits.semantics.to_bits)))")

@inline _shift_br_range(r::AbstractUnitRange{<:Integer}, n::Integer) = (first(r) + n):(last(r) + n)

@inline Base.:<<(bit::BitRange{Acc,r}, n::Integer) where {Acc,r} = BitRange{Acc}(_shift_br_range(r, n), bit.semantics)

@inline BitOperations.bmask(::Type{T}, bits::BitRange{Acc,r}) where {T<:Unsigned,Acc,r} = bmask(T, r)

@inline getraw(x::Unsigned, bits::BitRange{<:Readable, r}) where r = bget(x, r)

@inline setraw(x::Unsigned, bits::BitRange{<:Writeable, r}, v::Unsigned) where r = bset(x, r, v)



struct BitWriteOperation{T<:Unsigned}
    value::T
    bitmask::T
    isjk::Bool
end

export BitWriteOperation

BitWriteOperation{T}(::Type{<:Writeable}) where {T<:Unsigned} = BitWriteOperation{T}(zero(T), zero(T), false)
BitWriteOperation{T}(::Type{<:JKRW}) where {T<:Unsigned} = BitWriteOperation{T}(zero(T), zero(T), true)

is_masked(op::BitWriteOperation{T}) where T = (op.bitmask != ~zero(T))
export is_masked


@inline function BitOperations.bset(x::T, op::BitWriteOperation{T}) where T
    bm = op.bitmask
    y = op.value
    (x & ~bm) | (y & bm)
end

@inline function setraw(op::BitWriteOperation{T}, bsel::BitSelection{<:Writeable}, v::Union{Unsigned,Bool}) where T
    @argcheck op.isjk == false
    mod_value = setraw(op.value, bsel, v)
    mod_bitmask = op.bitmask | bmask(T, bsel)
    BitWriteOperation{T}(mod_value, mod_bitmask, op.isjk)
end

@inline function setraw(op::BitWriteOperation{T}, bsel::BitSelection{<:JKRW}, v::Union{Unsigned,Bool}) where T
    @argcheck op.isjk == true
    op.value == op.bitmask == zero(T) || op.bitmask == ~zero(T) || throw(ArgumentError("Can't add a JK bit write to a non-empty BitWriteOperation with partial bitmask"))
    n_shift = 4 * sizeof(T)
    to_set = setraw(zero(T), bsel, v) << n_shift >>> n_shift
    to_clear = setraw(zero(T), bsel, ~v) << n_shift
    mod_value = op.value | to_set | to_clear
    BitWriteOperation{T}(mod_value, ~zero(T), op.isjk)
end

@inline function setval(op::BitWriteOperation{T}, bsel::BitSelection{<:Writeable}, v) where T
    setraw(op, bsel, val_to_bits(v, bsel.semantics))
end


@inline Base.merge(a::BitWriteOperation) = a

@inline function Base.merge(a::BitWriteOperation{T}, b::BitWriteOperation{T}, cs::BitWriteOperation{T}...) where T
    @argcheck a.isjk == b.isjk
    if !b.isjk
        mod_value = (a.value & ~b.bitmask) | (b.value & b.bitmask) 
        mod_bitmask = a.bitmask | b.bitmask
        merge(BitWriteOperation(mod_value, mod_bitmask, false), cs...)
    else
        @argcheck a.bitmask == b.bitmask == ~zero(T)
        shft = 4 * sizeof(T)
        msk = ~((b.value >> shft) | (b.value << shft))
        mod_value = a.value & msk | b.value
        merge(BitWriteOperation(mod_value, ~zero(T), true), cs...)
    end
end



const NamedBits{N} = NamedTuple{names, <:NTuple{N,BitSelection}} where names
export NamedBits


getraw(x::Unsigned, nb::NamedBits) = map(bsel -> getraw(x, bsel), nb)

getval(x::Unsigned, nb::NamedBits) = map(bsel -> getval(x, bsel), nb)


Base.@pure _nt_names(x::NamedTuple{names}) where names = map(Val, names)
@inline _nt_getproperty(x::NamedTuple, ::Val{name}) where name = getproperty(x, name)

function setval(op::BitWriteOperation{T}, nb::NamedBits, v::NamedTuple) where T
    writes = map(_nt_names(v)) do name
        bsel = _nt_getproperty(nb, name)
        value = _nt_getproperty(v, name)
        setval(BitWriteOperation{T}(zero(T), zero(T), op.isjk), bsel, value)
    end
    merge(writes...)
end


@inline function Base.filter(::Type{Acc}, nbits::NamedBits) where {Acc<:AccessMode}
    if @generated
        Acc, nbits
        idxs = findall(T -> T <: BitSelection{<:Acc}, fieldtypes(nbits))
        names = fieldnames(nbits)[idxs]
        vals = Any[ :(getfield(nbits, $(QuoteNode(n)))) for n in names ]
        :( NamedTuple{$names}(($(vals...),)) )
    else
        (;filter(x -> x[2] isa BitSelection{<:Acc}, (pairs(nbits)...,))...)
    end
end



struct BitGroup{
    Acc<:AccessMode,
    NB<:NamedBits
} <: BitSelection{Acc}
    _layout::NB
end
export BitGroup


@inline BitGroup{Acc}(layout::NB) where {Acc<:AccessMode,NB<:NamedBits} = BitGroup{Acc,NB}(layout)

@inline BitGroup{Acc}(;named_bits...) where {Acc<:AccessMode} = BitGroup{Acc}(values(named_bits))


@inline getlayout(grp::BitGroup) = getfield(grp, :_layout)
@inline getaccessmode(reg::BitGroup{Acc}) where Acc = Acc


@inline function Base.getproperty(grp::BitGroup, p::Symbol)
    # May need to include internal fields of BitGroup to make Zygote happy:
    if p == :_layout
        getfield(grp, :_layout)
    else
        getproperty(getlayout(grp), p)
    end
end

@inline function Base.propertynames(grp::BitGroup, private::Bool = false)
    names = propertynames(getlayout(grp))
    private ? (names..., :_layout) : names
end

Base.merge(a::NamedTuple, grp::BitGroup{names}) where {names} = merge(a, getlayout(grp))


@inline Base.keys(grp::BitGroup) = keys(getlayout(grp))
@inline Base.values(grp::BitGroup) = values(getlayout(grp))

@inline Base.getindex(grp::BitGroup, name::Symbol) = getproperty(grp, name)
@inline Base.getindex(grp::BitGroup, i::Integer) = getlayout(grp)[i]


Base.show(io::IO, grp::BitGroup{Acc}) where {Acc} = print(io, "BitGroup{$Acc}($(repr(getlayout(grp))))")

function Base.show(io::IO, ::MIME"text/plain", grp::BitGroup{Acc}) where {Acc}
    println(io, "BitGroup{$Acc}(")
    for (k, v) in pairs(getlayout(grp))
        print("    ")
        print("$k = ")
        show(io, v)
        println(",")
    end
    print(io, ")")
end


@inline Base.:<<(grp::BitGroup{Acc}, n::Integer) where {Acc} =
    BitGroup{Acc}(map(bsel -> bsel << n, getlayout(grp)))


@inline BitOperations.bmask(::Type{T}, bsel::BitGroup) where {T<:Unsigned} =
    |(map(bsel -> bmask(T, bsel), values(bsel))...)

# ToDo:
# @inline getraw(x::Unsigned, bsel::BitGroup{<:Readable, r}) where r = bget(x, r)

# ToDo:
# @inline setraw(x::Unsigned, bsel::BitGroup{<:Writeable, r}, v::Unsigned) where r = bset(x, r, v)

getval(x::Unsigned, bsel::BitGroup{<:Readable}) = getval(x, getlayout(bsel))

# ToDo:
# setval(x::Unsigned, bsel::BitGroup{<:Writeable}, v) = ...



struct Register{Acc<:AccessMode,Addr<:Unsigned,T<:Unsigned,NB<:NamedBits}
    _address::Addr
    _layout::NB
end
export Register

Register{Acc,T}(address::Addr,layout::NB) where {Acc<:AccessMode,Addr<:Unsigned,T<:Unsigned,NB<:NamedBits} =
    Register{Acc,Addr,T,NB}(address, layout)

@inline getaddress(reg::Register) = getfield(reg, :_address)
@inline getlayout(reg::Register) = getfield(reg, :_layout)
@inline getaccessmode(reg::Register{Acc}) where Acc = Acc


_bitsel_ref(::Type{T}, addr::Addr, bsel::BitSelection) where {T,Addr<:Unsigned} = BitSelRef{T}(addr, bsel)

#!!! TODO: Reconsider - kind of a workaround, may lead to unexpexted results
# if user writes raw bits to returned pseudo-register:
_bitsel_ref(::Type{T}, addr::Addr, bsel::BitGroup{Acc}) where {T,Addr<:Unsigned,Acc} =
    Register{Acc,T}(addr, getlayout(bsel))

@inline function Base.getproperty(reg::Register{Acc,Addr,T}, p::Symbol) where {Acc,Addr,T}
    # May need to include internal fields of Register to make Zygote happy:
    if p == :_address
        getfield(reg, :_address)
    elseif p == :_layout
        getfield(reg, :_layout)
    else
        _bitsel_ref(T, getaddress(reg), getproperty(getlayout(reg), p))
    end
end

@inline function Base.propertynames(reg::Register, private::Bool = false)
    names = propertynames(getlayout(reg))
    if private
        (names..., :_address, :_layout)
    else
        names
    end
end

Base.merge(a::NamedTuple, reg::Register{names}) where {names} = merge(a, getlayout(reg))


@inline Base.keys(reg::Register) = keys(getlayout(reg))

@inline Base.getindex(reg::Register, name::Symbol) = getproperty(reg, name)

@inline Base.getindex(reg::Register{Acc,Addr,T}, i::Integer) where {Acc,Addr,T} =
    _bitsel_ref(T, getaddress(reg), getlayout(reg)[i])

@inline function Base.values(reg::Register{Acc,Addr,T}) where {Acc,Addr,T}
    addr = getaddress(reg)
    map(bsel -> BitSelRef{T}(bsel, addr), values(getlayout(reg)))
end


Base.show(io::IO, reg::Register{Acc,Addr,T}) where {Acc,Addr,T} = print(io, "Register{$Acc,$T}($(repr(getaddress(reg))), $(repr(getlayout(reg))))")

function Base.show(io::IO, ::MIME"text/plain", reg::Register{Acc,Addr,T}) where {Acc,Addr,T}
    println(io, "Register{$Acc,$T}(")
    println(io, "    $(repr(getaddress(reg))),")
    println(io, "    (")
    for (k, v) in pairs(getlayout(reg))
        print("        ")
        print("$k = ")
        show(io, v)
        println(",")
    end
    println(io, "    )")
    print(io, ")")
end


getraw(x::T, reg::Register) where {T} = map(x, filter(Readable, getlayout(reg)))

getval(x::T, reg::Register) where {T} = map(x, filter(Readable, getlayout(reg)))


struct BitSelRef{T<:Unsigned,Addr<:Unsigned,BSel<:BitSelection}
    addr::Addr
    bitsel::BSel
end
export BitSelRef

BitSelRef{T}(addr::Addr, bitsel::BSel) where {T<:Unsigned,Addr<:Unsigned,BSel<:BitSelection} =
    BitSelRef{T,Addr,BSel}(addr, bitsel)

Base.show(io::IO, bitref::BitSelRef{T}) where {T} = print(io, "BitSelRef{$T}($(repr(bitref.bitsel)), $(repr(bitref.addr)))")

getaddress(ref::BitSelRef) = ref.addr
getlayout(ref::BitSelRef) = ref.bitsel
@inline getaccessmode(bitref::BitSelRef) = getaccessmode(bitref.bitsel)
