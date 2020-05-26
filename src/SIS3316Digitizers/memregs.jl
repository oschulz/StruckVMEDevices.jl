# This file is a part of SIS3316Digitizers.jl, licensed under the MIT License (MIT).


const shift_by_one = (x -> signed(x + 1), x -> unsigned(x) - 1)


function linear_conv(;offset::Real = 1, scale::Real = 1)
    (
        x -> fma(x, scale, offset),
        x -> trunc(UInt32, x - offset / scale) 
    )
end


const word_byte_addr_conv = (
    x -> x * typeof(x)(4),
    x -> begin
        @argcheck rem(x, 4) == 0
        div(x, 4)
    end
)


function bool_val_conv(a, b)
    (
        x::Bool -> x ? b : a,
        x -> begin
            @argcheck x == a || x == b
            x == b ? true : false
        end
    )
end



const all_channels = 1:16
const all_fpga_groups = 1:4
const all_banks = 1:2
export all_channels, all_fpga_groups, all_banks



# VME interface registers
# -----------------------

const led_bits = BitGroup{JKRW}(
    mode        = Bit{JKRW}(4), # Application Mode
    state       = Bit{JKRW}(0), # on/off
)

"""Control/Status Register (0x00, `control_status_reg`)"""
const control_status_reg = Register{JKRW,RegVal}(
    MemAddr(0x00),
    (
        reboot_fpgas    = Bit{JKRW}(15),    # Status Reboot FPGAs
        led2            = led_bits << 2,    # Status LED 2 bits
        led1            = led_bits << 1,    # Status LED 1 bits
        ledU            = led_bits << 0,    # Status LED U bits
    )
)
export control_status_reg



"""Module Id. and Firmware Revision Register (0x04, `modid_fw_reg`)"""
const modid_fw_reg = Register{RO,RegVal}(
    MemAddr(0x04),
    (
        module_id       = BitRange{RO}(16:31),  # Module Id. (BCD)
        major_revision  = BitRange{RO}( 8:15),  # Major Revision (BCD)
        minor_revision  = BitRange{RO}( 0: 7),  # Minor Revision (BCD)
    )
)
export modid_fw_reg


# Not implemented: VME GW: Interrupt configuration register (0x8)
# Not implemented: VME GW: Interrupt control register (0xC)
# Not implemented: SIS3316: UDP Protocol Configuration Register (0x08)
# Not implemented: SIS3316: Last UDP Acknowledge Status Register (0x0C)


"""
    interface_access_arbitration_control_reg

(Link) Interface Access Arbitration Control Register (0x10, `interface_access_arbitration_control_reg`)

Note: Only write complete Register.
"""
const interface_access_arbitration_control_reg = Register{RW,RegVal}(
    MemAddr(0x10),
    (
        kill_other_if_req   = Bit{RW}(31),  # Kill of other interface request bit command
        # other_if_req_stat = Bit{RW}(21),  # Status of other interface grant bit
        # own_if_req_stat   = Bit{RW}(20),  # Status of own interface grant bit
        other_if_req_stat   = Bit{RW}(17),  # Status of other interface request bit
        own_if_req_stat     = Bit{RW}(16),  # Status of own interface request bit
        own_if_req          = Bit{RW}( 0),  # Own interface request bit
    )
)
export interface_access_arbitration_control_reg


# Not implemented: Broadcast Setup Register (0x14)


"""Hardware Version Register (0x1C, `hardware_version_reg`)"""
const hardware_version_reg = Register{RO,RegVal}(
    MemAddr(0x1C),
    (
        version         = BitRange{RO}(0:3),    # Hardware Version
    )
)
export hardware_version_reg



# ADC interface registers
# -----------------------


"""Temperature Register (0x20, R/W, `internal_temperature_reg`)"""
const internal_temperature_reg = Register{RW,RegVal}(
    MemAddr(0x20),
    (
        temperature     = BitRange{RO}(0:9, linear_conv(scale = 0.25)), # Temperature Data
    )
)
export internal_temperature_reg


# Not implemented: Onewire EEPROM Control Register (0x24)


"""Serial Number Register (0x28, R/O, `serial_number_reg`)"""
const serial_number_reg = Register{RO,RegVal}(
    MemAddr(0x28),
    (
        dhcp_option     = BitRange{RO}(24:31),  # DHCP Option Value
        serno_invalid   = Bit{RO}(16),            # Serial Number Not Valid Flag
        serno           = BitRange{RO}(0:15),   # Serial Number
    )
)
export serial_number_reg


# Not implemented: Internal Transfer Speed register (0x2C)
# Not implemented: ADC FPGA Boot control register (0x30)
# Not implemented: SPI Flash Control/Status register (0x34)
# Not implemented: SPI Flash Data register (0x38)


"""
Programmable ADC Clock I2C register (0x40, R/W, `clk_osc_i2c_reg`)
"""
const clk_osc_i2c_reg = Register{RW,RegVal}(
    MemAddr(0x40),
    (                                       
        read_byte       = Bit{RW}(13),      # Read byte, put ACK
        write_byte      = Bit{RW}(12),      # Write byte, put ACK
        stop            = Bit{RW}(11),      # STOP
        repeat_start    = Bit{RW}(10),      # Repeat START
        start           = Bit{RW}( 9),      # START
        ack             = Bit{RW}( 8),      # Read: Received Ack on write cycle; Write: Ack on read cycle
        data            = BitRange{RW}(0:7), # Read: Read data; Write: Write data    
    )
)
export clk_osc_i2c_reg


# Not implemented: Programmable MGT1 Clock I2C register (0x44, not used, according to manual)
# Not implemented: Programmable MGT2 Clock I2C register (0x48, not used, according to manual)
# Not implemented: Programmable DDR3 Clock I2C register (0x4C, not used, according to manual)


"""ADC Sample Clock distribution control Register (0x50, `sample_clock_distctl_reg`)"""
const sample_clock_distctl_reg = Register{RW,RegVal}(
    MemAddr(0x50),
    (
        adc_clk_mux     = BitRange{RW}(0:1),    # ADC Sample Clock Multiplexer select bits
    )
    # (0: Internal osc.; 1: VXS; 2: FP-LVDS; 3: FP-NIM)
)
export sample_clock_distctl_reg


"""
    nim_clk_multiplier_spi_reg

External NIM Clock Multiplier SPI Register (0x54, R/W)

* (Cmd Bit 1, Cmd Bit 0) == (0, 0): Execute SPI Write/Read Cmd
* (Cmd Bit 1, Cmd Bit 0) == (0, 1): Reset Cmd

Note: Only write complete Register.
"""
const nim_clk_multiplier_spi_reg = Register{RW,RegVal}(
    MemAddr(0x54),
    (
        cmd_bit_1       = Bit{RW}(31),          # Write: Cmd Bit 1; Read: Read/Write Cmd BUSY Flag
        cmd_bit_0       = Bit{RW}(30),          # Write: Cmd Bit 0; Read: Reset Cmd BUSY Flag
        instruction     = BitRange{RW}(8:15),   # Write: Instruction Byte
        addr_data       = BitRange{RW}(0:7),    # Write: Address/Data; Read: Data
    )
)
export nim_clk_multiplier_spi_reg


