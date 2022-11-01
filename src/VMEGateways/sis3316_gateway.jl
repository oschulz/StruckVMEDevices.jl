# This file is a part of SIS3316Digitizers.jl, licensed under the MIT License (MIT).


const UDPRespBits = (                                        
    req_counter = Bit{RW}(7),       # Request counter, toggles with each request
    prot_error = Bit{RW}(6),        # Protocol error (request command packet error)
    access_timeout = Bit{RW}(5),    # SIS3316 access timeout (fifo empty)
    no_eth_grant = Bit{RW}(4),      # Ethernet interface has no grant
    pkg_counter = BitRange{RW}(0:3),     # Packet counter
)

function check_udp_response_status(status::UInt8)
    getval(status, UDPRespBits.prot_error) && throw(ErrorException("Protocol error bit set in response status"))
    getval(status, UDPRespBits.access_timeout) && throw(ErrorException("Access timeout bit set in response status"))
    getval(status, UDPRespBits.no_eth_grant) && throw(ErrorException("Ethernet interface has no grant set in response status"))
    nothing
end


is_link_interface_register(addr::Integer) = addr < 0x20


function check_vme_datalen_mode(nbytes::Integer, mode::VMEMode)
    if mode == VME_A32_D32_SCT || mode == VME_A32_D32_BLT
        nbytes % sizeof(UInt32) == 0 || throw(ArgumentError("Invalid data size $nbytes for mode $mode"))
    elseif mode == VME_A32_D64_MBLT || mode == VME_A32_D64_2eVME
        nbytes % sizeof(UInt64) == 0 || throw(ArgumentError("Invalid data size $nbytes for mode $mode"))
    else
        throw(ArgumentError("VME mode $mode not supported"))
    end
    nothing
end


"""
    mutable struct SIS3316Gateway <: AbstractVMEGateway

Struck SIS3316 VME Ethernet gateway implementation.

Constructor:

    SIS3316Gateway(host::Union{AbstractString,IPv4}, port::Integer = 0xE000)

Finalizer:

    Base.close(gw::SIS3316Gateway)

Relevant functions:

    * [`read_registers!`](@ref)
    * [`write_registers!`](@ref)
"""
mutable struct SIS3316Gateway <: AbstractVMEGateway
    hostname::String
    ipaddr::IPv4
    port::UInt16
    socket::UDPSocket
    getsocket_lock::ReentrantLock
    socketio_lock::ReentrantLock
    socket_timeout::Atomic{UInt64}
    socket_mon::Channel{Nothing}
    last_pkgid::UInt8
    default_timeout::Float64
end

export SIS3316Gateway


function SIS3316Gateway(hostname::AbstractString, ipaddr::IPv4, port::Integer = 0xE000; default_timeout = 0.5)
    socket = UDPSocket()
    getsocket_lock = ReentrantLock()
    socketio_lock = ReentrantLock()
    socket_timeout = Atomic{UInt64}(0)
    socket_mon = Channel{Nothing}(); close(socket_mon)
    last_pkgid = UInt8(0)

    gw = SIS3316Gateway(
        hostname, ipaddr, port,
        socket, getsocket_lock, socketio_lock, socket_timeout, socket_mon,
        last_pkgid, default_timeout
    )
    gw.socket_mon = socketmon(gw)

    finalizer(x -> close(x), gw)

    check_connection(gw)
    gw
 end

SIS3316Gateway(hostname::AbstractString, port::Integer = 0xE000; default_timeout = 0.5) =
    SIS3316Gateway(hostname, getaddrinfo(hostname, IPv4), port, default_timeout = default_timeout)

SIS3316Gateway(ipaddr::IPv4, port::Integer = 0xE000; default_timeout = 0.5) =
    SIS3316Gateway(getnameinfo(ipaddr), ipaddr, port, default_timeout = default_timeout)


Base.show(io::IO, gw::SIS3316Gateway) = print(io, "SIS3316Gateway($(gw.hostname), $(gw.ipaddr), $(repr(gw.port)))")

