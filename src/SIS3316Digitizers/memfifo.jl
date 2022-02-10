# This file is a part of SIS3316Digitizers.jl, licensed under the MIT License (MIT).

const ch_buffer_size = 64 * 1024 * 1024


@enum DataTransferCmd::UInt8 begin
    DataTransferCtlReset        = 0 # Reset Transfer FSM
    DataTransferCtlReset_Also   = 1 # 
    DataTransferCtlRead         = 2 # Start Read Transfer
    DataTransferCtlWrite        = 3 # Start Write Transfer
end
export DataTransferCmd
export DataTransferCtlReset, DataTransferCtlReset_Also, DataTransferCtlRead, DataTransferCtlWrite

@enum MemSpaceSel::UInt8 begin
    MemSpaceMem1                = 0 # Memory 1 (Ch. 1 and 2, resp. 5 and 6, etc.)
    MemSpaceMem2                = 1 # Memory 2 (Ch. 3 and 4, resp. 7 and 8, etc.)
    MemSpaceStatCounter         = 3 # Statistic Counter (128 32-bit words)
end
export MemSpaceSel
export MemSpaceMem1, MemSpaceMem2, MemSpaceStatCounter


const data_transfer_ctl_register_layout = (
    cmd               = BitRange{RW}(30:31, DataTransferCmd), # Cmd
    mem_space_sel     = BitRange{RW}(28:29, MemSpaceSel), # Space select bits
    mem_addr          = BitRange{RW}( 0:27), # Memory 32-bit start address (128 Meg x 16 : only address bits 25-0 are used )
)
export data_transfer_ctl_register_layout

# ADC FPGA Data Transfer Control Register (only write complete register!)
data_transfer_ctl_register(addr::Unsigned) = Register{RW,RegVal}(
    MemAddr(addr),
    data_transfer_ctl_register_layout
)

# ADC FPGA Data Transfer Control Register, Ch. 1 to 4
const data_transfer_ch1_4_ctrl_reg = data_transfer_ctl_register(0x80)
export data_transfer_ch1_4_ctrl_reg

# ADC FPGA Data Transfer Control Register, Ch. 5 to 8
const data_transfer_ch5_8_ctrl_reg = data_transfer_ctl_register(0x84)
export data_transfer_ch5_8_ctrl_reg

# ADC FPGA Data Transfer Control Register, Ch. 9 to 12
const data_transfer_ch9_12_ctrl_reg = data_transfer_ctl_register(0x88)
export data_transfer_ch9_12_ctrl_reg

# ADC FPGA Data Transfer Control Register, Ch. 13 to 16
const data_transfer_ch13_16_ctrl_reg = data_transfer_ctl_register(0x8C)
export data_transfer_ch13_16_ctrl_reg

# ADC FPGA Data Transfer Control Registers
const data_transfer_ctrl_reg = (
    data_transfer_ch1_4_ctrl_reg,
    data_transfer_ch5_8_ctrl_reg,
    data_transfer_ch9_12_ctrl_reg,
    data_transfer_ch13_16_ctrl_reg,
)
export data_transfer_ctrl_reg


function data_transfer_ctrl_regval(
    cmd::DataTransferCmd,
    mem_space_sel::MemSpaceSel,
    mem_addr::Unsigned
)
    v::RegVal = zero(RegVal)
    v = setval(v, data_transfer_ctl_register_layout.cmd, cmd)
    v = setval(v, data_transfer_ctl_register_layout.mem_space_sel, mem_space_sel)
    v = setval(v, data_transfer_ctl_register_layout.mem_addr, mem_addr)
    v
end
export data_transfer_ctrl_regval


