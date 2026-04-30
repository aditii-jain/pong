`timescale 1ns / 1ps

module pong_ball #(
    parameter [11:0] BALL_COLOR = 12'b1111_0000_0000,
    parameter signed [10:0] START_X  = 11'sd464,
    parameter signed [10:0] START_Y  = 11'sd275,
    parameter signed [10:0] START_VX = 11'sd1,
    parameter signed [10:0] START_VY = -11'sd1
)(
    input clk, // slow movement clock, similar to block_controller
    input pixel_clk,
    input bright,
    input rst,
    input enable,
    input [3:0] speed_level,
    // Paddle bounding box (for collision handling)
    input [9:0] paddle_left,
    input [9:0] paddle_right,
    input [9:0] paddle_top,
    input [9:0] paddle_bottom,
    input [9:0] hCount, vCount,
    output reg [11:0] rgb,
    output reg [11:0] background,
    output reg paddle_hit_pulse,
    output reg miss_pulse
    );

    // Visible area from display_controller timing:
    // h: 144..783, v: 35..515
    localparam [9:0] H_MIN = 10'd144;
    localparam [9:0] H_MAX = 10'd783;
    localparam [9:0] V_MIN = 10'd35;
    localparam [9:0] V_MAX = 10'd515;

    localparam signed [10:0] BALL_HALF_SIZE = 11'sd15; // 30x30 sprite

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
    wire sprite_pixel_on;
    wire paddle_hit;
    wire signed [10:0] ball_left;
    wire signed [10:0] ball_right;
    wire signed [10:0] ball_top;
    wire signed [10:0] ball_bottom;
    wire signed [10:0] h_signed;
    wire signed [10:0] v_signed;
    wire signed [10:0] sprite_col_full;
    wire signed [10:0] sprite_row_full;
    wire [4:0] sprite_col;
    wire [4:0] sprite_row;
    wire [11:0] sprite_color;

    pong_sprite_rom ball_sprite(
        .clk        (pixel_clk),
        .row        (sprite_row),
        .col        (sprite_col),
        .color_data (sprite_color)
    );

    // Draw ball or background; force black outside active display.
    always @(*) begin
        if (~bright)
            rgb = 12'b0000_0000_0000;
        else if (enable && ball_fill && sprite_pixel_on)
            rgb = sprite_color;
        else
            rgb = background;
    end

    assign h_signed = $signed({1'b0, hCount});
    assign v_signed = $signed({1'b0, vCount});

    assign ball_fill = (v_signed >= ball_top)  && (v_signed <= ball_bottom) &&
                       (h_signed >= ball_left) && (h_signed <= ball_right);
    assign sprite_pixel_on = (sprite_color != BG_COLOR);

    assign sprite_col_full = h_signed - ball_left;
    assign sprite_row_full = v_signed - ball_top;
    assign sprite_col = sprite_col_full[4:0];
    assign sprite_row = sprite_row_full[4:0];

    assign ball_left   = xpos - BALL_HALF_SIZE;
    assign ball_right  = xpos + BALL_HALF_SIZE - 11'sd1;
    assign ball_top    = ypos - BALL_HALF_SIZE;
    assign ball_bottom = ypos + BALL_HALF_SIZE - 11'sd1;

    // Only count as a paddle collision when the ball is travelling downward (vy > 0).
    assign paddle_hit = enable && (vy > 0) &&
                        (ball_right >= $signed({1'b0, paddle_left}))  && (ball_left <= $signed({1'b0, paddle_right})) &&
                        (ball_bottom >= $signed({1'b0, paddle_top}))  && (ball_top <= $signed({1'b0, paddle_bottom}));

    always @(posedge clk, posedge rst) begin
        if (rst) begin
            xpos <= START_X;
            ypos <= START_Y;
            vx <= START_VX;
            vy <= START_VY;
            paddle_hit_pulse <= 1'b0;
            miss_pulse <= 1'b0;
        end else begin
            paddle_hit_pulse <= 1'b0;
            miss_pulse <= 1'b0;

            if (!enable) begin
                xpos <= START_X;
                ypos <= START_Y;
                vx <= START_VX;
                vy <= START_VY;
            end else begin
                // Per-frame update model:
                // x = x + vx, y = y + vy
                next_vx = vx;
                next_vy = vy;
                // speed_level is the number of extra pixels/tick above the base speed.
                speed_step = $signed({7'd0, speed_level}) + 11'sd1;
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
                    miss_pulse <= 1'b1;
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
    end

    always @(posedge clk, posedge rst) begin
        if (rst)
            background <= BG_COLOR;
        else
            background <= BG_COLOR;
    end

endmodule