"""FP-Bus control Register (0x58, R/W, `fp_lvds_bus_control_reg`)"""
const fp_lvds_bus_control_reg = Register{RW,RegVal}(
    MemAddr(0x58),
    (
      # FP-Bus Sample Clock Out MUX bit
      # Selects the source of the FP-Bus Sample Clock
      #
      # * Value 0: Onboard programmable oscillator ( after power up: 125MHz)
      # * Value 1: External clock from NIM connector CI (via programmable clock multiplier)
      smpl_clk_out_mux  = Bit{RW}(5),

      # FP-Bus Sample Clock Out Enable
      # Enables the Sample Clock:the FP- Bus (only on one SIS3316)
      smpl_clk_out_en   = Bit{RW}(4),

      # FP-Bus Status Lines Output Enable
      # Enables the Status Lines:the FP-Bus (on all SIS3316)
      stat_lines_out_en = Bit{RW}(1),

      # FP-Bus Control Lines Output Enable
      # Enables the Control Lines:the FP-Bus (only on one SIS3316)
      ctrl_lines_out_en = Bit{RW}(0),
    )
)
export fp_lvds_bus_control_reg


"""NIM Input Control/Status Register (0x5C, R/W, `nim_input_control_reg`"""
const nim_input_control_reg = Register{RW,RegVal}(
    0x0000005C,
    (
        input_sig_ui_stat = Bit{RO}(25),    # Write: reserved; Read: Status of NIM Input signal UI
        ext_in_ui_stat    = Bit{RO}(24),    # Write: reserved; Read: Status of External NIM Input UI
        input_sig_ti_stat = Bit{RO}(21),    # Write: reserved; Read: Status of NIM Input signal UI
        ext_in_ti_stat    = Bit{RO}(20),    # Write: reserved; Read: Status of External NIM Input UI
        in_ui_pss_en      = Bit{RW}(13),    # NIM Input UI as PPS Enable
        in_ui_veto_en     = Bit{RW}(12),    # NIM Input UI as Veto Enable
        in_ui_func        = Bit{RW}(11),    # Set NIM Input UI Function
        in_ui_level_sens  = Bit{RW}(10),    # NIM Input UI Level sensitive
        in_ui_inv         = Bit{RW}( 9),    # NIM Input UI Invert
        in_ui_tsclear_en  = Bit{RW}( 8),    # NIM Input UI as Timestamp Clear Enable
        in_ti_func        = Bit{RW}( 7),    # Set NIM Input TI Function
        in_ti_level_sens  = Bit{RW}( 6),    # NIM Input TI Level sensitive
        in_ti_inv         = Bit{RW}( 5),    # NIM Input TI Invert
        in_ti_trig_en     = Bit{RW}( 4),    # NIM Input TI as Trigger Enable
        in_ci_func        = Bit{RW}( 3),    # Set NIM Input CI Function
        in_ci_level_sens  = Bit{RW}( 2),    # NIM Input CI Level sensitive
        in_ci_inv         = Bit{RW}( 1),    # NIM Input CI Invert
        in_ci_en          = Bit{RW}( 0),    # NIM Input CI Enable
    )
)
export nim_input_control_reg


const fpga_bits = BitGroup{RW}(
    mem_addr_thresh = Bit{RO}(1),  # Write: reserved; Read: Status of Memory Address Threshold Flag
    smpl_busy       = Bit{RO}(0),  # Write: reserved; Read: Status of Sample Logic Busy
)

"""
    acquisition_control_status_reg

Acquisition control/status Register (0x60, R/W)

* single_bank_mode value: 0 = double bank mode, 1 = single bank mode
* nim_ui_bank_swap value: 0/1 = disable/enable toggling of the active Sample Bank with a signal on NIM Input UI
* nim_ti_bank_swap value: 0/1 = disable/enable toggling of the active Sample Bank with a signal on NIM Input TI
* nim_bank_swap_en value: 0/1 = "Sample Bank Swap Control with NIM Input TI/UI" Logic is disabled/enabled
"""
const acquisition_control_status_reg = Register{RW,RegVal}(
    MemAddr(0x60),
    (
        fpga = BitGroup{RW}(
            fpga1 = fpga_bits << 24,  # FPGA 1 bits    
            fpga2 = fpga_bits << 26,  # FPGA 2 bits
            fpga3 = fpga_bits << 28,  # FPGA 3 bits
            fpga4 = fpga_bits << 30,  # FPGA 4 bits
        ),
        pps_latch_stat    = Bit{RO}(23),  # Write: reserved; Read: Status of "PPS latch bit"
        nim_bank_swap_en  = Bit{RO}(22),  # Write: reserved; Read: Status of "Sample Bank Swap Control with NIM Input TI/UI" Logic enabled
        fp_addr_thresh    = Bit{RO}(21),  # Write: reserved; Read: Status of FP-Bus-In Status 2: Address Threshold flag
        fp_smpl_busy      = Bit{RO}(20),  # Write: reserved; Read: Status of FP-Bus-In Status 1: Sample Logic busy
        mem_addr_thresh   = Bit{RO}(19),  # Write: reserved; Read: Status of Memory Address Threshold flag (OR)
        smpl_busy         = Bit{RO}(18),  # Write: reserved; Read: Status of Sample Logic Busy (OR)
        smpl_armed_bank   = Bit{RO}(17, shift_by_one),  # Write: reserved; Read: Status of ADC Sample Logic Armed On Bank2 flag
        smpl_armed        = Bit{RO}(16),  # Write: reserved; Read: Status of ADC Sample Logic Armed
        ext_trig_dis_on_b = Bit{RW}(15),  # External Trigger Disable with internal Busy select
        int_trig_to_ext   = Bit{RW}(14),  # Feedback Selected Internal Trigger as External Trigger Enable
        nim_ui_bank_swap  = Bit{RW}(13),  # NIM Input UI as "disarm Bankx and arm alternate Bank" command Enable
        nim_ti_bank_swap  = Bit{RW}(12),  # NIM Input TI as "disarm Bankx and arm alternate Bank" command Enable
        local_veto        = Bit{RW}(11),  # Local Veto function as Veto Enable
        ext_tsclear_en    = Bit{RW}(10),  # External Timestamp-Clear function Enable
        ext_trig_as_veto  = Bit{RW}( 9),  # External Trigger function as Veto Enable
        ext_trig_en       = Bit{RW}( 8),  # External Trigger function as Trigger Enable
        fp_smpl_ctrl_en   = Bit{RW}( 7),  # FP-Bus-In Sample Control Enable
        fp_ctrl2_en       = Bit{RW}( 6),  # FP-Bus-In Control 2 Enable
        fp_ctrl2_as_veto  = Bit{RW}( 5),  # FP-Bus-In Control 1 as Veto Enable
        fp_ctrl1_as_trig  = Bit{RW}( 4),  # FP-Bus-In Control 1 as Trigger Enable
        single_bank_mode  = Bit{RW}( 0),  # Single Bank Mode Enable (reserved)        
    )
)
export acquisition_control_status_reg


