`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    12:18:00 12/14/2017 
// Design Name: 
// Module Name:    vga_top 
// Project Name: 
// Target Devices: 
// Tool versions: 
// Description: 
//
// Dependencies: 
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
//
// Date: 04/04/2020
// Author: Yue (Julien) Niu
// Description: Port from NEXYS3 to NEXYS4
//
// Accelerometer: Paddle X position is now controlled by the on-board ADXL362
//                via SPI.  Left/Right buttons are no longer used for paddle
//                movement (BtnL / BtnR kept as ports for compatibility).
//////////////////////////////////////////////////////////////////////////////////
module vga_top(
    input  ClkPort,
    input  SW0,
    input  BtnC,
    input  BtnU,
    input  BtnR,
    input  BtnL,
    input  BtnD,

    // VGA signals
    output hSync, vSync,
    output [3:0] vgaR, vgaG, vgaB,

    // Seven-segment display
    output An0, An1, An2, An3, An4, An5, An6, An7,
    output Ca, Cb, Cc, Cd, Ce, Cf, Cg, Dp,

    // ADXL362 SPI interface (on-board accelerometer)
    output acl_csn,   // chip-select, active LOW
    output acl_sclk,  // SPI clock
    output acl_mosi,  // FPGA → accelerometer
    input  acl_miso,  // accelerometer → FPGA

    output QuadSpiFlashCS,
    output RsTx
    );

    wire Reset;
    assign Reset = BtnC;

    wire bright;
    wire [9:0] hc, vc;
    wire [11:0] rgb;
    wire [11:0] ball0_rgb, ball1_rgb, ball2_rgb, ball3_rgb;
    wire [11:0] balls_rgb;
    wire [11:0] paddle_rgb;

    reg [3:0]   SSD;
    reg         SSD_DP;
    wire [3:0]  SSD7, SSD6, SSD5, SSD4, SSD3, SSD2, SSD1, SSD0;
    reg [7:0]   SSD_CATHODES;
    wire [2:0]  ssdscan_clk;
    wire        paddle_hit_pulse;

    reg [26:0]  sec_counter;
    reg [5:0]   elapsed_seconds;
    reg [6:0]   elapsed_minutes;
    reg [13:0]  score;
    wire [3:0]  level;
    wire        ball1_active, ball2_active, ball3_active;
    wire [3:0]  ball_speed_level;
    wire [3:0]  paddle_shrink_level;

    // -------------------------------------------------------
    // Clock divider
    // -------------------------------------------------------
    reg [27:0] DIV_CLK;
    always @ (posedge ClkPort, posedge Reset)
    begin : CLOCK_DIVIDER
        if (Reset)
            DIV_CLK <= 0;
        else
            DIV_CLK <= DIV_CLK + 1'b1;
    end

    // Movement clock: 100 MHz / 2^19 ≈ 190 Hz
    wire move_clk;
    assign move_clk = DIV_CLK[18];

    // -------------------------------------------------------
    // Accelerometer SPI reader
    // -------------------------------------------------------
    wire [7:0]  accel_x_data;   // signed 8-bit X acceleration from ADXL362
    wire        accel_valid;    // pulses when accel_x_data is updated (unused here)

    accel_spi accel_inst(
        .clk        (ClkPort),
        .rst        (Reset),
        .acl_csn    (acl_csn),
        .acl_sclk   (acl_sclk),
        .acl_mosi   (acl_mosi),
        .acl_miso   (acl_miso),
        .x_data     (accel_x_data),
        .data_valid (accel_valid)
    );

    uart_accel_debug accel_console(
        .clk    (ClkPort),
        .rst    (Reset),
        .x_data (accel_x_data),
        .tx     (RsTx)
    );

    // -------------------------------------------------------
    // VGA display controller
    // -------------------------------------------------------
    wire [11:0] background;
    wire [9:0]  paddle_left, paddle_right, paddle_top, paddle_bottom;
    wire        paddle_hit0, paddle_hit1, paddle_hit2, paddle_hit3;
    wire        level_box_fill, level_label_fill, level_digit_fill;
    wire [11:0] level_rgb;
    wire [6:0]  level_segments;
    wire        level_seg_a, level_seg_b, level_seg_c, level_seg_d;
    wire        level_seg_e, level_seg_f, level_seg_g;

    function [6:0] digit_to_segments;
        input [3:0] digit;
        begin
            case (digit)
                4'd0: digit_to_segments = 7'b1111110;
                4'd1: digit_to_segments = 7'b0110000;
                4'd2: digit_to_segments = 7'b1101101;
                4'd3: digit_to_segments = 7'b1111001;
                4'd4: digit_to_segments = 7'b0110011;
                default: digit_to_segments = 7'b1001111;
            endcase
        end
    endfunction

    display_controller dc(
        .clk    (ClkPort),
        .hSync  (hSync),
        .vSync  (vSync),
        .bright (bright),
        .hCount (hc),
        .vCount (vc)
    );

    // -------------------------------------------------------
    // Paddle: buttons when SW0=0, accelerometer when SW0=1
    // -------------------------------------------------------
    pong_paddle paddle_ctrl(
        .clk           (move_clk),
        .bright        (bright),
        .rst           (BtnC),
        .use_accel     (SW0),
        .btn_left      (BtnU),
        .btn_right     (BtnD),
        .accel_x       (accel_x_data),
        .shrink_level  (paddle_shrink_level),
        .hCount        (hc),
        .vCount        (vc),
        .paddle_left   (paddle_left),
        .paddle_right  (paddle_right),
        .paddle_top    (paddle_top),
        .paddle_bottom (paddle_bottom),
        .rgb           (paddle_rgb),
        .background    (/* paddle_background unused */)
    );

    // -------------------------------------------------------
    // Balls: add one at each 10-point level, up to 4 total.
    // -------------------------------------------------------
    pong_ball #(
        .BALL_COLOR(12'b1111_0000_0000),
        .START_X(11'sd464),
        .START_Y(11'sd275),
        .START_VX(11'sd1),
        .START_VY(-11'sd1)
    ) ball0_ctrl(
        .clk           (move_clk),
        .pixel_clk     (ClkPort),
        .bright        (bright),
        .rst           (BtnC),
        .enable        (1'b1),
        .speed_level   (ball_speed_level),
        .paddle_left   (paddle_left),
        .paddle_right  (paddle_right),
        .paddle_top    (paddle_top),
        .paddle_bottom (paddle_bottom),
        .hCount        (hc),
        .vCount        (vc),
        .rgb           (ball0_rgb),
        .background    (),
        .paddle_hit_pulse(paddle_hit0)
    );

    pong_ball #(
        .BALL_COLOR(12'b0000_1111_0000),
        .START_X(11'sd300),
        .START_Y(11'sd170),
        .START_VX(-11'sd1),
        .START_VY(11'sd1)
    ) ball1_ctrl(
        .clk           (move_clk),
        .pixel_clk     (ClkPort),
        .bright        (bright),
        .rst           (BtnC),
        .enable        (ball1_active),
        .speed_level   (ball_speed_level),
        .paddle_left   (paddle_left),
        .paddle_right  (paddle_right),
        .paddle_top    (paddle_top),
        .paddle_bottom (paddle_bottom),
        .hCount        (hc),
        .vCount        (vc),
        .rgb           (ball1_rgb),
        .background    (),
        .paddle_hit_pulse(paddle_hit1)
    );

    pong_ball #(
        .BALL_COLOR(12'b0000_0000_1111),
        .START_X(11'sd620),
        .START_Y(11'sd210),
        .START_VX(11'sd1),
        .START_VY(11'sd1)
    ) ball2_ctrl(
        .clk           (move_clk),
        .pixel_clk     (ClkPort),
        .bright        (bright),
        .rst           (BtnC),
        .enable        (ball2_active),
        .speed_level   (ball_speed_level),
        .paddle_left   (paddle_left),
        .paddle_right  (paddle_right),
        .paddle_top    (paddle_top),
        .paddle_bottom (paddle_bottom),
        .hCount        (hc),
        .vCount        (vc),
        .rgb           (ball2_rgb),
        .background    (),
        .paddle_hit_pulse(paddle_hit2)
    );

    pong_ball #(
        .BALL_COLOR(12'b1111_1111_0000),
        .START_X(11'sd400),
        .START_Y(11'sd390),
        .START_VX(-11'sd1),
        .START_VY(-11'sd1)
    ) ball3_ctrl(
        .clk           (move_clk),
        .pixel_clk     (ClkPort),
        .bright        (bright),
        .rst           (BtnC),
        .enable        (ball3_active),
        .speed_level   (ball_speed_level),
        .paddle_left   (paddle_left),
        .paddle_right  (paddle_right),
        .paddle_top    (paddle_top),
        .paddle_bottom (paddle_bottom),
        .hCount        (hc),
        .vCount        (vc),
        .rgb           (ball3_rgb),
        .background    (),
        .paddle_hit_pulse(paddle_hit3)
    );

    // -------------------------------------------------------
    // RGB priority: level overlay > balls > paddle > background
    // -------------------------------------------------------
    assign balls_rgb = (ball0_rgb != 12'b0000_0000_0000) ? ball0_rgb :
                       (ball1_rgb != 12'b0000_0000_0000) ? ball1_rgb :
                       (ball2_rgb != 12'b0000_0000_0000) ? ball2_rgb :
                       (ball3_rgb != 12'b0000_0000_0000) ? ball3_rgb :
                       12'b0000_0000_0000;

    assign level_rgb = (level_label_fill || level_digit_fill) ? 12'b0000_1111_1111 :
                       level_box_fill   ? 12'b1111_1111_1111 :
                       12'b0000_0000_0000;

    assign rgb = (level_rgb  != 12'b0000_0000_0000) ? level_rgb  :
                 (balls_rgb  != 12'b0000_0000_0000) ? balls_rgb  :
                 (paddle_rgb != 12'b0000_0000_0000) ? paddle_rgb :
                 background;

    assign background = 12'b0000_0000_0000;

    assign vgaR = rgb[11:8];
    assign vgaG = rgb[7:4];
    assign vgaB = rgb[3:0];

    assign QuadSpiFlashCS = 1'b1;
    assign paddle_hit_pulse = paddle_hit0 | paddle_hit1 | paddle_hit2 | paddle_hit3;

    // Game timer and score
    // -------------------------------------------------------
    always @(posedge ClkPort, posedge Reset)
    begin
        if (Reset) begin
            sec_counter      <= 27'd0;
            elapsed_seconds  <= 6'd0;
            elapsed_minutes  <= 7'd0;
        end else begin
            if (sec_counter == 27'd99_999_999) begin
                sec_counter <= 27'd0;
                if (elapsed_seconds == 6'd59) begin
                    elapsed_seconds <= 6'd0;
                    if (elapsed_minutes == 7'd99)
                        elapsed_minutes <= 7'd0;
                    else
                        elapsed_minutes <= elapsed_minutes + 7'd1;
                end else begin
                    elapsed_seconds <= elapsed_seconds + 6'd1;
                end
            end else begin
                sec_counter <= sec_counter + 27'd1;
            end
        end
    end

    always @(posedge move_clk, posedge Reset)
    begin
        if (Reset) begin
            score <= 14'd0;
        end else if (paddle_hit_pulse) begin
            if (score == 14'd9999)
                score <= 14'd0;
            else
                score <= score + 14'd1;
        end
    end

    // Start at level 1. Scores 10, 20, and 30 add balls 2, 3, and 4.
    assign level        = ((score / 14'd10) >= 14'd3) ? 4'd4 : ((score / 14'd10) + 4'd1);
    assign ball1_active = (level >= 4'd2);
    assign ball2_active = (level >= 4'd3);
    assign ball3_active = (level >= 4'd4);

    // Difficulty ramps with score and allows overlapping milestones.
    // Ball speed: 0-4 => base, 5-14 => +1, 15-24 => +2, then +1 every 10 points.
    assign ball_speed_level    = (score < 14'd5)  ? 4'd0 :
                                 (score < 14'd15) ? 4'd1 :
                                 (score < 14'd25) ? 4'd2 :
                                 (score < 14'd35) ? 4'd3 : 4'd4;
    assign paddle_shrink_level = (score / 14'd7 >= 14'd7) ? 4'd7 : (score / 14'd7);

    // -------------------------------------------------------
    // VGA level display: boxed "LEVEL N" in top-right
    // -------------------------------------------------------
    assign level_segments = digit_to_segments(level);
    assign level_box_fill = bright &&
                            (hc >= 10'd620) && (hc <= 10'd778) &&
                            (vc >= 10'd42)  && (vc <= 10'd100) &&
                            ((hc <= 10'd623) || (hc >= 10'd775) ||
                             (vc <= 10'd45)  || (vc >= 10'd97));

    assign level_label_fill = bright &&
                              (
                               // L
                               (((hc >= 10'd632) && (hc <= 10'd635) && (vc >= 10'd56) && (vc <= 10'd82)) ||
                                ((hc >= 10'd632) && (hc <= 10'd648) && (vc >= 10'd79) && (vc <= 10'd82))) ||
                               // E
                               (((hc >= 10'd654) && (hc <= 10'd657) && (vc >= 10'd56) && (vc <= 10'd82)) ||
                                ((hc >= 10'd654) && (hc <= 10'd670) && (vc >= 10'd56) && (vc <= 10'd59)) ||
                                ((hc >= 10'd654) && (hc <= 10'd668) && (vc >= 10'd68) && (vc <= 10'd71)) ||
                                ((hc >= 10'd654) && (hc <= 10'd670) && (vc >= 10'd79) && (vc <= 10'd82))) ||
                               // V, drawn as a blocky V so it synthesizes cleanly.
                               (((hc >= 10'd676) && (hc <= 10'd679) && (vc >= 10'd56) && (vc <= 10'd70)) ||
                                ((hc >= 10'd690) && (hc <= 10'd693) && (vc >= 10'd56) && (vc <= 10'd70)) ||
                                ((hc >= 10'd680) && (hc <= 10'd689) && (vc >= 10'd71) && (vc <= 10'd82))) ||
                               // E
                               (((hc >= 10'd700) && (hc <= 10'd703) && (vc >= 10'd56) && (vc <= 10'd82)) ||
                                ((hc >= 10'd700) && (hc <= 10'd716) && (vc >= 10'd56) && (vc <= 10'd59)) ||
                                ((hc >= 10'd700) && (hc <= 10'd714) && (vc >= 10'd68) && (vc <= 10'd71)) ||
                                ((hc >= 10'd700) && (hc <= 10'd716) && (vc >= 10'd79) && (vc <= 10'd82))) ||
                               // L
                               (((hc >= 10'd722) && (hc <= 10'd725) && (vc >= 10'd56) && (vc <= 10'd82)) ||
                                ((hc >= 10'd722) && (hc <= 10'd738) && (vc >= 10'd79) && (vc <= 10'd82)))
                              );

    assign level_seg_a = (hc >= 10'd750) && (hc <= 10'd768) && (vc >= 10'd56) && (vc <= 10'd59);
    assign level_seg_b = (hc >= 10'd765) && (hc <= 10'd768) && (vc >= 10'd59) && (vc <= 10'd69);
    assign level_seg_c = (hc >= 10'd765) && (hc <= 10'd768) && (vc >= 10'd69) && (vc <= 10'd82);
    assign level_seg_d = (hc >= 10'd750) && (hc <= 10'd768) && (vc >= 10'd82) && (vc <= 10'd85);
    assign level_seg_e = (hc >= 10'd750) && (hc <= 10'd753) && (vc >= 10'd69) && (vc <= 10'd82);
    assign level_seg_f = (hc >= 10'd750) && (hc <= 10'd753) && (vc >= 10'd59) && (vc <= 10'd69);
    assign level_seg_g = (hc >= 10'd750) && (hc <= 10'd768) && (vc >= 10'd68) && (vc <= 10'd71);

    assign level_digit_fill = bright &&
                              ((level_segments[6] && level_seg_a) ||
                               (level_segments[5] && level_seg_b) ||
                               (level_segments[4] && level_seg_c) ||
                               (level_segments[3] && level_seg_d) ||
                               (level_segments[2] && level_seg_e) ||
                               (level_segments[1] && level_seg_f) ||
                               (level_segments[0] && level_seg_g));

    // -------------------------------------------------------
    // Seven-segment display
    // Upper 4 SSDs: MM:SS elapsed time
    // Lower 4 SSDs: paddle-hit score
    // -------------------------------------------------------
    assign SSD7 = elapsed_minutes / 10;
    assign SSD6 = elapsed_minutes % 10;
    assign SSD5 = elapsed_seconds / 10;
    assign SSD4 = elapsed_seconds % 10;

    assign SSD3 = score / 1000;
    assign SSD2 = (score / 100) % 10;
    assign SSD1 = (score / 10) % 10;
    assign SSD0 = score % 10;

    assign ssdscan_clk = DIV_CLK[19:17];
    assign An0 = ~(ssdscan_clk == 3'b000);
    assign An1 = ~(ssdscan_clk == 3'b001);
    assign An2 = ~(ssdscan_clk == 3'b010);
    assign An3 = ~(ssdscan_clk == 3'b011);
    assign An4 = ~(ssdscan_clk == 3'b100);
    assign An5 = ~(ssdscan_clk == 3'b101);
    assign An6 = ~(ssdscan_clk == 3'b110);
    assign An7 = ~(ssdscan_clk == 3'b111);

    always @ (ssdscan_clk, SSD0, SSD1, SSD2, SSD3, SSD4, SSD5, SSD6, SSD7)
    begin : SSD_SCAN_OUT
        case (ssdscan_clk)
            3'b000: begin SSD = SSD0; SSD_DP = 1'b1; end
            3'b001: begin SSD = SSD1; SSD_DP = 1'b1; end
            3'b010: begin SSD = SSD2; SSD_DP = 1'b1; end
            3'b011: begin SSD = SSD3; SSD_DP = 1'b1; end
            3'b100: begin SSD = SSD4; SSD_DP = 1'b1; end
            3'b101: begin SSD = SSD5; SSD_DP = 1'b1; end
            3'b110: begin SSD = SSD6; SSD_DP = 1'b0; end
            3'b111: begin SSD = SSD7; SSD_DP = 1'b1; end
        endcase
    end

    always @ (SSD)
    begin : HEX_TO_SSD
        case (SSD)
            4'b0000: SSD_CATHODES = 8'b00000010; // 0
            4'b0001: SSD_CATHODES = 8'b10011110; // 1
            4'b0010: SSD_CATHODES = 8'b00100100; // 2
            4'b0011: SSD_CATHODES = 8'b00001100; // 3
            4'b0100: SSD_CATHODES = 8'b10011000; // 4
            4'b0101: SSD_CATHODES = 8'b01001000; // 5
            4'b0110: SSD_CATHODES = 8'b01000000; // 6
            4'b0111: SSD_CATHODES = 8'b00011110; // 7
            4'b1000: SSD_CATHODES = 8'b00000000; // 8
            4'b1001: SSD_CATHODES = 8'b00001000; // 9
            4'b1010: SSD_CATHODES = 8'b00010000; // A
            4'b1011: SSD_CATHODES = 8'b11000000; // B
            4'b1100: SSD_CATHODES = 8'b01100010; // C
            4'b1101: SSD_CATHODES = 8'b10000100; // D
            4'b1110: SSD_CATHODES = 8'b01100000; // E
            4'b1111: SSD_CATHODES = 8'b01110000; // F
            default: SSD_CATHODES = 8'bXXXXXXXX;
        endcase
    end

    assign {Ca, Cb, Cc, Cd, Ce, Cf, Cg} = SSD_CATHODES[7:1];
    assign Dp = SSD_DP;

endmodule
