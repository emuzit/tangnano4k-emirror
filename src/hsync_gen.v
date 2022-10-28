// =============================================================================
// Module description
//
//   Generate missing HSYNC from OV5640's VSYNC/HREF DVP output.
//
// Author  : github @emuzit
// License : MIT
// =============================================================================

module hsync_gen #(
    parameter
        HCOUNT_BITS = 12,
        HCOUNT_HS_SET = 1280 + 110,
        HCOUNT_HS_CLR = HCOUNT_HS_SET + 40
    ) (
    input       reset,
    input       pixclk,
    input       vsync,
    input       href,
    output reg  o_hsync
    );

    localparam
        HCOUNT_MAX = {HCOUNT_BITS{1'b1}};

    reg  [HCOUNT_BITS-1:0] hs_counter;
    reg  [HCOUNT_BITS-1:0] hc_end_count;

    reg  href_d1, first_hlpulse, mismatch_toggle;

    always @(negedge pixclk)
        href_d1 <= href;

    wire
        href_leading_pulse = href && !href_d1;

    //     pixclk  __/--\__/--\__/--\__/--\__
    //       href  _____/--------------------
    //    href_d1  ___________/--------------
    // hs_counter  YYYYYZZZZZZ000000111111222

    always @(negedge pixclk or posedge reset) begin
        if (reset)
            hs_counter <= 0;
        else if (href_leading_pulse)
            hs_counter <= 0;
        else if (hs_counter == hc_end_count)
            hs_counter <= 0;
        else
            hs_counter <= hs_counter + 1;

        // get hc_end_count from first line (should be the same for all lines)

        if (reset)
            first_hlpulse <= 1'b1;
        else if (vsync)
            first_hlpulse <= 1'b1;
        else if (href_leading_pulse)
            first_hlpulse <= 1'b0;

        if (reset)
            hc_end_count <= HCOUNT_MAX;
        else if (href_leading_pulse) begin
            if (first_hlpulse)
                hc_end_count <= HCOUNT_MAX;
            else if (hc_end_count == HCOUNT_MAX)
                hc_end_count <= hs_counter;
        end

        // Improper setting makes h_total wabbling, this is for the check
        if (reset)
            mismatch_toggle <= 1'b0;
        else if (href_leading_pulse && hs_counter != hc_end_count)
            mismatch_toggle <= ~mismatch_toggle;

        if (reset)
            o_hsync <= 1'b0;
        else if (href)
            o_hsync <= 1'b0;
        else if (hs_counter == HCOUNT_HS_SET)
            o_hsync <= 1'b1;
        else if (hs_counter == HCOUNT_HS_CLR)
            o_hsync <= 1'b0;
    end

endmodule