Base.deepcopy(gw::SIS3316Gateway) = SIS3316Gateway(gw.hostname, gw.ipaddr, gw.port, default_timeout = gw.default_timeout)


Base.isopen(gw::SIS3316Gateway) = isopen(gw.socket_mon)

function Base.close(gw::SIS3316Gateway)
    if isopen(gw.socket_mon)
        # @info "Closing $gw" # logging causes trouble in finalizers
        lock(gw.socketio_lock) do
            close(gw.socket_mon)
        end
        # Just to make sure:
        lock(gw.socketio_lock) do
            close(getsocket(gw))
        end
        # @info "Closed $gw" # logging causes trouble in finalizers
    end
end


function getsocket(gw::SIS3316Gateway)
    lock(gw.getsocket_lock) do
        gw.socket
    end
end
    

function socketmon(gw::SIS3316Gateway; sleep_interval_ns::Integer = 50 * 10^6)
    Channel{Nothing}(0; taskref = nothing, spawn = true) do ch
        try
            @debug "UDP Socket monitor started"
            while isopen(ch)
                t_ns = time_ns()::UInt64
                timeout = gw.socket_timeout[]
                # Note: timeout == 0 means watchdog disabled
                if timeout != 0 && signed(t_ns - timeout) > 0
                    @info "UDP socket watchdog timeout, opening new UDP Socket"
                    lock(gw.getsocket_lock) do
                        new_socket = UDPSocket()
                        close(gw.socket)
                        gw.socket = new_socket
                        gw.socket_timeout[] = 0
                    end
                end
                sleep(sleep_interval_ns / 10^9)
            end
            @debug "UDP Socket monitor closed and terminating"
        catch err
            @error err
        finally
            close(gw.socket)
        end
    end
end


function timeout_after!(gw::SIS3316Gateway, timeout_s::Real)
    timeout_ns = trunc(UInt64, timeout_s * 10^9)
    timeout_at = time_ns() + timeout_ns
    if timeout_at == 0
        # Note: timeout == 0 means watchdog disabled, so add 1
        timeout_at += 1
    end
    gw.socket_timeout[] = timeout_at
end

function disable_timeout!(gw::SIS3316Gateway)
    # Note: timeout == 0 means watchdog disabled
    gw.socket_timeout[] = 0
end


function Sockets.send(gw::SIS3316Gateway, req::Vector{UInt8})
    socket = getsocket(gw)
    lock(gw.socketio_lock) do
        # @debug "Sending UDP request to $(gw.hostname): $req"
        send(socket, gw.ipaddr, gw.port, req)
    end
end


function Sockets.recv(gw::SIS3316Gateway, len::Missing = missing; timeout::Real = gw.default_timeout)
    socket = getsocket(gw)
    resp_from, resp = lock(gw.socketio_lock) do
        # @debug "Waiting for UDP data from $(gw.hostname)"
        timeout_after!(gw, timeout)
        resp_from, resp = recvfrom(socket)
        disable_timeout!(gw)
        resp_from, resp
    end
    resp_from_expected = Sockets.InetAddr{IPv4}(gw.ipaddr, gw.port)
    resp_from == resp_from_expected || throw(ErrorException("Received UDP data from $resp_from instead from expected $resp_from_expected"))
    # @debug "Received $(length(resp)) UDP data bytes $(gw.hostname) "
    resp
end

function Sockets.recv(gw::SIS3316Gateway, len::Integer; timeout::Real = gw.default_timeout)
    resp = recv(gw, missing, timeout = timeout)
    resp_len = length(resp)
    length(resp) == len || throw(ErrorException("Received UDP response with $resp_len bytes, but expected $len bytes"))
    resp
end


