`timescale 1ns / 1ps
//
// pong_paddle.v
//
// Paddle moves left/right based on the ADXL362 X-axis acceleration.
// Positive accel_x (right tilt)  → paddle moves right.
// Negative accel_x (left tilt)   → paddle moves left.
// Speed is proportional to tilt magnitude (3 tiers + dead zone).
//
// accel_x is the signed 8-bit XDATA value from accel_spi.v.
//

module pong_paddle(
    input  wire        clk,        // slow movement clock (~190 Hz)
    input  wire        bright,
    input  wire        rst,
    input  wire        use_accel,
    input  wire        btn_left,
    input  wire        btn_right,
    input  wire [7:0]  accel_x,    // signed 8-bit X acceleration from ADXL362
    input  wire [3:0]  shrink_level,
    input  wire [9:0]  hCount,
    input  wire [9:0]  vCount,
    output wire [9:0]  paddle_left,
    output wire [9:0]  paddle_right,
    output wire [9:0]  paddle_top,
    output wire [9:0]  paddle_bottom,
    output reg  [11:0] rgb,
    output reg  [11:0] background
    );

    // Visible area from display_controller timing
    localparam [9:0] H_MIN = 10'd144;
    localparam [9:0] H_MAX = 10'd783;
    localparam [9:0] V_MIN = 10'd35;
    localparam [9:0] V_MAX = 10'd515;

    // Paddle geometry
    localparam [9:0] PADDLE_HALF_W = 10'd35;  // total width  70 px
    localparam [9:0] PADDLE_HALF_H = 10'd6;   // total height 12 px
    localparam [9:0] MIN_PADDLE_HALF_W = 10'd8;

    localparam [11:0] PADDLE_COLOR = 12'b1111_1111_1111; // white
    localparam [11:0] BG_COLOR     = 12'b0000_0000_0000; // black

    // Interpret incoming byte as signed
    wire signed [7:0] ax = $signed(accel_x);

    wire accel_go_right;
    wire accel_go_left;
    wire btn_go_right;
    wire btn_go_left;
    wire go_right;
    wire go_left;

    wire [9:0] accel_step;
    wire [9:0] btn_step;
    wire [9:0] step;

    // Paddle center; Y is fixed (horizontal-only motion)
    reg [9:0] paddle_x;
    reg [9:0] paddle_y;

    wire paddle_fill;
    wire [9:0] paddle_half_w;

    // Each shrink step removes ~10% of the original total width.
    assign paddle_half_w = (shrink_level >= 4'd7) ? MIN_PADDLE_HALF_W :
                           (PADDLE_HALF_W - (shrink_level * 10'd4));

    // Dead zone ±15 LSB (~0.23 g); speed tiers at ±40 and ±80.
    assign accel_go_right = (ax > 8'sd15);
    assign accel_go_left  = (ax < -8'sd15);
    assign accel_step = ((ax > 8'sd80) || (ax < -8'sd80)) ? 10'd3 :
                        ((ax > 8'sd40) || (ax < -8'sd40)) ? 10'd2 : 10'd1;

    // Button mode uses fixed-speed left/right movement.
    assign btn_go_left  = btn_left  && !btn_right;
    assign btn_go_right = btn_right && !btn_left;
    assign btn_step = 10'd2;

    assign go_left  = use_accel ? accel_go_left  : btn_go_left;
    assign go_right = use_accel ? accel_go_right : btn_go_right;
    assign step     = use_accel ? accel_step     : btn_step;

    // Pixel colour output
    always @(*) begin
        if (~bright)
            rgb = 12'b0000_0000_0000;
        else if (paddle_fill)
            rgb = PADDLE_COLOR;
        else
            rgb = background;
    end

    assign paddle_fill   = (hCount >= (paddle_x - paddle_half_w)) &&
                           (hCount <= (paddle_x + paddle_half_w)) &&
                           (vCount >= (paddle_y - PADDLE_HALF_H)) &&
                           (vCount <= (paddle_y + PADDLE_HALF_H));

    assign paddle_left   = paddle_x - paddle_half_w;
    assign paddle_right  = paddle_x + paddle_half_w;
    assign paddle_top    = paddle_y - PADDLE_HALF_H;
    assign paddle_bottom = paddle_y + PADDLE_HALF_H;

    // Paddle position update (clocked by slow move_clk, X-axis only)
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            paddle_x <= 10'd464;  // horizontal centre of visible area
            paddle_y <= 10'd490;  // near bottom of visible area
        end else begin
            if (go_right && !go_left) begin
                if (paddle_x < H_MAX - paddle_half_w - step)
                    paddle_x <= paddle_x + step;
                else
                    paddle_x <= H_MAX - paddle_half_w;
            end else if (go_left && !go_right) begin
                if (paddle_x > H_MIN + paddle_half_w + step)
                    paddle_x <= paddle_x - step;
                else
                    paddle_x <= H_MIN + paddle_half_w;
            end else if (paddle_x > H_MAX - paddle_half_w) begin
                paddle_x <= H_MAX - paddle_half_w;
            end else if (paddle_x < H_MIN + paddle_half_w) begin
                paddle_x <= H_MIN + paddle_half_w;
            end
            // Y stays fixed
        end
    end

    // Background is always black
    always @(posedge clk or posedge rst) begin
        if (rst)
            background <= BG_COLOR;
        else
            background <= BG_COLOR;
    end

endmodule