# ADC FPGA Data Transfer Status Register
data_transfer_status_register(addr::Unsigned) = Register{RO,RegVal}(
    MemAddr(addr),
    (
        busy              = Bit{RO}(31),  # Data Transfer Logic busy
        direction         = Bit{RO}(30),  # Data Transfer Direction (Write-Flag; 0: Memory -> VME FPGA; 1: VME FPGA -> Memory)
        fifo_near_full    = Bit{RO}(28),  # FIFO (read VME FIFO) Data AlmostFull Flag
        max_no_pend_read  = Bit{RO}(27),  # "max_nof_pending_read_requests"
        no_pend_read      = Bit{RO}(26),  # "no_pending_read_requests"
        int_addr_counter  = BitRange{RO}(0:25),  # Data Transfer internal 32-bit Address counter
    )
)

# ADC FPGA Data Transfer Status Register, Ch. 1 to 4
const data_transfer_adc1_4_status_reg = data_transfer_status_register(0x90)
export data_transfer_adc1_4_status_reg

# ADC FPGA Data Transfer Status Register, Ch. 5 to 8
const data_transfer_adc5_8_status_reg = data_transfer_status_register(0x94)
export data_transfer_adc5_8_status_reg

# ADC FPGA Data Transfer Status Register, Ch. 9 to 12
const data_transfer_adc9_12_status_reg = data_transfer_status_register(0x98)
export data_transfer_adc9_12_status_reg

# ADC FPGA Data Transfer Status Register, Ch. 13 to 16
const data_transfer_adc13_16_status_reg = data_transfer_status_register(0x9C)
export data_transfer_adc13_16_status_reg


# ADC FPGA Data Transfer Status Registers
const data_transfer_status_reg = (
    data_transfer_adc1_4_status_reg,
    data_transfer_adc5_8_status_reg,
    data_transfer_adc9_12_status_reg,
    data_transfer_adc13_16_status_reg,
)
export data_transfer_status_reg


const dls_fpga_bits = BitGroup{RW}(
    frame_err_cl    = Bit{RW}(7),   # Write: ADC FPGA: Clear Frame_error_latch; Read: ADC FPGA: Frame_error_latch
    soft_err_cl     = Bit{RW}(6),   # Write: ADC FPGA: Clear Soft_error_latch; Read: ADC FPGA: Soft_error_latch
    hard_err_cl     = Bit{RW}(5),   # Write: ADC FPGA: Clear Hard_error_latch; Read: ADC FPGA: Hard_error_latch
    lane_up         = Bit{RO}(4),   # Read: ADC FPGA: Lane_up_flag
    ch_up           = Bit{RO}(3),   # Read: ADC FPGA: Channel_up_flag
    frame_err       = Bit{RO}(2),   # Read: ADC FPGA: Frame_error_flag
    soft_err        = Bit{RO}(1),   # Read: ADC FPGA: Soft_error_flag
    hard_err        = Bit{RO}(0),   # Read: ADC FPGA: Hard_error_flag
)

"""
    vme_fpga_link_adc_prot_status_register(addr::Unsigned)

VME FPGA – ADC FPGA Data Link Status register (R/W, 0xA0)

Note: Only write complete Register.
"""
const vme_fpga_link_adc_prot_status_register = Register{RW,RegVal}(
    MemAddr(0xA0),
    (
        adc = BitGroup{RW}(
            fpga1 = dls_fpga_bits <<  0,  # FPGA 1 bits
            fpga2 = dls_fpga_bits <<  8,  # FPGA 2 bits
            fpga3 = dls_fpga_bits << 16,  # FPGA 3 bits
            fpga4 = dls_fpga_bits << 24,  # FPGA 4 bits
        ),
    )
)
export vme_fpga_link_adc_prot_status_register


fpga_num(dev_ch::Int) = div((dev_ch - 1), 4) + 1
fpga_ch(dev_ch::Int) = rem((dev_ch - 1), 4) + 1
export fpga_num, fpga_ch


const data_transfer_ctl_register_layout = (
    cmd               = BitRange{RW}(30:31, DataTransferCmd), # Cmd
    mem_space_sel     = BitRange{RW}(28:29, MemSpaceSel), # Space select bits
    mem_addr          = BitRange{RW}( 0:27), # Memory 32-bit start address (128 Meg x 16 : only address bits 25-0 are used )
)
export data_transfer_ctl_register_layout