"""
    lookup_table_control_reg

Trigger Coincidence Lookup Table Control Register (0x64, R/W)

Note: Only write complete Register.
"""
const lookup_table_control_reg = Register{RW,RegVal}(
    MemAddr(0x64),
    (
        table_clear         = Bit{RW}(31),          # Write: Lookup Table Clear command; Read: Status Clear Busy
        table2_pulse_len    = BitRange{RW}(8:15),   # Lookup Table 2 Coincidence output pulse length
        table1_pulse_len    = BitRange{RW}(0:7),    # Lookup Table 1 Coincidence output pulse length
    )
)
export lookup_table_control_reg


"""
    lookup_table_addr_reg

Trigger Coincidence Lookup Table Address Register (0x68, R/W)

Note: Only write complete Register.
"""
const lookup_table_addr_reg= Register{RW,RegVal}(
    MemAddr(0x68),
    (
        mask        = BitRange{RW}(16:31),  # Lookup Table 1 and 2  Channel Trigger Mask
        rw_addr     = BitRange{RW}(0:15),   # Lookup Table 1 and 2 Write/Read Address
    )
)
export lookup_table_addr_reg


"""
    lookup_table_data_reg

Trigger Coincidence Lookup Table Data register (0x6C, R/W)

Note: Only write complete Register.
"""
const lookup_table_data_reg = Register{RW,RegVal}(
    MemAddr(0x6C),
    (
        table2_     = Bit{RW}(1),   # Lookup Table 2 Coincidence validation bit
        table1_     = Bit{RW}(0),   # Lookup Table 1 Coincidence validation bit
    )
)
export lookup_table_data_reg


# Not implemented: LEMO Out "CO" Select register (0x70)
# Not implemented: LEMO Out "TO" Select register (0x74)
# Not implemented: LEMO Out "UO" Select register (0x78)


"""Internal Trigger Feedback Select register (RW, 0x7C, `internal_trigger_feedback_select_reg`)"""
const internal_trigger_feedback_select_reg = Register{RW,RegVal}(
    MemAddr(0x7C),
    (
        lut1_coind_sel      = Bit{RW}(24),  # Select Lookup Table 1 Coincidence stretched output pulse
        sel_sum_trig = BitGroup{RW}(
            grp1    = Bit{RW}(16),  # Select internal SUM-Trigger stretched pulse ch1-4
            grp2    = Bit{RW}(17),  # Select internal SUM-Trigger stretched pulse ch5-8
            grp3    = Bit{RW}(18),  # Select internal SUM-Trigger stretched pulse ch19-12
            grp4    = Bit{RW}(19),  # Select internal SUM-Trigger stretched pulse ch13-16
        ),
        sel_trig = BitGroup{RW}(
            ch1     = Bit{RW}( 0),  # Select internal Trigger stretched pulse ch 1
            ch2     = Bit{RW}( 1),  # Select internal Trigger stretched pulse ch 2
            ch3     = Bit{RW}( 2),  # Select internal Trigger stretched pulse ch 3
            ch4     = Bit{RW}( 3),  # Select internal Trigger stretched pulse ch 4
            ch5     = Bit{RW}( 4),  # Select internal Trigger stretched pulse ch 5
            ch6     = Bit{RW}( 5),  # Select internal Trigger stretched pulse ch 6
            ch7     = Bit{RW}( 6),  # Select internal Trigger stretched pulse ch 7
            ch8     = Bit{RW}( 7),  # Select internal Trigger stretched pulse ch 8
            ch9     = Bit{RW}( 8),  # Select internal Trigger stretched pulse ch 9
            ch10    = Bit{RW}( 9),  # Select internal Trigger stretched pulse ch 10
            ch11    = Bit{RW}(10),  # Select internal Trigger stretched pulse ch 11
            ch12    = Bit{RW}(11),  # Select internal Trigger stretched pulse ch 12
            ch13    = Bit{RW}(12),  # Select internal Trigger stretched pulse ch 13
            ch14    = Bit{RW}(13),  # Select internal Trigger stretched pulse ch 14
            ch15    = Bit{RW}(14),  # Select internal Trigger stretched pulse ch 15
            ch16    = Bit{RW}(15),  # Select internal Trigger stretched pulse ch 16
        ),
    )
)
export internal_trigger_feedback_select_reg




"""ADC FPGA SPI BUSY Status register (0xA4, R/O, `fpga_spi_busy_status_reg`)"""
const fpga_spi_busy_status_reg = Register{RO,RegVal}(
    MemAddr(0xA4),
    (
        busy        = Bit{RO}(31),  # ADC FPGAx: Busy flag (or of ADC FPGA 1:4 Busy flags)
        fpga = BitGroup{RO}(
            fpga1   = Bit{RO}( 0),  # ADC FPGA 1: Busy flag
            fpga2   = Bit{RO}( 1),  # ADC FPGA 2: Busy flag
            fpga3   = Bit{RO}( 2),  # ADC FPGA 3: Busy flag
            fpga4   = Bit{RO}( 3),  # ADC FPGA 4: Busy flag
        )
    )
)
export fpga_spi_busy_status_reg


# Not implemented: Prescaler Output Pulse Divider register (0xB8)
# Not implemented: Prescaler Output Pulse Length register (0xBC)


# ADC key registers
# -----------------

"""Key address: Register Reset (0x400, `key_reset_addr`)"""
const key_reset_addr = MemAddr(0x400)
export key_reset_addr

"""Key address: User function logic (0x404, `key_user_function_addr`)"""
const key_user_function_addr = MemAddr(0x404)
export key_user_function_addr

"Key address: Arm sample logic (0x410, `key_arm`)"
const key_arm_addr = MemAddr(0x410)
export key_arm_addr

"""Key address: Disarm sample logic (0x414, `key_disarm_addr`)"""
const key_disarm_addr = MemAddr(0x414)
export key_disarm_addr

"""Key address: Trigger (0x418, `key_trigger_addr`)"""
const key_trigger_addr = MemAddr(0x418)
export key_trigger_addr

"""Key address: Timestamp Clear (0x41C, `key_timestamp_clear_addr`)"""
const key_timestamp_clear_addr = MemAddr(0x41C)
export key_timestamp_clear_addr


"""Key address: Disarm Bankx and Arm Bank1 (0x420, `key_disarm_and_arm_bank1_addr`)"""
const key_disarm_and_arm_bank1_addr = MemAddr(0x420)
export key_disarm_and_arm_bank1_addr

