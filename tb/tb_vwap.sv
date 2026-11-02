// tb_vwap.sv — self-checking testbench for the VWAP datapath.
//
// Strategy:
//  * Drive randomized (price,size) beats with random tvalid gaps.
//  * A reference model (SV queue) maintains the same sliding window and the
//    golden rolling sums; a monitor checks dut.sum_ps / dut.sum_sz on every
//    accumulator-valid beat (validates multiply + windowed accumulate).
//  * A second monitor snapshots the dividend/divisor each time the divider
//    starts and checks the quotient when it finishes (validates the divide).
//  * The output is consumed with random back-pressure; SVA asserts the AXIS
//    rule that tdata/tvalid are stable while tvalid && !tready.
`timescale 1ns/1ps
import vwap_pkg::*;

module tb_vwap;
    localparam real CLK_NS = 10.0;

    logic clk = 0, rst = 1;
    always #(CLK_NS/2.0) clk = ~clk;

    // DUT I/O
    logic [PRICE_W-1:0] s_price;
    logic [SIZE_W-1:0]  s_size;
    logic               s_tvalid, s_tready;
    logic [VWAP_W-1:0]  m_vwap;
    logic               m_tvalid, m_tready;
    logic [15:0]        latency_cycles;
    logic               div0;

    vwap_top dut (
        .clk, .rst,
        .s_price, .s_size, .s_axis_tvalid(s_tvalid), .s_axis_tready(s_tready),
        .m_vwap, .m_axis_tvalid(m_tvalid), .m_axis_tready(m_tready),
        .latency_cycles, .div0
    );

    int errors = 0;
    int n_sum_checks = 0, n_div_checks = 0;

    // ---------------- reference model: rolling window ----------------
    logic [PROD_W-1:0] ref_ps[$];
    logic [SIZE_W-1:0] ref_sz[$];
    // records driven, consumed in order by the accumulator monitor
    logic [PRICE_W-1:0] drv_price[$];
    logic [SIZE_W-1:0]  drv_size[$];

    // ---------------- stimulus ----------------
    task automatic drive_beat(input logic [PRICE_W-1:0] p, input logic [SIZE_W-1:0] s);
        s_price  <= p;
        s_size   <= s;
        s_tvalid <= 1'b1;
        @(posedge clk iff s_tready);   // accepted on this edge
        drv_price.push_back(p);
        drv_size.push_back(s);
        s_tvalid <= 1'b0;
    endtask

    // ---------------- accumulator monitor (checks sums) ----------------
    // When acc_valid is high, dut.sum_ps/sum_sz reflect one more record; pop the
    // next driven record, update the golden window, compare.
    always @(posedge clk) begin
        if (!rst && dut.u_acc.out_valid) begin
            automatic logic [PRICE_W-1:0] p = drv_price.pop_front();
            automatic logic [SIZE_W-1:0]  s = drv_size.pop_front();
            automatic longint unsigned eps = 0, esz = 0;
            ref_ps.push_back(p * s);
            ref_sz.push_back(s);
            if (ref_ps.size() > WIN) begin ref_ps.pop_front(); ref_sz.pop_front(); end
            foreach (ref_ps[i]) eps += ref_ps[i];
            foreach (ref_sz[i]) esz += ref_sz[i];
            n_sum_checks++;
            if (dut.sum_ps !== eps[SUMPS_W-1:0]) begin
                $error("sum_ps mismatch: dut=%0d exp=%0d", dut.sum_ps, eps); errors++;
            end
            if (dut.sum_sz !== esz[SUMSZ_W-1:0]) begin
                $error("sum_sz mismatch: dut=%0d exp=%0d", dut.sum_sz, esz); errors++;
            end
        end
    end

    // ---------------- divider monitor (checks quotient) ----------------
    longint unsigned div_exp_q[$];
    always @(posedge clk) begin
        if (!rst && dut.div_start) begin
            automatic longint unsigned num = dut.sum_ps;
            automatic longint unsigned den = dut.sum_sz;
            div_exp_q.push_back(num / den);           // golden floor divide
        end
        if (!rst && dut.div_done && !dut.div0) begin
            automatic longint unsigned e = div_exp_q.pop_front();
            n_div_checks++;
            if (dut.quotient !== e[SUMPS_W-1:0]) begin
                $error("quotient mismatch: dut=%0d exp=%0d", dut.quotient, e); errors++;
            end
        end
    end

    // ---------------- output consumer with random back-pressure ----------------
    initial begin
        m_tready = 0;
        forever begin
            @(posedge clk);
            m_tready <= ($urandom_range(0,3) != 0);   // ~75% ready
        end
    end

    // ---------------- SVA: output AXIS handshake stability ----------------
    // While a result is offered but not taken, data and valid must hold.
    property p_hold;
        @(posedge clk) disable iff (rst)
            (m_tvalid && !m_tready) |=> (m_tvalid && $stable(m_vwap));
    endproperty
    a_hold: assert property (p_hold)
        else begin $error("AXIS output not stable under back-pressure"); errors++; end

    // ---------------- main ----------------
    initial begin
        s_price = 0; s_size = 0; s_tvalid = 0;
        repeat (10) @(posedge clk);
        rst = 0;
        repeat (5) @(posedge clk);

        // randomized stream with random gaps
        for (int i = 0; i < 300; i++) begin
            // random idle gap before the next beat
            repeat ($urandom_range(0,3)) @(posedge clk);
            drive_beat($urandom_range(1, (1<<PRICE_W)-1),
                       $urandom_range(1, 255));   // keep sizes modest
        end

        // let the pipeline + last divisions drain
        repeat (3000) @(posedge clk);

        $display("[tb_vwap] sum checks=%0d  div checks=%0d  errors=%0d",
                 n_sum_checks, n_div_checks, errors);
        $display("[tb_vwap] last latency_cycles=%0d", latency_cycles);
        if (errors == 0 && n_sum_checks > 0 && n_div_checks > 0)
            $display("[tb_vwap] PASS");
        else
            $display("[tb_vwap] FAIL");
        $finish;
    end

    initial begin #(20_000_000); $error("[tb_vwap] TIMEOUT"); $finish; end
endmodule