const mem_data_region = 0x00100000:0x00500000
export mem_data_region

const mem_fifo_region = first(mem_data_region):first(mem_data_region) + 0x000FFFFD
export mem_fifo_region

const fifo_start_addr = IdDict(
    1 => 0x00100000,
    2 => 0x00200000,
    3 => 0x00300000,
    4 => 0x00400000,
)
export fifo_start_addr

const fpga_ch_offset = IdDict(
    1 => 0x00000000,
    2 => 0x02000000,
    3 => 0x00000000,
    4 => 0x02000000,
)
export fpga_ch_offset


const bank_offset = IdDict(
    1 => 0x00000000,
    2 => 0x01000000,
)
export bank_offset

function fpga_ch_fifo_addr_offset(fpga_ch::Integer, bank::Integer)
    1 <= fpga_ch <= 4 || throw(ArgumentError("ADC FPGA channel number must be between 1 and 4"))
    1 <= bank <= 2 || throw(ArgumentError("Bank must be 1 or 2"))

    fpga_ch_offset[fpga_ch] + bank_offset[bank]
end
export fpga_ch_fifo_addr_offset


const fpga_ch_mem_space_sel = IdDict(
    1 => MemSpaceMem1,
    2 => MemSpaceMem1,
    3 => MemSpaceMem2,
    4 => MemSpaceMem2
)
export fpga_ch_mem_space_sel


function jumbo_frames_enabled(mem::SIS3316Memory)
    # Called during fifo I/O, bypass R/W task:
    r = UInt32[0]
    SIS3316Digitizers.read_registers!(mem.gw, [getaddress(SIS3316Digitizers.udp_protocol_config_reg)], r)
    getval(first(r), getlayout(SIS3316Digitizers.udp_protocol_config_reg.jumbo_packet_enable))
end
export jumbo_frames_enabled

function jumbo_frames_enabled!(mem::SIS3316Memory, enabled::Bool)
    mem[SIS3316Digitizers.udp_protocol_config_reg.jumbo_packet_enable] = enabled
end
export jumbo_frames_enabled!


function start_fifo_read!(mem::SIS3316Memory, ch::Integer, bank::Integer, from::Unsigned)
    @debug "Starting FIFO data transfer for channel $ch, bank $bank, address $(repr(from))"
    @argcheck from % 4 == 0
    @argcheck from < 0x10000000
    
    from_word = div(from, 4) #!!!!????

    group = fpga_num(ch)
    grp_ch = fpga_ch(ch)

    cmd = DataTransferCtlRead
    mem_space_sel = fpga_ch_mem_space_sel[grp_ch]
    mem_addr = fpga_ch_fifo_addr_offset(grp_ch, bank) + from_word

    ctlreg_addr = getaddress(data_transfer_ctrl_reg[group])
    ctlreg_val = data_transfer_ctrl_regval(cmd, mem_space_sel, mem_addr)

    # @debug "Writing value $(repr(ctlreg_val)) to data transfer control register $(repr(ctlreg_addr))"
    #mem.sync() #!!!
    #mem[ctlreg_addr] = ctlreg_val
    # Bypass R/W task:
    write_registers!(mem.gw, [ctlreg_addr], [ctlreg_val])
    nothing
end
export start_fifo_read!


function reset_fifo!(mem::SIS3316Memory, ch::Integer)
    @argcheck 1 <= ch <= 16
    @debug "Resetting FIFO data transfer for channel $ch"
    group = fpga_num(ch)

    ctlreg_addr = getaddress(data_transfer_ctrl_reg[group])
    ctlreg_val = setval(zero(RegVal), data_transfer_ctl_register_layout.cmd, DataTransferCtlReset)

    # @debug "Writing value $(repr(ctlreg_val)) to data transfer control register $(repr(ctlreg_addr))"
    #mem.sync() #!!!
    #mem[ctlreg_addr] = ctlreg_val
    # Bypass R/W task:
    write_registers!(mem.gw, [ctlreg_addr], [ctlreg_val])
    nothing