"""Key address: Disarm Bankx and Arm Bank2 (0x424, `key_disarm_and_arm_bank2_addr`)"""
const key_disarm_and_arm_bank2_addr = MemAddr(0x424)
export key_disarm_and_arm_bank2_addr

"""Key address: Disarm Bankx and Arm Banky (`key_disarm_and_arm_bank_addr`)"""
const key_disarm_and_arm_bank_addr = (
    key_disarm_and_arm_bank1_addr,
    key_disarm_and_arm_bank2_addr,
)
export key_disarm_and_arm_bank_addr


"""Key address: Enable Sample Bank Swap Control with NIM Input TI/UI Logic (0x428, `key_enable_sample_bank_swap_control_with_nim_input_addr`)"""
const key_enable_sample_bank_swap_control_with_nim_input_addr = MemAddr(0x428)
export key_enable_sample_bank_swap_control_with_nim_input_addr

"""Key address: Disable Prescaler Output Pulse Divider logic (0x42C, `key_disable_prescaler_output_pulse_divider_addr`)"""
const key_disable_prescaler_output_pulse_divider_addr = MemAddr(0x42C)
export key_disable_prescaler_output_pulse_divider_addr

"""Key address: PPS_Latch_Bit_clear (0x430, `key_pps_latch_bit_clear_addr`)"""
const key_pps_latch_bit_clear_addr = MemAddr(0x430)
export key_pps_latch_bit_clear_addr

"""Key address: Reset ADC-FPGA-Logic (0x434, `key_adc_fpga_reset_addr`)"""
const key_adc_fpga_reset_addr = MemAddr(0x434)
export key_adc_fpga_reset_addr

"""Key address: ADC Clock DCM/PLL Reset (0x438, `key_adc_clock_dcm_reset_addr`)"""
const key_adc_clock_dcm_reset_addr = MemAddr(0x438)
export key_adc_clock_dcm_reset_addr



# ADC FPGA Registers
# ------------------

function adc_fpga_registers(mklayout::Function, ::Val{Acc}, rel_addr::Unsigned) where Acc
    (
        ch01_04 = Register{RW,RegVal}(MemAddr(0x1000 + rel_addr), mklayout()),
        ch05_08 = Register{RW,RegVal}(MemAddr(0x2000 + rel_addr), mklayout()),
        ch09_12 = Register{RW,RegVal}(MemAddr(0x3000 + rel_addr), mklayout()),
        ch13_16 = Register{RW,RegVal}(MemAddr(0x4000 + rel_addr), mklayout()),
    )
end


"""
    input_tap_delay_regs

ADC Input Tap Delay Registers (R/W)

Note: Only write complete Register.
"""
const input_tap_delay_regs = adc_fpga_registers(Val(RW), 0x000) do
    (
        half_smpl_delay     = Bit{RW}(12),  # Add 1⁄2 Sample Clock period delay bit (since ADC Version V-0250-0004 and V-0125-0004)
        calib               = Bit{RW}(11),  # Calibration
        lnk_err_latch_clr   = Bit{RW}(10),  # Clear Link Error Latch bits
        sel_ch_34           = Bit{RW}(9),   # Ch. 3 and 4 select
        sel_ch_12           = Bit{RW}(8),   # Ch. 1 and 2 select
        tap_delay           = BitRange{RW}(0:7), # Tap delay value (times 40ps, max. 1⁄2 Sample Clock period)
    )
end
export input_tap_delay_regs


const analog_ctrl_chbits = BitGroup{RW}(
    term_dis    = Bit{RW}(2),           # Disable 50 Ohm Termination
    gain_ctrl   = BitRange{RW}(0:1),    # Gain Control
)

"""
    analog_ctrl_regs

ADC Gain and Termination Control Registers (R/W, `analog_ctrl_reg`)

Gain control value:

    * 0: 5 V
    * 1: 2 V
    * 2: 1.9 V
    * 3: 1.9 V
"""
const analog_ctrl_regs = adc_fpga_registers(Val(RW), 0x004) do
    (
        ch = BitGroup{RW}(
            ch1 = analog_ctrl_chbits <<  0,  # Ch. 1 bits
            ch2 = analog_ctrl_chbits <<  8,  # Ch. 2 bits
            ch3 = analog_ctrl_chbits << 16,  # Ch. 3 bits
            ch4 = analog_ctrl_chbits << 24,  # Ch. 4 bits
        ),
    )        
end
export analog_ctrl_regs


"""ADC Offset (DAC) Control Registers (W/O, `dac_offset_ctrl_reg`)"""
const dac_offset_ctrl_regs = adc_fpga_registers(Val(WO), 0x008) do
    (
        crtl_mode         = BitRange{WO}(29:31),  # DAC Ctrl Mode
        command           = BitRange{WO}(24:27),  # DAC Command
        dac_addr          = BitRange{WO}(20:23),  # DAC Address
        data              = BitRange{WO}(4:19),   #  DAC Data
    )        
end
export dac_offset_ctrl_regs


"""ADC Offset (DAC) Readback Registers (R/W, `dac_offset_readback_reg`)"""
const dac_offset_readback_regs = adc_fpga_registers(Val(RO), 0x108) do
    (
        data    = BitRange{RO}(0:15),   # DAC Read Data
    )        
end
export dac_offset_readback_regs


@enum SPICmd::UInt8 begin
    NoOp            = 0  # no function
    Reserved        = 1  # Reserved (ADC Synch Cmd)
    Write           = 2  # Write Cmd (relevant bits: 22 and 20:0)
    Read            = 3  # Read Cmd (relevant bits: 22 and 20:0)
end

"""
    spi_ctrl_reg

ADC SPI Control Registers (R/W)

Note: Only write complete Register.
"""
const spi_ctrl_regs = adc_fpga_registers(Val(RW), 0x00c) do
    (
        cmd         = BitRange{RW}(30:31, SPICmd), # Command
        data_out_en = Bit{RW}(24),          # ADC Data Output Enable
        sel_ch34    = Bit{RW}(22),          # Select ADCx ch3/ch4 bit
        rw_addr     = BitRange{RW}(8:20),   # Address
        data        = BitRange{RW}(0:7),    # Write Data
    )        
end
export spi_ctrl_regs


"""ADC SPI Readback Registers (R/O, `spi_readback_reg`)"""
const spi_readback_regs = adc_fpga_registers(Val(RO), 0x10c) do
    (
        data    = BitRange{RO}(0:15),   # Read Data
    )        
end
export spi_readback_regs


const evt_cfg_chbits = BitGroup{RW}(
    ext_veto_en       = Bit{RW}(7),     # External Veto Enable bit
    ext_gate_en       = Bit{RW}(6),     # External Gate Enable bit
    int_gate2_en      = Bit{RW}(5),     # Internal Gate 2 Enable bit
    int_gate1_en      = Bit{RW}(4),     # Internal Gate 1 Enable bit
    ext_trig_en       = Bit{RW}(3),     # External Trigger Enable bit
    int_trig_en       = Bit{RW}(2),     # Internal Trigger Enable bit
    sum_trig_en       = Bit{RW}(1),     # Internal SUM-Trigger Enable bit
    input_inv         = Bit{RW}(0),     # Input Invert bit
)


