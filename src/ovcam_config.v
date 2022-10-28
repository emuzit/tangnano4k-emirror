// =============================================================================
// Module description
//
//   Configure an OmniVision image sensor with data stored in a Gowin_pROM.
//
// Author  : github @emuzit
// License : MIT
// =============================================================================

module ovcam_config #(
    parameter
        SCCB_ID = 8'h78,
        TWO_BYTE_ADDRESS = 1,
        INIT_PAUSE = 500000
    ) (
    input  reset,
    input  clk,             // 2^n x SCL (n > 2, default 25MHz)
    output finished,        // config done
    output sda_o,           // 0/1 => SDA 0/HiZ
    output scl_o            // 0/1 => SCL 0/HiZ
    );

    localparam
        SCCB_OV2640 = 8'h60,  // one-byte address
        SCCB_OV5640 = 8'h78;  // two-byte address

    localparam
        REGI_MSB = TWO_BYTE_ADDRESS? 15 : 7;

    localparam
        CMD_TRANS    = 4'b0000,
        CMD_WIP      = 4'b0001,
        CMD_START    = 4'b0010,
        CMD_ADVANCE  = 4'b0100,
        CMD_ADV2     = 4'b0101,
        CMD_FINISHED = 4'b1000;

    reg  [3:0]  cstate;
    reg  [8:0]  address;

    reg  [21:0] delay_counter;
    reg  [15:0] idxword;
    wire [15:0] dout;
    wire [7:0]  regv;

    wire [REGI_MSB:0] regi;

    reg  init_delay_done;
    reg  cmd_delay_done;
    reg  need_cmd_delay;

    wire
        start    = cstate[1],
        advance  = cstate[2];

    assign
        finished = cstate[3];

    // one-byte-address => index at high byte, regv at low byte
    // two-byte-address => index at 1st word, regv at low byte of 2nd word

    assign
        regi = TWO_BYTE_ADDRESS? idxword : dout[15:8],
        regv = dout[7:0];

    wire
        cmd_soft_reset = (idxword == 16'h3008 && regv[7]);

    always @(posedge clk) begin
        // need 5ms delay for software reset
        need_cmd_delay <= (SCCB_ID == SCCB_OV5640 && cmd_soft_reset);
        cmd_delay_done <= !need_cmd_delay || (delay_counter > INIT_PAUSE/4);
    end

    always @(posedge clk or posedge reset) begin
        // 20ms@25MHz delay before SCCB config begins
        if (reset)
            init_delay_done <= 1'b0;
        else if (delay_counter == INIT_PAUSE)
            init_delay_done <= 1'b1;

        // used for both initial config delay & soft reset cmd
        if (reset)
            delay_counter <= 0;
        else if (start)
            delay_counter <= 0;
        else if (!init_delay_done || need_cmd_delay)
            delay_counter <= delay_counter + 1;
    end

    always @(posedge clk)
        if (TWO_BYTE_ADDRESS && cstate == CMD_TRANS)
            idxword <= dout;

    always @(posedge clk) begin
        if (!init_delay_done)
            cstate <= TWO_BYTE_ADDRESS? CMD_ADV2 : CMD_TRANS;
        else begin
            case (cstate)
                CMD_TRANS :
                    // Gowin_pROM data ends when 16'hffff encountered
                    cstate <= (dout == 16'hffff)? CMD_FINISHED : CMD_START;
                CMD_START :
                    cstate <= CMD_WIP;
                CMD_WIP :
                    if (done && cmd_delay_done) cstate <= CMD_ADVANCE;
                CMD_ADVANCE :
                    cstate <= TWO_BYTE_ADDRESS? CMD_ADV2 : CMD_TRANS;
                CMD_ADV2 :
                    cstate <= CMD_TRANS;
                default :
                    cstate <= CMD_FINISHED;
            endcase
        end

        if (!init_delay_done)
            address <= 0;
        else if (advance && !finished)
            address <= address + 1;
    end

    // Ref : OV5640_AF_Imaging_Module_Application_Guide_(DVP_Interface)
    //
    // For 720p30 RGB565, change the following registers from default setting :
    //
    //   0x4740 : 0x20    (not changed)
    //   0x4300 : 0x61    FORMAT RGB565
    //   0x501f : 0x01    ISP RGB
    //   0x3035 : 0x21    (not changed)
    //   0x3036 : 0xd2    XCLK is 12MHz instead of 24MHz
    //   0x3820 : 0x47    ISP vflip on
    //   0x3821 : 0x07    ISP mirror on
    //
    // One frame is 1892x740 (see registers 0x380c ~ 0x380f). Measured timing :
    //   DVP_PCLK  - around 84MHz => RGB565 pixclk ~42MHz
    //   DVP_VSYNC - around 30.00Hz, Front/Width/Back 398.59/90.11/502.39 uS
    //   DVP_HSYNC - around 22.20KHz, pulse_width/period 30.48uS/45.05uS
    //
    // There are problems for this :
    //   * most HDMI monitors does not accept 30Hz vsync
    //   * vesa 720p frame format is 1650x750
    //   * for 720p60, DVP_PCLK will be 168MHz,
    //     which exceeds 150MHz IO Max. Frequency of GW1NSR chips
    //
    // Further reg change for 1650x750 60fps, and measure the timing :
    //
    //   0x3034 : 0x18    MIPI 10-bit mode may make pixclk/h_total wabble
    //   0x3035 : 0x11
    //   0x3036 : 0x63    12MHz / 4 * 99 ==> 148.5MHz * 2
    //   0x3037 : 0x04    bypass PLL root divider
    //   0x380c : 0x06
    //   0x380d : 0x72    0x0672 --> 1650
    //   0x380e : 0x02
    //   0x380f : 0xee    0x02ee --> 750
    //
    //   DVP_PCLK  - around (9.09~10.00)x16 MHz, likely 148.5MHz
    //   DVP_VSYNC - around 60.00Hz, Front/Width/Back 155.24/44.46/467.29 uS
    //   DVP_HSYNC - around 45.00KHz, pulse_width/period 17.24uS/22.22uS
    //
    // Notably reg 0x3034 should be set to MIPI 8-bit mode, otherwise pixclk
    // and h_total wabble easily for improper PLL setting.

    Gowin_pROM u_prom_ov (
        .clk    (clk),
        .reset  (reset),
        .ce     (~finished),
        .oce    (~finished),
        .ad     (address),
        .dout   (dout)
    );

    i2c_write1_nw #(
        .TARGET_ID (SCCB_ID),
        .REGI_MSB (REGI_MSB)
    ) u_i2c_ov (
        .reset  (reset),
        .clk    (clk),
        .regi   (regi),     // index of register to write
        .regv   (regv),     // value of register to write
        .start  (start),    // 1 to start transaction
        .done   (done),     // transaction done
        .sda_o  (sda_o),    // 0/1 => SDA 0/HiZ
        .scl_o  (scl_o)     // 0/1 => SCL 0/HiZ
    );

endmodule