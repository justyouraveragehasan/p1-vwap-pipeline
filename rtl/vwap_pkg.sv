// vwap_pkg.sv — fixed-point formats and derived widths for the VWAP datapath.
//
// The whole point of this package is that EVERY width is derived, not guessed.
// You must be able to justify each one in an interview:
//
//   price : Q8.8 unsigned  -> 16 bits  (integer price 0..255, 1/256 tick)
//   size  : unsigned int   -> 16 bits  (lot size 0..65535)
//
// Bit growth through the datapath:
//   product price*size : (8+8).(8+0) = Q16.8  -> PRICE_W+SIZE_W = 32 bits
//   Σ over WIN records  : product + log2(WIN) bits of headroom (worst case all max)
//   Σ size              : SIZE_W + log2(WIN) bits
//   VWAP = Σps / Σsize  : the Q.8 fraction is already baked into Σps, so the integer
//                         quotient IS the result in Q.8 (no pre-shift needed).
package vwap_pkg;
    parameter int PRICE_W = 16;                 // Q8.8 unsigned
    parameter int PRICE_F = 8;                  // fractional bits of price
    parameter int SIZE_W  = 16;                 // unsigned integer
    parameter int WIN      = 8;                 // sliding-window length (power of 2)
    parameter int WIN_W    = $clog2(WIN);       // 3

    parameter int PROD_W   = PRICE_W + SIZE_W;          // 32  : price*size (Q16.8)
    parameter int SUMPS_W  = PROD_W + WIN_W;            // 35  : Σ(price*size)
    parameter int SUMSZ_W  = SIZE_W + WIN_W;            // 19  : Σ(size)

    // Quotient = Σps / Σsize. Σps already carries the *256 (Q.8) scaling, so the
    // quotient is VWAP in Q.8 directly. Allocate the dividend width for the result.
    parameter int VWAP_W   = SUMPS_W;                   // 35  (we expose low bytes)
endpackage