"""Event Configuration Registers (R/W, `event_config_regs`)"""
const event_config_regs = adc_fpga_registers(Val(RW), 0x010) do
    (
        ch = BitGroup{RW}(
            ch1 = evt_cfg_chbits <<  0, # Ch. 1 bits
            ch2 = evt_cfg_chbits <<  8, # Ch. 2 bits
            ch3 = evt_cfg_chbits << 16, # Ch. 3 bits
            ch4 = evt_cfg_chbits << 24, # Ch. 4 bits
        ),
    )
end
export event_config_regs


# Not implemented: Extended Event configuration registers (0x109C, 0x209C, 0x309C, 0x409C)


"""Channel Header ID Registers (R/W, `channel_header_regs`)"""
const channel_header_regs = adc_fpga_registers(Val(RW), 0x014) do
    (
        id = BitRange{RW}(20:31),   # Channel Header/ID
    )
end
export channel_header_regs


"""End Address Threshold Registers (R/W, `address_threshold_regs`)"""
const address_threshold_regs = adc_fpga_registers(Val(RW), 0x018) do
    (
        stop_on_thresh      = Bit{RW}(31),          # "Suppress saving of more Hits/Events if Memory Address Threshold Flag is valid" Enable
        addr_thresh_value   = BitRange{RW}(0:23),   # End Address Threshold value, value range 1:0xff0000, value is number of 32-bit words
    )
end
export address_threshold_regs


"""Active Trigger Gate Window Length Registers (R/W, `trigger_gate_window_length_regs`)"""
const trigger_gate_window_length_regs = adc_fpga_registers(Val(RW), 0x01C) do
    (
        length  = BitRange{RW}(0:15),   # Active Trigger Gate Window Length (bit 0 not used)
    )
end
export trigger_gate_window_length_regs


"""
raw_data_buffer_config_regs

Raw Data Buffer Configuration Registers (R/W)

Note: Bit 0 of start_index and sample_length is always zero (since data is
stored in packets of 2 consecutive samples).
"""
const raw_data_buffer_config_regs = adc_fpga_registers(Val(RW), 0x020) do
    (
        sample_length   = BitRange{RW}(16:31),  # Raw Buffer Sample_Length
        start_index     = BitRange{RW}(0:15),   # Raw Buffer_Start_Index
    )
end
export raw_data_buffer_config_regs


"""
    pileup_config_regs

Pileup Configuration Registers (R/W)

Note: Bit 0 of repileup_win_len and pileup_win_len is always zero.
"""
const pileup_config_regs = adc_fpga_registers(Val(RW), 0x024) do
    (
        repileup_win_len    = BitRange{RW}(16:31),  # Re-Pileup Window Length
        pileup_win_len      = BitRange{RW}(0:15),   # Pileup Window Length
    )
end
export pileup_config_regs


"""
    pre_trigger_delay_regs

Pre-Trigger Delay Registers (R/W)

Note: Bit 0 of delay is always zero. Maximum value of delay is 2042 for ADC
FPGA firmware versions <= 0006 and 16378 for versions >= 0007.
"""
const pre_trigger_delay_regs = adc_fpga_registers(Val(RW), 0x028) do
(
    additional  = Bit{RW}(15),  # Additional Delay of Fir Trigger P+G Bit
    delay       = BitRange{RW}(0:13),   # Pretrigger Delay
)
end
export pre_trigger_delay_regs


"""
    average_configuration_regs

Average Configuration Registers (R/W)

Only present for SIS3316-16bit.

Note: Valid values for pretrig_delay are 0, 1, 2:4094. Valid values for
sample_len are 0, 2, 4, 6:65534 (bit 0 of sample_len) is always zero).
"""
const average_configuration_regs = adc_fpga_registers(Val(RW), 0x02C) do
(
    mode            = BitRange{RW}(28:30),  # Average Mode
    pretrig_delay   = BitRange{RW}(16:27),  # Average Pretrigger Delay
    sample_len      = BitRange{RW}(0:15),   # Average Sample Length
)
end
export average_configuration_regs


const dfmtcfg_bits = BitGroup{RW}(
    sel_test_buf      = Bit{RW}(5),  # Select Energy MAW Test Buffer
    save_mawvals   = Bit{RW}(4),  # Save MAW Test Buffer Enable
    save_energy       = Bit{RW}(3),  # Save Start Energy MAW value and Max. Energy MAW value
    save_ft_maw       = Bit{RW}(2),  # Save 3 x Fast Trigger MAW values (max value, value before Trigger, value with Trigger)
    save_acc_78       = Bit{RW}(1),  # Save 2 x Accumulator values (Gates 7,8)
    save_ph_acc16     = Bit{RW}(0),  # Save Peak High values and 6 x Accumulator values (Gates 1,2, ..,6)
)

"""
    dataformat_config_regs

Data Format Configuration Registers (R/W)

sel_test_buf value:

* 0 for FIR Trigger MAW selected
* 1 for FIR Energy MAW selected
"""
const dataformat_config_regs = adc_fpga_registers(Val(RW), 0x030) do
(
    ch = BitGroup{RW}(
        ch1 = dfmtcfg_bits <<  0,   # Ch. 1 bits
        ch2 = dfmtcfg_bits <<  8,   # Ch. 2 bits
        ch3 = dfmtcfg_bits << 16,   # Ch. 3 bits
        ch4 = dfmtcfg_bits << 24,   # Ch. 4 bits
    ),
)
end
export dataformat_config_regs


"""
    maw_test_buffer_config_regs

MAW Test Buffer Configuration Registers (R/W)

Note:

* Valid values for pretrig_delay: 2, 4, 6:1022.
* Valid values for buffer_len: 0, 2, 4, 6:1022.
* Bit 0 of pretrig_delay and buffer_len is always zero.
"""
const maw_test_buffer_config_regs = adc_fpga_registers(Val(RW), 0x034) do
    (
        pretrig_delay   = BitRange{RW}(16:25),  # MAW Test Buffer Pretrigger Delay
        buffer_len      = BitRange{RW}(0:10),   # MAW Test Buffer Length
    )
end
export maw_test_buffer_config_regs


const trigdelay_bits = BitGroup{RW}(
    delay   = BitRange{RW}(0:7),    # Internal Trigger Delay
)

"""
    internal_trigger_delay_config_regs

Internal Trigger Delay Configuration Registers (R/W)

Delay time is delay value multiplied by 2 clock cycles.
"""
const internal_trigger_delay_config_regs = adc_fpga_registers(Val(RW), 0x0038) do
    (
        ch = BitGroup{RW}(
            ch1 = trigdelay_bits <<  0, # Ch. 1 bits
            ch2 = trigdelay_bits <<  8, # Ch. 2 bits
            ch3 = trigdelay_bits << 16, # Ch. 3 bits
            ch4 = trigdelay_bits << 24, # Ch. 4 bits
        ),
    )
