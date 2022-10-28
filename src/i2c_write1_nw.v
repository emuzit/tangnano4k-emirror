// =============================================================================
// Module description
//
//   Generate one-data-byte I2C write (ACK ignored, SCL stretching not allowed).
//
// Author  : github @emuzit
// License : MIT
// =============================================================================

module i2c_write1_nw #(
    parameter
        TARGET_ID = 8'ha0,
        REGI_MSB = 7,
        CLKDIV_MSB = 7
    ) (
    input               reset,
    input               clk,       // 2^n x SCL (n > 2, default 25MHz)
    input  [REGI_MSB:0] regi,      // index of register to write
    input  [7:0]        regv,      // value of register to write
    input               start,     // 1 to start transaction
    output reg          done,      // transaction done
    output reg          sda_o,     // 0/1 => SDA 0/HiZ
    output reg          scl_o      // 0/1 => SCL 0/HiZ
    );

    localparam
        SDAOSR_MSB = (REGI_MSB == 7)? 29 : 38;

    reg  sda_x;

    reg  [CLKDIV_MSB:0] divider;
    reg  [SDAOSR_MSB:0] sdao_sr;

    reg  [5:0]  bit_position;

    wire [7:0]  tid = TARGET_ID & 8'hfe;

    always @(posedge clk) begin
        // default i2c clock : 25MHz / 256 --> ~97KHz
        divider <= (bit_position > SDAOSR_MSB)? {(CLKDIV_MSB+1){1'b1}} : divider - 1;
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            sdao_sr[SDAOSR_MSB] <= 1'b1;
            bit_position <= 63;
        end
        else if (bit_position > SDAOSR_MSB) begin
            if (start) begin
                bit_position <= SDAOSR_MSB;
                done <= 1'b0;
                if (REGI_MSB == 7)
                    // load {IdleGap, START, {3{DataByte, HiZ_ACK}}, STOP}
                    sdao_sr <= {2'b10, tid, 1'b1, regi[7:0], 1'b1, regv, 1'b1, 1'b0};
                else
                    // load {IdleGap, START, {4{DataByte, HiZ_ACK}}, STOP}
                    sdao_sr <= {2'b10, tid, 1'b1, regi[15:8], 1'b1, regi[7:0], 1'b1, regv, 1'b1, 1'b0};
            end
        end
        else if (divider == 0) begin
            // bit_position 0 -> 63 => transaction done
            bit_position <= bit_position - 1;
            done <= (bit_position == 0);
            // sdao_sr : shift left, all ones when transaction done
            sdao_sr <= {sdao_sr[(SDAOSR_MSB-1):0], 1'b1};
        end

        if (reset)
            {sda_x, sda_o, scl_o} = {1'b1, 1'b1, 1'b1};
        else begin
            // make sda_o 1 clk behind scl_o for hold time
            sda_x <= sdao_sr[SDAOSR_MSB];
            sda_o <= sda_x;
            // note : scl kept inactive during gap/start bit period
            scl_o <= ~(divider[CLKDIV_MSB] && (bit_position < SDAOSR_MSB - 1));
        end
    end

endmodule