function check_resp_pkg!(cmd::UInt8, pkgid::UInt8, recvbuf::IO)
    recv_cmd, recv_pkgid = read(recvbuf, UInt8), read(recvbuf, UInt8)
    recv_cmd == cmd || throw(ErrorException("Received response to command $recv_cmd, but expected $cmd"))
    recv_pkgid == pkgid || throw(ErrorException("Received with package id $recv_pkgid, but expected $pkgid"))
    recvbuf
end


function send_req_recv_resp!(gw::SIS3316Gateway, reqbuf::IO, recv_len::Union{Missing,Integer}; timeout::Real = gw.default_timeout)
    req = take!(reqbuf)
    cmd, pkgid = req[1], req[2]
 
    resp_pkg = lock(gw.socketio_lock) do
        send(gw, req)
        recv(gw, recv_len, timeout = timeout)
    end

    resp = IOBuffer(resp_pkg)
    check_resp_pkg!(cmd, pkgid, resp)

    resp
end


function check_connection(gw::SIS3316Gateway)
    lock(gw.socketio_lock) do
        req = UInt8[0x10, 0x42, 0x00, 0x00, 0x00, 0x04]
        send(gw, UInt8[0x10, 0x42, 0x00, 0x00, 0x00, 0x04])
        resp = try
            recv(gw, 10, timeout = 1.0)
        catch err
            if err isa EOFError
                throw(ErrorException("Can't connect to $gw"))
            else
                rethrow()
            end
        end
        inbuf = IOBuffer(resp)
        read(inbuf, 6) == req[1:6] || throw(ErrorException("Invalid UDP response $resp during connection test"))
        devinfo = read(inbuf, UInt32)
        @assert eof(inbuf)
        @info "Tested connection to $(gw.hostname), received device info $(repr(devinfo))"
    nothing
    end
end


function next_pkgid!(gw::SIS3316Gateway)
    lock(gw.socketio_lock) do
        next_id::UInt8 = gw.last_pkgid::UInt8 + UInt8(1)
        gw.last_pkgid = next_id
        next_id
    end
end


function read_link_interface_register(gw::SIS3316Gateway, addr::Integer; timeout::Real = gw.default_timeout)
    conv_addr = UInt32(addr)

    req = IOBuffer()
    write(req, UInt8(0x10))
    write(req, UInt8(next_pkgid!(gw)))
    write(req, htol(conv_addr))

    resp = send_req_recv_resp!(gw, req, 10, timeout = timeout)
 
    recv_addr = read(resp, UInt32)
    recv_value = read(resp, UInt32)
    @assert eof(resp)

    recv_addr == addr || throw(ErrorException("Received interface register value for address $(repr(recv_addr)), but expected address $(repr(conv_addr))"))

    recv_value
end


function write_link_interface_register!(gw::SIS3316Gateway, addr::Integer, value::Integer; timeout::Real = gw.default_timeout)
    conv_addr = UInt32(addr)
    conv_value = UInt32(value)

    req = IOBuffer()
    write(req, UInt8(0x11))
    write(req, htol(conv_addr))
    write(req, htol(conv_value))

    send(gw, take!(req))

    nothing
end


function _read_register_space_req(gw::SIS3316Gateway, addrs::Vector{UInt32}; timeout::Float64 = gw.default_timeout)
    n = length(eachindex(addrs))
    n == 0 && return Vector{UInt32}()
    n > 64 && throw(ArgumentError("Cannot read more than 64 registers with a single request"))

    req = IOBuffer()
    write(req, UInt8(0x20))
    write(req, UInt8(next_pkgid!(gw)))
    write(req, htol(UInt16(n - 1)))
    write(req, htol.(addrs::Vector{UInt32}))

    len_resp = 3 + n * sizeof(UInt32)
    resp = send_req_recv_resp!(gw, req, len_resp, timeout = timeout)

    status = read(resp, UInt8)
    data = read!(resp, Vector{UInt32}(undef, n))
    data .= htol.(data)
    @assert eof(resp)

    check_udp_response_status(status)
    pkg_counter = getval(status, UDPRespBits.pkg_counter)
    pkg_counter == 0 || throw(ErrorException("Packet counter in response is $pkg_counter, but expected 0"))

    data