end
export internal_trigger_delay_config_regs


const gatelen_bits = BitGroup{RW}(
    gate2_en          = Bit{RW}(4),  # Gate 2 Enable
    gate1_en          = Bit{RW}(0),  # Gate 1 Enable
)

"""
internal_gate_length_config_regs

Internal Gate Length Configuration Registers (R/W)

Gate time is length value multiplied by 2 clock cycles.
"""
const internal_gate_length_config_regs = adc_fpga_registers(Val(RW), 0x03C) do
(
    ch = BitGroup{RW}(
        ch1 = gatelen_bits << 16,   # Ch. 1 bits
        ch2 = gatelen_bits << 17,   # Ch. 2 bits
        ch3 = gatelen_bits << 18,   # Ch. 3 bits
        ch4 = gatelen_bits << 19,   # Ch. 4 bits
    ),
    gate_len        = BitRange{RW}(8:15),   # Internal Gate Length
    coind_gate_len  = BitRange{RW}(0:7),    # Internal Coincidence Gate Length
)
end
export internal_gate_length_config_regs


fir_trigger_setup_register(addr::Unsigned) = Register{RW,RegVal}(
    MemAddr(addr),
    (
        nim_tp_len  = BitRange{RW}(24:31),  # External NIM Out Trigger Pulse Length (streched).
        gap_time    = BitRange{RW}(12:23),  # G: Gap time (Flat Time)
        peak_time   = BitRange{RW}( 0:11),  # P : Peaking time
    )
)

"""
    fir_trigger_setup_regs

FIR Trigger Setup Registers (R/W)

Note: Valid values for gap_time and peak_time: 2, 4, 6, ...., 510 (bit 0 of g
and p is not used). Valid values for nim_tp_len: 2, 4, 6, ...., 256.
"""
const fir_trigger_setup_regs = (
    ch01 = fir_trigger_setup_register(0x1040),
    ch02 = fir_trigger_setup_register(0x1050),
    ch03 = fir_trigger_setup_register(0x1060),
    ch04 = fir_trigger_setup_register(0x1070),

    ch05 = fir_trigger_setup_register(0x2040),
    ch06 = fir_trigger_setup_register(0x2050),
    ch07 = fir_trigger_setup_register(0x2060),
    ch08 = fir_trigger_setup_register(0x2070),

    ch09 = fir_trigger_setup_register(0x3040),
    ch10 = fir_trigger_setup_register(0x3050),
    ch11 = fir_trigger_setup_register(0x3060),
    ch12 = fir_trigger_setup_register(0x3070),

    ch13 = fir_trigger_setup_register(0x4040),
    ch14 = fir_trigger_setup_register(0x4050),
    ch15 = fir_trigger_setup_register(0x4060),
    ch16 = fir_trigger_setup_register(0x4070),
)
export fir_trigger_setup_regs

"""
    sum_fir_trigger_setup_regs

Sum FIR Trigger Setup Registers (R/W)

Note: Valid values for gap_time and peak_time: 2, 4, 6, ...., 510 (bit 0 of g
and p is not used). Valid values for nim_tp_len: 2, 4, 6, ...., 256.
"""
const sum_fir_trigger_setup_regs = (
    ch01_04 = fir_trigger_setup_register(0x1080),
    ch05_08 = fir_trigger_setup_register(0x2080),
    ch09_10 = fir_trigger_setup_register(0x3080),
    ch13_15 = fir_trigger_setup_register(0x4080),
)
export sum_fir_trigger_setup_regs


@enum CfdCtrl::UInt8 begin
    CFDDisabled     = 0     # CFD function disabled
    CFDDisabled_alt = 1     # CFD function disabled
    CFDZeroCross    = 2     # CFD function enabled with Zero crossing
    CDF50Percent    = 3     # CFD function enabled with 50 percent
end

export CfdCtrl, CFDDisabled, CFDDisabled_alt, CFDDisabled_alt, CDF50Percent

fir_trigger_threshold_register(addr::Unsigned) = Register{RW,RegVal}(
    MemAddr(addr),
    (
        trig_en         = Bit{RW}(31),  # Trigger enable
        high_e_suppr    = Bit{RW}(30),  # High Energy Suppress Trigger Mode
        cfd_ctrl        = BitRange{RW}(28:29, CfdCtrl), # CFD control bits
        threshold       = BitRange{RW}(0:27,linear_conv(offset = -signed(0x8000000))) # Trigger threshold value
    )
)

"""
    fir_trigger_threshold_regs

Trigger Threshold Registers (R/W)

Note: High energy suppression only works with CFD enabled.
"""
const fir_trigger_threshold_regs = (
    ch01 = fir_trigger_threshold_register(0x1044),
    ch02 = fir_trigger_threshold_register(0x1054),
    ch03 = fir_trigger_threshold_register(0x1064),
    ch04 = fir_trigger_threshold_register(0x1074),

    ch05 = fir_trigger_threshold_register(0x2044),
    ch06 = fir_trigger_threshold_register(0x2054),
    ch07 = fir_trigger_threshold_register(0x2064),
    ch08 = fir_trigger_threshold_register(0x2074),

    ch09 = fir_trigger_threshold_register(0x3044),
    ch10 = fir_trigger_threshold_register(0x3054),
    ch11 = fir_trigger_threshold_register(0x3064),
    ch12 = fir_trigger_threshold_register(0x3074),

    ch13 = fir_trigger_threshold_register(0x4044),
    ch14 = fir_trigger_threshold_register(0x4054),
    ch15 = fir_trigger_threshold_register(0x4064),
    ch16 = fir_trigger_threshold_register(0x4074),
)

export fir_trigger_threshold_regs

"""
    sum_fir_trigger_threshold_regs

Sum Trigger Threshold Registers (R/W)

Note: High energy suppression only works with CFD enabled.
"""
const sum_fir_trigger_threshold_regs = (
    ch01_04 = fir_trigger_threshold_register(0x1084),
    ch05_08 = fir_trigger_threshold_register(0x2084),
    ch09_10 = fir_trigger_threshold_register(0x3084),
    ch13_15 = fir_trigger_threshold_register(0x4084),
)
export sum_fir_trigger_threshold_regs



high_energy_threshold_register(addr::Unsigned) = Register{RW,RegVal}(
    MemAddr(addr),
    (
        trig_both_edges = Bit{RW}(31),          # Trigger on both edges enable bit
        trig_out        = Bit{RW}(28),          # High Energy stretched Trigger Out select bit
        threshold       = BitRange{RW}(0:27),   # High Energy Trigger Threshold value
    )
)

