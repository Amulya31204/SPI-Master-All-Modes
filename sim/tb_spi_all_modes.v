`timescale 1ns / 1ps
module tb_spi_all_modes();

    reg        clk;
    reg        rst_n;
    reg        start;
    reg  [7:0] tx_data;
    reg  [1:0] mode_sel;

    wire [7:0] rx_data [0:3];
    wire       busy    [0:3];
    wire       done    [0:3];
    wire       cs_n    [0:3];
    wire       sclk    [0:3];
    wire       mosi    [0:3];
    reg        miso    [0:3];

    genvar g;
    generate
        for (g = 0; g < 4; g = g + 1) begin : dut
            spi_controller_all_modes #(.MODE(g)) uut (
                .clk(clk), .rst_n(rst_n),
                .start(start && (mode_sel == g)),
                .tx_data(tx_data), .rx_data(rx_data[g]),
                .busy(busy[g]), .done(done[g]),
                .sclk(sclk[g]), .mosi(mosi[g]),
                .miso(miso[g]), .cs_n(cs_n[g])
            );
        end
    endgenerate

    // ── System-clock-based slave (no async edges) ─────────────────────────────
    integer m;
    reg [7:0] slave_sr   [0:3];
    reg [3:0] slave_cnt  [0:3];
    reg       sclk_prev  [0:3];
    reg       cs_n_prev  [0:3];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (m = 0; m < 4; m = m + 1) begin
                miso[m]      <= 0;
                slave_sr[m]  <= 0;
                slave_cnt[m] <= 0;
                sclk_prev[m] <= m[1];
                cs_n_prev[m] <= 1;
            end
        end else begin
            for (m = 0; m < 4; m = m + 1) begin
                sclk_prev[m] <= sclk[m];
                cs_n_prev[m] <= cs_n[m];

                // CS asserted
                if (cs_n_prev[m] && !cs_n[m]) begin
                    slave_sr[m]  <= tx_data;
                    slave_cnt[m] <= 0;
                    miso[m]      <= (m[0] == 0) ? tx_data[7] : 1'b0;
                end
                // CS deasserted
                else if (!cs_n_prev[m] && cs_n[m]) begin
                    miso[m] <= 0;
                end
                else if (!cs_n[m]) begin
                    case (m)
                        0: if (sclk_prev[0] && !sclk[0]) begin  // negedge = trailing
                            slave_sr[0]  <= {slave_sr[0][6:0], 1'b0};
                            slave_cnt[0] <= slave_cnt[0] + 1;
                            miso[0]      <= slave_sr[0][6];
                        end
                        1: if (!sclk_prev[1] && sclk[1]) begin  // posedge = leading
                            miso[1]      <= slave_sr[1][7];
                            slave_sr[1]  <= {slave_sr[1][6:0], 1'b0};
                            slave_cnt[1] <= slave_cnt[1] + 1;
                        end
                        2: if (!sclk_prev[2] && sclk[2]) begin  // posedge = trailing
                            slave_sr[2]  <= {slave_sr[2][6:0], 1'b0};
                            slave_cnt[2] <= slave_cnt[2] + 1;
                            miso[2]      <= slave_sr[2][6];
                        end
                        3: if (sclk_prev[3] && !sclk[3]) begin  // negedge = leading
                            miso[3]      <= slave_sr[3][7];
                            slave_sr[3]  <= {slave_sr[3][6:0], 1'b0};
                            slave_cnt[3] <= slave_cnt[3] + 1;
                        end
                    endcase
                end
            end
        end
    end

    // ── Clock ─────────────────────────────────────────────────────────────────
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // ── Transfer task ─────────────────────────────────────────────────────────
    task spi_transfer_mode;
        input [1:0] mode;
        input [7:0] data;
        begin
            @(posedge clk); #1;
            tx_data  = data;
            mode_sel = mode;
            start    = 1;
            @(posedge clk); #1;
            start = 0;
            @(posedge done[mode]);
            @(posedge clk); #1;
        end
    endtask

    // ── Results ───────────────────────────────────────────────────────────────
    integer pass_count;
    integer fail_count;

    task check;
        input [1:0] mode;
        input [7:0] tx;
        input [7:0] rx;
        input [7:0] expected;
        begin
            if (rx == expected) begin
                $display("  Mode%0d  TX=%02h  RX=%02h  PASS", mode, tx, rx);
                pass_count = pass_count + 1;
            end else begin
                $display("  Mode%0d  TX=%02h  RX=%02h  FAIL (expected %02h)",
                          mode, tx, rx, expected);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // ── Stimulus ──────────────────────────────────────────────────────────────
    integer i;
    reg [7:0] test_vec [0:3];

    initial begin
        pass_count  = 0;
        fail_count  = 0;
        rst_n       = 0;
        start       = 0;
        mode_sel    = 0;
        tx_data     = 0;
        test_vec[0] = 8'hA5;
        test_vec[1] = 8'h5A;
        test_vec[2] = 8'hFF;
        test_vec[3] = 8'h00;

        repeat(6) @(posedge clk);
        rst_n = 1;
        repeat(2) @(posedge clk);

        for (i = 0; i < 4; i = i + 1) begin
            $display("--- Mode %0d (CPOL=%0b CPHA=%0b) ---", i, i[1], i[0]);

            spi_transfer_mode(i[1:0], test_vec[0]);
            check(i[1:0], test_vec[0], rx_data[i], test_vec[0]);
            repeat(2) @(posedge clk);

            spi_transfer_mode(i[1:0], test_vec[1]);
            check(i[1:0], test_vec[1], rx_data[i], test_vec[1]);
            repeat(2) @(posedge clk);

            spi_transfer_mode(i[1:0], test_vec[2]);
            check(i[1:0], test_vec[2], rx_data[i], test_vec[2]);
            repeat(2) @(posedge clk);

            spi_transfer_mode(i[1:0], test_vec[3]);
            check(i[1:0], test_vec[3], rx_data[i], test_vec[3]);
            repeat(2) @(posedge clk);
        end

        $display("================================");
        $display("TOTAL: %0d PASS, %0d FAIL", pass_count, fail_count);
        $display("================================");
        $finish;
    end

endmodule
