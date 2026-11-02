// vwap_top.sv — rolling VWAP datapath, AXI-Stream in and out.
//
//   s_axis (price,size) --> mult_stage --> window_accum --> divider --> m_axis (vwap)
//                           1 cyc           1 cyc           DW+2 cyc
//
// Throughput: the mult + accumulate accept ONE record per cycle (s_axis_tready is
//   always high) — line-rate ingest.
// Latency:    a result for a given beat appears ACCUM(2) + divide(DW+2) cycles later.
//   These are different numbers and you must know both.
//
// The divider is free-running: whenever it is idle, Σsize != 0, and the output is
// not back-pressured, it starts a fresh VWAP on the current sums. Output uses a
// real AXI-Stream handshake with back-pressure: while m_axis_tvalid && !m_axis_tready
// the data is held stable (and we do NOT start a new divide), so no result is ever
// corrupted or silently dropped mid-handshake.
module vwap_top
    import vwap_pkg::*;
(
    input  logic                clk,
    input  logic                rst,

    // input stream: {price, size}
    input  logic [PRICE_W-1:0]  s_price,
    input  logic [SIZE_W-1:0]   s_size,
    input  logic                s_axis_tvalid,
    output logic                s_axis_tready,

    // output stream: vwap (Q.8, low VWAP_W bits meaningful)
    output logic [VWAP_W-1:0]   m_vwap,
    output logic                m_axis_tvalid,
    input  logic                m_axis_tready,

    // telemetry
    output logic [15:0]         latency_cycles,  // input-beat -> vwap-valid, in cycles
    output logic                div0
);
    localparam int DW = SUMPS_W;
    localparam int VW = SUMSZ_W;

    // Always accept input: the add/subtract accumulator keeps up at 1 beat/cycle.
    assign s_axis_tready = 1'b1;
    wire   in_valid = s_axis_tvalid & s_axis_tready;

    // ---- stage 1: multiply ----
    logic [PROD_W-1:0] prod;
    logic [SIZE_W-1:0] size_q;
    logic              mult_valid;
    mult_stage u_mult (
        .clk, .rst, .price(s_price), .size(s_size), .in_valid(in_valid),
        .prod, .size_q, .out_valid(mult_valid)
    );

    // ---- stage 2: rolling sums ----
    logic [SUMPS_W-1:0] sum_ps;
    logic [SUMSZ_W-1:0] sum_sz;
    logic               acc_valid;
    window_accum u_acc (
        .clk, .rst, .prod, .size(size_q), .in_valid(mult_valid),
        .sum_ps, .sum_sz, .out_valid(acc_valid)
    );

    // ---- stage 3: divide (free-running) ----
    logic [DW-1:0] quotient;
    logic          div_busy, div_done, div_div0;

    // hold-off: do not launch a new divide while a result is waiting to be taken
    wire out_pending = m_axis_tvalid & ~m_axis_tready;
    wire div_start   = ~div_busy & (sum_sz != 0) & ~out_pending & ~div_done;

    divider #(.DW(DW), .VW(VW)) u_div (
        .clk, .rst,
        .start(div_start),
        .dividend(sum_ps),
        .divisor(sum_sz),
        .quotient, .busy(div_busy), .done(div_done), .div0(div_div0)
    );

    // latency counter: count cycles the divide takes, add the 2 accum/mult stages.
    logic [15:0] lat_run;
    always_ff @(posedge clk) begin
        if (rst) lat_run <= '0;
        else if (div_start) lat_run <= '0;
        else if (div_busy)  lat_run <= lat_run + 1'b1;
    end

    // ---- output handshake ----
    always_ff @(posedge clk) begin
        if (rst) begin
            m_axis_tvalid  <= 1'b0;
            m_vwap         <= '0;
            latency_cycles <= '0;
            div0           <= 1'b0;
        end else begin
            if (div_done) begin
                m_vwap         <= quotient[VWAP_W-1:0];
                m_axis_tvalid  <= 1'b1;
                latency_cycles <= lat_run + 16'd2;   // + mult + accum stages
                div0           <= div_div0;
            end else if (m_axis_tvalid & m_axis_tready) begin
                m_axis_tvalid  <= 1'b0;              // consumer took it
            end
        end
    end
endmodule
