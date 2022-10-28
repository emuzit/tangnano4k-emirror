// =============================================================================
// Project tangnano4k-emirror
//
//   A zero-delay mirrored video display with Sipeed Tang Nano-4K + OV5640
//
// Author  : github @emuzit
// License : MIT
// =============================================================================

module emirror_top (
    input           KEY1_RST_N,
    input           SYS_CLK,        // 27Mhz
    output          MODE,           // LED (high to lite)
    output          PIN13_IOB4A,    // probed signal output
    inout           CAMERA_SDA,
    inout           CAMERA_SCL,
    input           DVP_VSYNC,      // active high
    input           DVP_HSYNC,      // active high (DE actually)
    input   [9:0]   PIXDATA,
    input           DVP_PCLK,
    output          DVP_XCLK,       // 12MHz output to OV5640
    output          HDMI_TXC_p,
    output          HDMI_TXC_n,
    output  [2:0]   HDMI_TX_p,      // {R,G,B}
    output  [2:0]   HDMI_TX_n
    );

    reg  [9:0]  pixdata_d1;
    reg  [9:0]  pixdata_n1;
    reg  [15:0] camdata_tog1;

    reg  px2_clk;
    reg  px2_vsync;
    reg  px2_href;
    reg  px2_in_phase;

    reg  href_d1;
    reg  href_adjust;
    reg  href_pixtog;

    wire
        PIXCLK = DVP_PCLK,
        reset = ~KEY1_RST_N;

    //  PIXCLK  __/--\__/--\__/--\__/--\__  --\__/--\__/--\__/--\__
    //    HREF  _____/--------------------  --------------\________
    // PIXDATA  xxxxxx=====x=====x=====x==  ==x=====x=====xxxxxxxxx
    //  pixtog  00000000011111100000011111  00000011111100000000000
    // px2_clk  __/-----\_____/-----\_____  -----\_____/-----\_____ (expected)
    // px2_clk  --\_____/-----\_____/-----  _____/-----\_____/----- (well....)

    always @(posedge PIXCLK)  pixdata_d1 <= PIXDATA;
    always @(negedge PIXCLK)  pixdata_n1 <= pixdata_d1;

    wire [15:0]
        rgb565 = {pixdata_n1[9:5], pixdata_n1[4:2], PIXDATA[9:7], PIXDATA[6:2]},
        camdata = px2_in_phase? rgb565 : camdata_tog1;

    always @(posedge PIXCLK) begin
        href_d1 <= DVP_HSYNC;
        if (DVP_HSYNC && !href_d1)
            px2_in_phase <= px2_clk;

        href_pixtog <= DVP_HSYNC? ~href_pixtog : 1'b0;

        // for unexpected out of phase px2_clk, delay rgb565 by 1 PIXCLK
        if (href_pixtog)
            camdata_tog1 <= rgb565;
    end

    always @(posedge PIXCLK or posedge reset) begin
        // first DVP_HSYNC to adjust phase of px2_clk
        if (reset)
            href_adjust <= 1'b0;
        else if (DVP_HSYNC)
            href_adjust <= 1'b1;

        // divide PIXCLK by 2 for packed pixel clock
        if (reset)
            px2_clk <= 1'b0;
        else if (DVP_HSYNC && !href_adjust)
            px2_clk <= 1'b0;
        else
            px2_clk <= ~px2_clk;
    end

    wire
        PX2_CLK = px2_clk;  // may need to feed to clock driver ?

    always @(negedge PX2_CLK)
        {px2_vsync, px2_href} <= {DVP_VSYNC, DVP_HSYNC};

	// *****************************
	// LED PWM output, 16 levels
	// *****************************

    reg  [25:0] led_counter;

    reg  pwm_out;

    assign
        MODE = pwm_out;

    always @(posedge SYS_CLK) begin
        if (led_counter[25])
            pwm_out <= led_counter[16:13] > led_counter[24:21];
        else
            pwm_out <= led_counter[16:13] <= led_counter[24:21];
    end

    always @(posedge SYS_CLK or posedge reset) begin
        if (reset)
            led_counter <= 0;
        else
            led_counter <= led_counter + 1;
    end

	// *****************************
	// 12MHz DVP_XCLK for OV5640
	// *****************************

    wire
        clk_12M = DVP_XCLK;

    CLK12M_PLLVR u_dvp_xclk (
        .clkout (DVP_XCLK),
        .clkin  (SYS_CLK)
    );

	// *****************************
	// OV5640 camera configuration
	// *****************************

    wire sda_o, scl_o;

    assign
        CAMERA_SDA = sda_o? 1'bz : 1'b0,
        CAMERA_SCL = scl_o? 1'bz : 1'b0;

    ovcam_config  u_ovcam (
        .reset    (reset),
        .clk      (clk_12M),
        .finished (),
        .sda_o    (sda_o),
        .scl_o    (scl_o)
    );

	// *****************************
	// DVP direct to DVI_TX module
	// *****************************

    // Use of Video Frame Buffer introduces extra delay. It's best we
    // make the timing of OV5640 suitable for DVI TX module directly.
    // See ovcam_config.v for register setting.

    hsync_gen u_dvi_hs (
        .reset      (reset),
        .pixclk     (PX2_CLK),
        .vsync      (px2_vsync),
        .href       (px2_href),
        .o_hsync    (I_rgb_hs)
    );

    wire [7:0]
        I_rgb_r = {camdata[15:11], 3'b0},
        I_rgb_g = {camdata[10:5], 2'b0},
        I_rgb_b = {camdata[4:0], 3'b0};

	DVI_TX_Top u_dvi_tx (
		.I_rst_n        (~reset),
		.I_rgb_clk      (PX2_CLK),
		.I_rgb_vs       (px2_vsync),
		.I_rgb_hs       (I_rgb_hs),
		.I_rgb_de       (px2_href),
		.I_rgb_r        (I_rgb_r),
		.I_rgb_g        (I_rgb_g),
		.I_rgb_b        (I_rgb_b),
		.O_tmds_clk_p   (HDMI_TXC_p),
		.O_tmds_clk_n   (HDMI_TXC_n),
		.O_tmds_data_p  (HDMI_TX_p),
		.O_tmds_data_n  (HDMI_TX_n)
	);

	// *****************************
	// debug output
	// *****************************

    localparam
        PIN13_OSEL = 0;

    reg [3:0] pxdiv;

    always @(posedge PIXCLK)
        pxdiv <= pxdiv + 1;

    // routed to PIN13_IOB4A output for observation

    assign PIN13_IOB4A =
        (PIN13_OSEL == 0) && u_dvi_hs.mismatch_toggle ||
        (PIN13_OSEL == 1) && pxdiv[3] ||
        (PIN13_OSEL == 2) && I_rgb_hs;

endmodule