"""
    high_energy_threshold_regs

High Energy Trigger Threshold Registers (R/W)

`trig_both_edges` only available with firmware version “adc_fpga_V-0125-0004”
and higher, only works with CFD enabled.
"""
const high_energy_threshold_regs = (
    ch01 = high_energy_threshold_register(0x1048),
    ch02 = high_energy_threshold_register(0x1058),
    ch03 = high_energy_threshold_register(0x1068),
    ch04 = high_energy_threshold_register(0x1078),

    ch05 = high_energy_threshold_register(0x2048),
    ch06 = high_energy_threshold_register(0x2058),
    ch07 = high_energy_threshold_register(0x2068),
    ch08 = high_energy_threshold_register(0x2078),

    ch09 = high_energy_threshold_register(0x3048),
    ch10 = high_energy_threshold_register(0x3058),
    ch11 = high_energy_threshold_register(0x3068),
    ch12 = high_energy_threshold_register(0x3078),

    ch13 = high_energy_threshold_register(0x4048),
    ch14 = high_energy_threshold_register(0x4058),
    ch15 = high_energy_threshold_register(0x4068),
    ch16 = high_energy_threshold_register(0x4078),
)
export high_energy_threshold_regs

"""
    sum_high_energy_threshold_regs

Sum High Energy Trigger Threshold Registers (R/W)

Note: High energy suppression only works with CFD enabled.
"""
const sum_high_energy_threshold_regs = (
    ch01_04 = high_energy_threshold_register(0x1088),
    ch05_08 = high_energy_threshold_register(0x2088),
    ch09_10 = high_energy_threshold_register(0x3088),
    ch13_15 = high_energy_threshold_register(0x4088),
)
export sum_high_energy_threshold_regs


"""
    trigger_statistic_counter_regs

Trigger Statistic Counter Mode Registers (R/W)

* `update_mode value`:
    * 0: Readout of actual Trigger-Statistic-Counters
    * 1: Readout of the latched Trigger-Statistic-Counters (latch
        on bank switch)
"""
const trigger_statistic_counter_regs = adc_fpga_registers(Val(RW), 0x090) do
    (
        update_mode = Bit{RW}(0),   # Update Mode
    )
end
export trigger_statistic_counter_regs


"""
    peak_charge_configuration_regs

Peak/Charge Configuration Registers (R/W)

Valid values for bl_pregate_delay: 0, 2, 4, 6:510 (bit 0 is always zero).
"""
const peak_charge_configuration_regs = adc_fpga_registers(Val(RW), 0x094) do
(
    peak_charge_en      = Bit{RW}(31),          # Enable Peak/Charge Mode
    bl_avg_mode         = BitRange{RW}(28:29),  # Baseline Average Mode
    bl_pregate_delay    = BitRange{RW}(16:27),  # Baseline Pregate Delay
)
end
export peak_charge_configuration_regs


"""
    extended_raw_data_buffer_config_regs

Extended Raw Data Buffer Configuration Registers (R/W)

Maximum value of sample_len is (0x2000000 - 2), bit 0 is always zero.
"""
const extended_raw_data_buffer_config_regs = adc_fpga_registers(Val(RW), 0x098) do
    (
        sample_len  = BitRange{RW}(0:24),    # Extended Raw Buffer Sample Length
    )
end
export extended_raw_data_buffer_config_regs


accumulator_gate_config_registers(rel_addr::Unsigned) = adc_fpga_registers(Val(RW), rel_addr) do
    (
        gate_len    = BitRange{RW}(16:24, linear_conv(offset = 1)), # Gate Length
        gate_start  = BitRange{RW}(0:15),   # Gate Start Index (Address)
    )
end

"""
    accumulator_gate_config_regs

Accumulator Gate Configuration Registers (R/W)
"""
const accumulator_gate_config_regs = (
    gate1 = accumulator_gate_config_registers(0x0A0),
    gate2 = accumulator_gate_config_registers(0x0A4),
    gate3 = accumulator_gate_config_registers(0x0A8),
    gate4 = accumulator_gate_config_registers(0x0AC),
    gate5 = accumulator_gate_config_registers(0x0B0),
    gate6 = accumulator_gate_config_registers(0x0B4),
    gate7 = accumulator_gate_config_registers(0x0B8),
    gate8 = accumulator_gate_config_registers(0x0BC),
)
export accumulator_gate_config_regs



fir_energy_setup_register(addr::Unsigned) = Register{RW,RegVal}(
    MemAddr(addr),
    (
        tau_table       = BitRange{RW}(30:31),  # Tau table selection
        tau_factor      = BitRange{RW}(24:29),  # Tau factor
        extra_filter    = BitRange{RW}(22:23),  # Extra filter
        gap_time        = BitRange{RW}(12:21),  # G: Gap time (Flat Time)
        peak_time       = BitRange{RW}( 0:11),  # P : Peaking time
    )
)

"""
    fir_energy_setup_regs

FIR Energy Setup Registers (R/W)

Valid values:

    * tau_factor: 0, 1, 2, ...., 63
    * gap_time: 2, 4, 6, ...., 510 (bit 0 is not used)
    * peak_time: 2, 4, 6, ...., 2044 (bit 0 is not used)

Extra filter value:

    * 0: No extra filter
    * 1: Average of 4
    * 2: Average of 8
    * 3: Average of 16
"""
const fir_energy_setup_regs = (
    ch01 = fir_energy_setup_register(0x10c0),
    ch02 = fir_energy_setup_register(0x10c4),
    ch03 = fir_energy_setup_register(0x10c8),
    ch04 = fir_energy_setup_register(0x10cc),

    ch05 = fir_energy_setup_register(0x20c0),
    ch06 = fir_energy_setup_register(0x20c4),
    ch07 = fir_energy_setup_register(0x20c8),
    ch08 = fir_energy_setup_register(0x20cc),

    ch09 = fir_energy_setup_register(0x30c0),
    ch10 = fir_energy_setup_register(0x30c4),
    ch11 = fir_energy_setup_register(0x30c8),
    ch12 = fir_energy_setup_register(0x30cc),

    ch13 = fir_energy_setup_register(0x40c0),
    ch14 = fir_energy_setup_register(0x40c4),
    ch15 = fir_energy_setup_register(0x40c8),
    ch16 = fir_energy_setup_register(0x40cc),
)
export fir_energy_setup_regs


histogram_conf_register(addr::Unsigned) = Register{RW,RegVal}(
    MemAddr(addr),
    (
        mem_evt_write_dis   = Bit{RW}(31),          # Writing Hits/Events into Event Memory Disable bit
        clear_hist_w_ts     = Bit{RW}(30),          # Histogram clear with Timestamp-Clear Disable bit
        energy_div          = BitRange{RW}(16:27),  # Energy Divider (value = 0 is not allowed)
        energy_offs         = BitRange{RW}(8:11),   # Energy Subtract Offset
        pileup_en           = Bit{RW}(1),           # Pileup Enable bit
        hist_en             = Bit{RW}(0),           # Histogramming Enable bit
    )
)

