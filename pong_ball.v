`timescale 1ns / 1ps

module pong_ball(
    input clk, // slow movement clock, similar to block_controller
    input bright,
    input rst,
    input [3:0] speed_level,
    // Paddle bounding box (for collision handling)
    input [9:0] paddle_left,
    input [9:0] paddle_right,
    input [9:0] paddle_top,
    input [9:0] paddle_bottom,
    input [9:0] hCount, vCount,
    output reg [11:0] rgb,
    output reg [11:0] background,
    output reg paddle_hit_pulse
    );

    // Visible area from display_controller timing:
    // h: 144..783, v: 35..515
    localparam [9:0] H_MIN = 10'd144;
    localparam [9:0] H_MAX = 10'd783;
    localparam [9:0] V_MIN = 10'd35;
    localparam [9:0] V_MAX = 10'd515;

    localparam signed [10:0] BALL_HALF_SIZE = 11'sd5; // 10x10 block

    localparam [11:0] BALL_COLOR = 12'b1111_0000_0000; // red
    localparam [11:0] BG_COLOR   = 12'b0000_0000_0000; // black

    // Ball state: position and velocity
    reg signed [10:0] xpos, ypos;
    reg signed [10:0] vx, vy;

    reg signed [10:0] next_x;
    reg signed [10:0] next_y;
    reg signed [10:0] next_vx;
    reg signed [10:0] next_vy;
    reg signed [10:0] step_x;
    reg signed [10:0] step_y;
    reg signed [10:0] speed_step;

    wire ball_fill;
    wire paddle_hit;
    wire signed [10:0] ball_left;
    wire signed [10:0] ball_right;
    wire signed [10:0] ball_top;
    wire signed [10:0] ball_bottom;
    wire [9:0] draw_x;
    wire [9:0] draw_y;

    // Draw ball or background; force black outside active display.
    always @(*) begin
        if (~bright)
            rgb = 12'b0000_0000_0000;
        else if (ball_fill)
            rgb = BALL_COLOR;
        else
            rgb = background;
    end

    assign draw_x = xpos[9:0];
    assign draw_y = ypos[9:0];

    assign ball_fill = (vCount >= (draw_y - BALL_HALF_SIZE[9:0])) && (vCount <= (draw_y + BALL_HALF_SIZE[9:0])) &&
                       (hCount >= (draw_x - BALL_HALF_SIZE[9:0])) && (hCount <= (draw_x + BALL_HALF_SIZE[9:0]));

    assign ball_left   = xpos - BALL_HALF_SIZE;
    assign ball_right  = xpos + BALL_HALF_SIZE;
    assign ball_top    = ypos - BALL_HALF_SIZE;
    assign ball_bottom = ypos + BALL_HALF_SIZE;

    // Only count as a paddle collision when the ball is travelling downward (vy > 0).
    assign paddle_hit = (vy > 0) &&
                        (ball_right >= $signed({1'b0, paddle_left}))  && (ball_left <= $signed({1'b0, paddle_right})) &&
                        (ball_bottom >= $signed({1'b0, paddle_top}))  && (ball_top <= $signed({1'b0, paddle_bottom}));

    always @(posedge clk, posedge rst) begin
        if (rst) begin
            // Start from screen center, moving up-right.
            xpos <= 11'sd464;
            ypos <= 11'sd275;
            vx <= 11'sd1;
            vy <= -11'sd1;
            paddle_hit_pulse <= 1'b0;
        end else begin
            paddle_hit_pulse <= 1'b0;

            // Per-frame update model:
            // x = x + vx, y = y + vy
            next_vx = vx;
            next_vy = vy;
            // Increase speed more gradually: each pair of levels adds 1 pixel/tick.
            speed_step = $signed({8'd0, (speed_level >> 1)}) + 11'sd1;
            step_x = (vx < 0) ? -speed_step : speed_step;
            step_y = (vy < 0) ? -speed_step : speed_step;
            next_x = xpos + step_x;
            next_y = ypos + step_y;

            // Left/right wall bounce: flip only vx
            if ((next_x - BALL_HALF_SIZE) <= $signed({1'b0, H_MIN})) begin
                next_vx = -next_vx;
                next_x = $signed({1'b0, H_MIN}) + BALL_HALF_SIZE;
            end else if ((next_x + BALL_HALF_SIZE) >= $signed({1'b0, H_MAX})) begin
                next_vx = -next_vx;
                next_x = $signed({1'b0, H_MAX}) - BALL_HALF_SIZE;
            end

            // Top/bottom wall bounce: flip only vy
            if ((next_y - BALL_HALF_SIZE) <= $signed({1'b0, V_MIN})) begin
                next_vy = -next_vy;
                next_y = $signed({1'b0, V_MIN}) + BALL_HALF_SIZE;
            end else if ((next_y + BALL_HALF_SIZE) >= $signed({1'b0, V_MAX})) begin
                next_vy = -next_vy;
                next_y = $signed({1'b0, V_MAX}) - BALL_HALF_SIZE;
            end

            // Paddle bounce: also flip only vy (pong behavior)
            if (paddle_hit) begin
                next_vy = -next_vy;
                next_y = $signed({1'b0, paddle_top}) - BALL_HALF_SIZE - 11'sd1;
                paddle_hit_pulse <= 1'b1;
            end

            xpos <= next_x;
            ypos <= next_y;
            vx <= next_vx;
            vy <= next_vy;
        end
    end

    always @(posedge clk, posedge rst) begin
        if (rst)
            background <= BG_COLOR;
        else
            background <= BG_COLOR;
    end

endmodule
