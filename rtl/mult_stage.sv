// mult_stage.sv — pipeline stage 1: registered price*size.
//
// One cycle of latency. The product is PRICE_W+SIZE_W bits wide (no truncation
// here — truncation decisions belong downstream where we can reason about them).
// 'size' is passed through a matching register so it stays aligned with 'prod'
// for the accumulator (Σ size needs the same beat's size).
module mult_stage
    import vwap_pkg::*;
(
    input  logic                clk,
    input  logic                rst,
    input  logic [PRICE_W-1:0]  price,
    input  logic [SIZE_W-1:0]   size,
    input  logic                in_valid,
    output logic [PROD_W-1:0]   prod,
    output logic [SIZE_W-1:0]   size_q,
    output logic                out_valid
);
    always_ff @(posedge clk) begin
        if (rst) begin
            prod      <= '0;
            size_q    <= '0;
            out_valid <= 1'b0;
        end else begin
            prod      <= price * size;   // 16x16 -> 32, infers one DSP48
            size_q    <= size;
            out_valid <= in_valid;
        end
    end
endmodule
