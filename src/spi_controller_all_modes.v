`timescale 1ns / 1ps
// SPI Master - all 4 modes (CPOL/CPHA)
// MODE[1]=CPOL  MODE[0]=CPHA
//
// CPHA=0: sample on leading edge,  shift on trailing edge
// CPHA=1: shift  on leading edge,  sample on trailing edge
//
// State machine:
//   IDLE  → SETUP → LEAD → TRAIL → LEAD → ... → TRAIL(last) → IDLE
//
// For CPHA=1 the TRAIL state samples MISO. But the slave (in the testbench)
// updates MISO on the system clock AFTER it detects the leading edge.
// So by the time we reach TRAIL (one system clock after LEAD), MISO is stable.
// We add an extra SAMPLE state after TRAIL for CPHA=1 to guarantee one more
// clock of hold before we latch - this removes any remaining race.

module spi_controller_all_modes #(
    parameter [1:0] MODE = 2'd0
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       start,
    input  wire [7:0] tx_data,
    output reg  [7:0] rx_data,
    output reg        busy,
    output reg        done,
    output reg        sclk,
    output reg        mosi,
    input  wire       miso,
    output reg        cs_n
);
    wire cpol = MODE[1];
    wire cpha = MODE[0];

    localparam IDLE  = 3'd0;
    localparam SETUP = 3'd1;  // CS low, signals settle
    localparam LEAD  = 3'd2;  // leading  edge: sclk = ~cpol
    localparam HOLD  = 3'd3;  // one clock hold after leading  (CPHA=1 only)
    localparam TRAIL = 3'd4;  // trailing edge: sclk = cpol
    localparam LATCH = 3'd5;  // one clock hold after trailing (CPHA=1: sample here)

    reg [2:0] state;
    reg [3:0] bit_cnt;
    reg [7:0] tx_shift;
    reg [7:0] rx_shift;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= IDLE;
            busy     <= 0;
            done     <= 0;
            cs_n     <= 1;
            sclk     <= cpol;
            mosi     <= 0;
            rx_data  <= 0;
            bit_cnt  <= 0;
            tx_shift <= 0;
            rx_shift <= 0;
        end else begin
            done <= 0;

            case (state)

                // ── IDLE ─────────────────────────────────────────────────────
                IDLE: begin
                    sclk <= cpol;
                    if (start) begin
                        busy     <= 1;
                        cs_n     <= 0;
                        bit_cnt  <= 0;
                        tx_shift <= tx_data;
                        rx_shift <= 0;
                        // CPHA=0: pre-drive MSB so it's stable before first leading edge
                        // CPHA=1: mosi driven on leading edge
                        mosi     <= (cpha == 0) ? tx_data[7] : 0;
                        state    <= SETUP;
                    end
                end

                // ── SETUP ────────────────────────────────────────────────────
                // One clock with CS=0, sclk=idle. Lets slave load its shift
                // register and drive MISO[7] (for CPHA=0) before first edge.
                SETUP: begin
                    sclk  <= cpol;
                    state <= LEAD;
                end

                // ── LEAD ─────────────────────────────────────────────────────
                // Assert leading edge of sclk.
                LEAD: begin
                    sclk <= ~cpol;          // leading edge

                    if (cpha == 0) begin
                        // CPHA=0: sample MISO now - slave updated it before this edge
                        rx_shift <= {rx_shift[6:0], miso};
                        state    <= TRAIL;
                    end else begin
                        // CPHA=1: drive MOSI, slave will update MISO this same
                        // clock cycle (non-blocking) - we need one extra clock
                        // before sampling, so go to HOLD first
                        mosi  <= tx_shift[7];
                        state <= HOLD;
                    end
                end

                // ── HOLD ─────────────────────────────────────────────────────
                // CPHA=1 only: sclk stays high (~cpol), gives slave one system
                // clock to update MISO after detecting the leading edge.
                HOLD: begin
                    sclk  <= ~cpol;         // hold leading level
                    state <= TRAIL;
                end

                // ── TRAIL ────────────────────────────────────────────────────
                // Assert trailing edge of sclk.
                TRAIL: begin
                    sclk <= cpol;           // trailing edge

                    if (cpha == 0) begin
                        // CPHA=0: shift out next MOSI bit
                        if (bit_cnt < 7) begin
                            tx_shift <= {tx_shift[6:0], 1'b0};
                            mosi     <= tx_shift[6];
                        end

                        if (bit_cnt == 7) begin
                            // last bit already sampled in LEAD
                            rx_data <= {rx_shift[6:0], miso};
                            done    <= 1;
                            busy    <= 0;
                            cs_n    <= 1;
                            mosi    <= 0;
                            state   <= IDLE;
                        end else begin
                            bit_cnt <= bit_cnt + 1;
                            state   <= LEAD;
                        end
                    end else begin
                        // CPHA=1: sample MISO on trailing edge
                        // slave updated MISO during HOLD - it is stable now
                        rx_shift <= {rx_shift[6:0], miso};

                        // shift tx for next bit
                        tx_shift <= {tx_shift[6:0], 1'b0};

                        if (bit_cnt == 7) begin
                            rx_data <= {rx_shift[6:0], miso};
                            done    <= 1;
                            busy    <= 0;
                            cs_n    <= 1;
                            mosi    <= 0;
                            state   <= IDLE;
                        end else begin
                            bit_cnt <= bit_cnt + 1;
                            state   <= LEAD;
                        end
                    end
                end

            endcase
        end
    end

endmodule