end
export reset_fifo!


const max_udp_req_pkg_size = 1485
const max_udp_resp_pkg_size = 1485
const max_udp_jumbo_pkg_size = 8237

const udp_resp_header_size = 45 # According to SIS3316 docs - why not 28 (17 + 8 + 3)?
const max_n_resp_data_frames = 15

const max_n_bytes_per_req = div(min(
    max_n_resp_data_frames * (max_udp_resp_pkg_size - udp_resp_header_size),
    (typemax(UInt16) + 1) * sizeof(UInt32)
), sizeof(UInt32)) * sizeof(UInt32)


function read_adc_fifo_raw!(mem::SIS3316Memory, address::MemAddr, data::AbstractVector{T}) where {T<:Unsigned}
    use_jumbo_frames = jumbo_frames_enabled(mem) # Register read also ensures no pending reads/writes

    n_bytes = Int(length(eachindex(data)) * sizeof(T))
    @argcheck n_bytes % sizeof(UInt32) == 0
    @debug "Reading $n_bytes from FIFO memory, starting at address $(repr(address))" 

    udp_resp_size_limit = use_jumbo_frames ? max_udp_jumbo_pkg_size : max_udp_resp_pkg_size

    max_n_bytes_per_req = div(min(
        max_n_resp_data_frames * (udp_resp_size_limit - udp_resp_header_size),
        (typemax(UInt16) + 1) * sizeof(UInt32)
    ), sizeof(UInt32)) * sizeof(UInt32)

    data_words = reinterpret(UInt32, data)
    max_n_words_per_req = div(max_n_bytes_per_req, sizeof(UInt32))

    for data_bytes_part in Base.Iterators.partition(data_words, max_n_words_per_req)
        # With the SIS3316 UDP Interface, address does not increase from
        # chunk to chunk for a FIFO read (different from SIS3153):
        from_addr = address

        read_bulk!(mem.gw, from_addr, data_bytes_part)
    end

    data
end
export read_adc_fifo_raw!


function _read_ch_bank_data_padded!(data::AbstractVector{UInt8}, mem::SIS3316Memory, ch::Int, bank::Int, padded_from::MemAddr)
    @argcheck padded_from + length(eachindex(data)) <= MemAddr(0x04000000)

    lock(mem.fifo_lock)
    try
        fifo_addr = fifo_start_addr[fpga_num(ch) ]
        reset_fifo!(mem, ch)
        start_fifo_read!(mem, ch, bank, MemAddr(padded_from))
        read_adc_fifo_raw!(mem, fifo_addr, data)
        reset_fifo!(mem, ch)
    finally
        unlock(mem.fifo_lock)
    end

    nothing
end

function read_ch_bank_data(mem::SIS3316Memory, ch::Integer, bank::Integer, from::Integer = 0, n_bytes::Integer = ch_buffer_size)
    @argcheck from >= 0
    @argcheck n_bytes >= 0
    
    unpadded_from = MemAddr(from)
    unpadded_until = MemAddr(unpadded_from + n_bytes)
    unpadded_nbytes = unpadded_until - unpadded_from

    @debug "Reading bank $bank data for channel $ch from $(repr(unpadded_from)) until $(repr(unpadded_until))"

    padded_from = MemAddr(div(unpadded_from, 8) * 8) # Must be a multiple of 64 bit
    padded_until = MemAddr(div(unpadded_until + 7, 8) * 8) # Must be a multiple of 64 bit
    padded_nbytes = padded_until - padded_from

    @assert padded_from <= unpadded_from
    @assert padded_until >= unpadded_until

    data = Vector{UInt8}(undef, padded_nbytes)
    multiple_tries(5, (EOFError,), "Reading padded bank data for channel $ch") do
        _read_ch_bank_data_padded!(data, mem, Int(ch), Int(bank), padded_from)
    end

    view_start = firstindex(data) + (unpadded_from - padded_from)
    view_end = view_start + unpadded_nbytes - 1
    view(data, view_start:view_end)
end
export read_ch_bank_data
