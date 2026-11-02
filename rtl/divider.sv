// divider.sv — unsigned sequential restoring divider, 1 bit/cycle.
//
// quotient = floor(dividend / divisor), latency = DW+2 cycles (1 to accept,
// DW to iterate, 1 to publish). Fixed, deterministic latency.
//
// This is deliberately the SIMPLE, honest baseline. In an interview the point is
// to know *why* it is the expensive part of the datapath (a full-width divide can
// not be done in one cycle at any sane Fmax) and what the alternatives are:
//   - precompute a reciprocal and multiply (1/Σsize changes slowly),
//   - Newton-Raphson refinement,
//   - keep the divide OFF the hot path entirely.
// The stretch goal swaps this for a reciprocal-multiply and compares.
module divider #(
    parameter int DW = 35,   // dividend / quotient width
    parameter int VW = 19    // divisor width
) (
    input  logic            clk,
    input  logic            rst,
    input  logic            start,       // pulse to begin (ignored unless !busy)
    input  logic [DW-1:0]   dividend,
    input  logic [VW-1:0]   divisor,
    output logic [DW-1:0]   quotient,
    output logic            busy,
    output logic            done,        // 1-cycle pulse when quotient is valid
    output logic            div0         // divisor was zero (quotient = all ones)
);
    typedef enum logic [1:0] {IDLE, RUN, FIN} state_t;
    state_t state;

    logic [DW-1:0] q;        // quotient being built (MSB-first)
    logic [DW-1:0] d;        // dividend being consumed (shifts out the top)
    logic [DW:0]   rem;      // running remainder (one extra bit for the shift-in)
    logic [VW-1:0] dvsr;
    logic          dz;
    logic [$clog2(DW+1)-1:0] cnt;

    always_ff @(posedge clk) begin
        if (rst) begin
            state <= IDLE; busy <= 1'b0; done <= 1'b0; div0 <= 1'b0;
            q <= '0; d <= '0; rem <= '0; dvsr <= '0; dz <= 1'b0; cnt <= '0;
            quotient <= '0;
        end else begin
            done <= 1'b0;
            case (state)
                IDLE: if (start) begin
                    rem  <= '0;
                    q    <= '0;
                    d    <= dividend;
                    dvsr <= divisor;
                    dz   <= (divisor == 0);
                    cnt  <= '0;
                    busy <= 1'b1;
                    state <= RUN;
                end
                RUN: begin
                    // bring the next dividend MSB into the remainder, shift dividend
                    logic [DW:0] rem_sh;
                    rem_sh = {rem[DW-1:0], d[DW-1]};
                    d <= {d[DW-2:0], 1'b0};
                    if (rem_sh >= {{(DW+1-VW){1'b0}}, dvsr}) begin
                        rem <= rem_sh - dvsr;      // subtract: this bit is 1
                        q   <= {q[DW-2:0], 1'b1};
                    end else begin
                        rem <= rem_sh;             // restore: this bit is 0
                        q   <= {q[DW-2:0], 1'b0};
                    end
                    if (cnt == DW-1) state <= FIN;
                    else             cnt <= cnt + 1'b1;
                end
                FIN: begin
                    quotient <= dz ? '1 : q;       // div-by-0 -> saturate high
                    div0     <= dz;
                    busy     <= 1'b0;
                    done     <= 1'b1;
                    state    <= IDLE;
                end
            endcase
        end
    end
endmodule