end

function read_register_space(gw::SIS3316Gateway, addrs::AbstractVector{<:Integer}; timeout::Real = gw.default_timeout)
    data = Vector{UInt32}()
    sizehint!(data, length(eachindex(addrs)))
    for addrs_part in Base.Iterators.partition(addrs, 64)
        conv_addrs = convert(Vector{UInt32}, addrs_part)
        append!(data, _read_register_space_req(gw, conv_addrs, timeout = Float64(timeout)))
    end
    data
end


function read_registers!(gw::SIS3316Gateway, addrs::Vector{UInt32}, values::Vector{UInt32}; timeout::Float64 = gw.default_timeout)
    @debug "Reading registers $(repr(addrs)) on $gw"
    length(addrs) == length(values) || throw(ArgumentError("Number of addresses does not match number of values"))

    if !(isempty(addrs))
        lock(gw.socketio_lock) do
            li_idxs = findall(is_link_interface_register, addrs)
            re_idxs = findall(!is_link_interface_register, addrs)

            for i in li_idxs
                values[i] = read_link_interface_register(gw, addrs[i], timeout = timeout)
            end

            values[re_idxs] = read_register_space(gw, addrs[re_idxs], timeout = timeout)
        end
    end

    values
end

read_registers!(gw::SIS3316Gateway, addrs::AbstractVector{<:Integer}, values::AbstractVector{<:Integer}; timeout::Real = gw.default_timeout) =
    read_registers!(gw, convert(Vector{UInt32}, addrs), convert(Vector{UInt32}, values), timeout = Float64(timeout))



function _write_register_space_req!(gw::SIS3316Gateway, addrs_vals::Vector{Pair{UInt32,UInt32}}; timeout::Float64 = gw.default_timeout)
    n = length(addrs_vals)
    n == 0 && return Vector{UInt32}()
    n > 64 && throw(ArgumentError("Cannot write more than 64 registers with a single request"))

    addrs_data_flat = collect(Iterators.flatten(addrs_vals))

    req = IOBuffer()
    write(req, UInt8(0x21))
    write(req, UInt8(next_pkgid!(gw)))
    write(req, htol(UInt16(n - 1)))
    write(req, htol.(addrs_data_flat::Vector{UInt32}))

    resp = send_req_recv_resp!(gw, req, 3, timeout = timeout)

    status = read(resp, UInt8)
    @assert eof(resp)

    check_udp_response_status(status)
    pkg_counter = getval(status, UDPRespBits.pkg_counter)
    pkg_counter == 0 || throw(ErrorException("Packet counter in response is $pkg_counter, but expected 0"))
end

function write_register_space!(gw::SIS3316Gateway, addrs_vals::AbstractVector{<:Pair{<:Integer,<:Integer}}; timeout::Real = gw.default_timeout)
    for addr_vals_part in Base.Iterators.partition(addrs_vals, 64)
        conv_addr_vals = convert(Vector{Pair{UInt32,UInt32}}, addr_vals_part)
        _write_register_space_req!(gw, conv_addr_vals, timeout = Float64(timeout))
    end
    nothing
end

write_register_space!(gw::SIS3316Gateway, addrs::AbstractVector{<:Integer}, values::AbstractVector{<:Integer}; timeout::Real = gw.default_timeout) =
    write_register_space!(gw, addrs .=> values, timeout = timeout)


function write_registers!(gw::SIS3316Gateway, addrs::AbstractVector{UInt32}, values::AbstractVector{UInt32}; timeout::Float64 = gw.default_timeout)
    @debug "Writing registers $(repr(addrs)) on $gw"
    length(addrs) == length(values) || throw(ArgumentError("Number of addresses does not match number of values"))

    if !isempty(addrs)
        lock(gw.socketio_lock) do
            li_idxs = findall(is_link_interface_register, addrs)
            re_idxs = findall(!is_link_interface_register, addrs)

            # Since there's no acknowledgement when writing link interface
            # registers, make a short pause between each request and a
            # longer pause after all requests.
            for i in li_idxs
                write_link_interface_register!(gw, addrs[i], values[i], timeout = timeout)

                sleep(0.005) # or yield() for a shorter pause
            end
            sleep(0.02) # or yield() for a shorter pause

            write_register_space!(gw, addrs[re_idxs], values[re_idxs], timeout = timeout)
        end
    end

    nothing