"""
    histogram_conf_regs

Energy Histogram Configuration Registers (R/W)
"""
const histogram_conf_regs = (
    ch01 = histogram_conf_register(0x10d0),
    ch02 = histogram_conf_register(0x10d4),
    ch03 = histogram_conf_register(0x10d8),
    ch04 = histogram_conf_register(0x10dc),
    
    ch05 = histogram_conf_register(0x20d0),
    ch06 = histogram_conf_register(0x20d4),
    ch07 = histogram_conf_register(0x20d8),
    ch08 = histogram_conf_register(0x20dc),
    
    ch09 = histogram_conf_register(0x30d0),
    ch10 = histogram_conf_register(0x30d4),
    ch11 = histogram_conf_register(0x30d8),
    ch12 = histogram_conf_register(0x30dc),
    
    ch13 = histogram_conf_register(0x40d0),
    ch14 = histogram_conf_register(0x40d4),
    ch15 = histogram_conf_register(0x40d8),
    ch16 = histogram_conf_register(0x40dc),
)
export histogram_conf_regs


maw_start_energy_pickup_register(addr::Unsigned) = Register{RW,RegVal}(
    MemAddr(addr),
    (
        energy_pickup_idx   = BitRange{RW}(16:31),  # Energy Pickup Index
        maw_buf_start_idx   = BitRange{RW}(0:15),   # MAW Test Buffer Start Index
    )
)

"""
    maw_start_energy_pickup_regs

MAW Start Index and Energy Pickup Configuration Registers (R/W)
"""
const maw_start_energy_pickup_regs = (
    ch01 = maw_start_energy_pickup_register(0x10e0),
    ch02 = maw_start_energy_pickup_register(0x10e4),
    ch03 = maw_start_energy_pickup_register(0x10e8),
    ch04 = maw_start_energy_pickup_register(0x10ec),
    
    ch05 = maw_start_energy_pickup_register(0x20e0),
    ch06 = maw_start_energy_pickup_register(0x20e4),
    ch07 = maw_start_energy_pickup_register(0x20e8),
    ch08 = maw_start_energy_pickup_register(0x20ec),
    
    ch09 = maw_start_energy_pickup_register(0x30e0),
    ch10 = maw_start_energy_pickup_register(0x30e4),
    ch11 = maw_start_energy_pickup_register(0x30e8),
    ch12 = maw_start_energy_pickup_register(0x30ec),
    
    ch13 = maw_start_energy_pickup_register(0x40e0),
    ch14 = maw_start_energy_pickup_register(0x40e4),
    ch15 = maw_start_energy_pickup_register(0x40e8),
    ch16 = maw_start_energy_pickup_register(0x40ec),
)
export maw_start_energy_pickup_regs


"""
    firmware_version_regs

ADC FPGA Firmware Version Registers (R/W)

`fw_type` values:

    * 0x0125: 125 MHz 16-bit ADC
    * 0x0250: 250 MHz 14-bit ADC
"""
const firmware_version_regs = adc_fpga_registers(Val(RW), 0x100) do
    (
        fw_type     = BitRange{RO}(16:31),  # Firmware Type
        fw_version  = BitRange{RO}(8:15),   # Firmware Version
        fw_revision = BitRange{RO}(0:7),    # Firmware Revision
    )
end
export firmware_version_regs


"""
    adc_fpge_status_regs

ADC FPGA Status Registers (R/W)
"""
const adc_fpge_status_regs = adc_fpga_registers(Val(RW), 0x104) do
    (
        adc_clk_dcm_reset   = Bit{RO}(21),  # ADC-Clock DCM RESET flag
        adc_clk_dcm_ok      = Bit{RO}(20),  # ADC-Clock DCM OK flag
        mem2_ok             = Bit{RO}(17),  # Memory 2 OK flag (ch3 and ch4)
        mem1_ok             = Bit{RO}(16),  # Memory 1 OK flag (ch1 and ch2)
        link_speed_fl       = Bit{RO}(8),   # Data Link Speed flag
        vme_frame_err_la    = Bit{RO}(7),   # VME FPGA : Frame_error_latch
        vme_soft_err_la     = Bit{RO}(6),   # VME FPGA : Soft_error_latch
        vme_hard_err_la     = Bit{RO}(5),   # VME FPGA : Hard_error_latch
        vme_lane_up_fl      = Bit{RO}(4),   # VME FPGA : Lane_up_flag
        vme_ch_up_fl        = Bit{RO}(3),   # VME FPGA : Channel_up_flag
        vme_frame_err_fl    = Bit{RO}(2),   # VME FPGA : Frame_error_flag
        vme_soft_err_fl     = Bit{RO}(1),   # VME FPGA : Soft_error_flag
        vme_hard_err_fl     = Bit{RO}(0),   # VME FPGA : Hard_error_flag
    )
end
export adc_fpge_status_regs


sample_address_register(addr::Unsigned) = Register{RW,RegVal}(
    MemAddr(addr),
    (
        ch_offset   = Bit{RO}(25),  # Indicates the Channel Offset
        bank        = Bit{RO}(24, bool_val_conv(1, 2)),         # Indicates the Bank
        sample_addr = BitRange{RO}(0:23, word_byte_addr_conv),  # Actual Sample Address
    )
)

"""
    actual_sample_address_regs

Actual Sample Address Registers (R/W)
"""
const actual_sample_address_regs = (
    ch01 = sample_address_register(0x1110),
    ch02 = sample_address_register(0x1114),
    ch03 = sample_address_register(0x1118),
    ch04 = sample_address_register(0x111c),
    
    ch05 = sample_address_register(0x2110),
    ch06 = sample_address_register(0x2114),
    ch07 = sample_address_register(0x2118),
    ch08 = sample_address_register(0x211c),
    
    ch09 = sample_address_register(0x3110),
    ch10 = sample_address_register(0x3114),
    ch11 = sample_address_register(0x3118),
    ch12 = sample_address_register(0x311c),
    
    ch13 = sample_address_register(0x4110),
    ch14 = sample_address_register(0x4114),
    ch15 = sample_address_register(0x4118),
    ch16 = sample_address_register(0x411c),
)
export actual_sample_address_regs

"""
    previous_bank_sample_address_regs

Previous Bank Sample address Registers (R/W)
"""
const previous_bank_sample_address_regs = (
    ch01 = sample_address_register(0x1120),
    ch02 = sample_address_register(0x1124),
    ch03 = sample_address_register(0x1128),
    ch04 = sample_address_register(0x112c),
    
    ch05 = sample_address_register(0x2120),
    ch06 = sample_address_register(0x2124),
    ch07 = sample_address_register(0x2128),
    ch08 = sample_address_register(0x212c),
    
    ch09 = sample_address_register(0x3120),
    ch10 = sample_address_register(0x3124),
    ch11 = sample_address_register(0x3128),
    ch12 = sample_address_register(0x312c),
    
    ch13 = sample_address_register(0x4120),
    ch14 = sample_address_register(0x4124),
    ch15 = sample_address_register(0x4128),
    ch16 = sample_address_register(0x412c),
)
export previous_bank_sample_address_regs
