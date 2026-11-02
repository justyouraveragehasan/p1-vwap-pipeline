// window_accum.sv — pipeline stage 2: rolling window sums.
//
// Maintains Σ(price*size) and Σ(size) over the last WIN records as a true
// sliding window: each new beat ADDs the newest product/size and SUBTRACTs the
// one leaving the window. A WIN-deep shift register holds the in-flight records
// so we know what is leaving. Before the window fills, nothing leaves yet.
//
// This is O(1) work per beat regardless of WIN — the key trick vs recomputing
// the whole sum every cycle (which would be a long adder tree = bad Fmax).
module window_accum
    import vwap_pkg::*;
(
    input  logic                 clk,
    input  logic                 rst,
    input  logic [PROD_W-1:0]    prod,
    input  logic [SIZE_W-1:0]    size,
    input  logic                 in_valid,
    output logic [SUMPS_W-1:0]   sum_ps,
    output logic [SUMSZ_W-1:0]   sum_sz,
    output logic                 out_valid
);
    // Delay line: index 0 = newest, index WIN-1 = about to leave.
    logic [PROD_W-1:0] ps_line [WIN];
    logic [SIZE_W-1:0] sz_line [WIN];
    logic [WIN_W:0]    count;                 // valid entries so far (0..WIN)
    wire               full = (count == WIN);

    always_ff @(posedge clk) begin
        if (rst) begin
            sum_ps    <= '0;
            sum_sz    <= '0;
            count     <= '0;
            out_valid <= 1'b0;
            for (int i = 0; i < WIN; i++) begin
                ps_line[i] <= '0;
                sz_line[i] <= '0;
            end
        end else begin
            out_valid <= in_valid;
            if (in_valid) begin
                // shift the window: newest in at [0], oldest falls off [WIN-1]
                for (int i = WIN-1; i > 0; i--) begin
                    ps_line[i] <= ps_line[i-1];
                    sz_line[i] <= sz_line[i-1];
                end
                ps_line[0] <= prod;
                sz_line[0] <= size;

                // add newest, subtract the one leaving (only once the window is full)
                sum_ps <= sum_ps + prod - (full ? ps_line[WIN-1] : '0);
                sum_sz <= sum_sz + size - (full ? sz_line[WIN-1] : '0);

                if (!full) count <= count + 1'b1;
            end
        end
    end
endmodule