end

write_registers!(gw::SIS3316Gateway, addrs::AbstractVector{<:Integer}, values::AbstractVector{<:Integer}; timeout::Real = gw.default_timeout) =
    write_registers!(gw, convert(Vector{UInt32}, addrs), convert(Vector{UInt32}, values), timeout = Float64(timeout))


"""
    read_bulk!(
        gw::SIS3316Gateway,
        addr::Unsigned,
        data::AbstractVector{UInt32};
        timeout::Float64 = gw.default_timeout
    )

SIS3316 FIFO read transfer.
"""
function read_bulk!(gw::SIS3316Gateway, addr::UInt32, data::AbstractVector{UInt32}; timeout::Float64 = gw.default_timeout)
    # @debug "read_bulk!(::SIS3316Gateway, $(repr(addr)), data)" 
    n = length(data)
    n == 0 && return data
    max_n = typemax(UInt16) + 1
    n > max_n && throw(ArgumentError("Cannot read more than $max_n 32-bit values with a single request"))

    chunks = Vector{Vector{UInt32}}(undef, 15)

    req = IOBuffer()
    cmd = UInt8(0x30)
    pkgid = next_pkgid!(gw)
    write(req, cmd::UInt8)
    write(req, pkgid::UInt8)
    write(req, htol(UInt16(n - 1)))
    write(req, htol(addr::UInt32))

    chunks_i0 = firstindex(chunks)
    n_words_recv::Int = 0
    n_chunks_recv::Int = 0

    lock(gw.socketio_lock) do
        send(gw, take!(req))

        while n_words_recv < n
            resp_pkg = recv(gw, timeout = timeout)
            resp = IOBuffer(resp_pkg)
            check_resp_pkg!(cmd, pkgid, resp)

            status = read(resp, UInt8)
            check_udp_response_status(status)
            pkg_counter = getval(status, UDPRespBits.pkg_counter)
            pkg_counter > 14 && throw(ErrorException("Received FIFO read response packet with packet counter value $pkg_counter, should be kept <= 14 to prevent overflow"))

            chunk_len = bytesavailable(resp)
            chunk_len % sizeof(UInt32) == 0 || throw(ErrorException("Received FIFO read response with packet counter value $pkg_counter, but data length is not a multiple of $(sizeof(UInt32)) bytes"))
            chunk_n = div(chunk_len, sizeof(UInt32))
            # @debug "Received FIFO read response with packet counter value $pkg_counter and $chunk_n data words"

            chunk = read!(resp, Vector{UInt32}(undef, chunk_n))
            chunk .= ltoh.(chunk)
            @assert eof(resp)

            if isassigned(chunks, pkg_counter + chunks_i0)
                throw(ErrorException("Received FIFO read response packet with duplicate packet counter value $pkg_counter"))
            else
                chunks[pkg_counter + chunks_i0] = chunk
                n_chunks_recv += 1
                n_words_recv += chunk_n
            end
        end
    end
    
    # @info "Received $n_chunks_recv FIFO data chunks"

    filled_chunk_idxs = chunks_i0:(chunks_i0 + n_chunks_recv - 1)

    data_pos::Int = firstindex(data)
    for i in filled_chunk_idxs
        isassigned(chunks, i) || throw(ErrorException("Missing data chunk $i"))
        chunk = chunks[i]
        n = length(chunk)
        copyto!(data, data_pos, chunk, firstindex(chunk), n)
        data_pos += n
    end
    @assert data_pos == lastindex(data) + 1

    return data
end
