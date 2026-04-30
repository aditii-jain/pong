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
    wire [11:0] ball_rgb;
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
    wire [11:0] ball_background;
    wire [9:0]  paddle_left, paddle_right, paddle_top, paddle_bottom;

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
        .btn_left      (BtnL),
        .btn_right     (BtnR),
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
    // Ball
    // -------------------------------------------------------
    pong_ball ball_ctrl(
        .clk           (move_clk),
        .bright        (bright),
        .rst           (BtnC),
        .speed_level   (ball_speed_level),
        .paddle_left   (paddle_left),
        .paddle_right  (paddle_right),
        .paddle_top    (paddle_top),
        .paddle_bottom (paddle_bottom),
        .hCount        (hc),
        .vCount        (vc),
        .rgb           (ball_rgb),
        .background    (ball_background),
        .paddle_hit_pulse(paddle_hit_pulse)
    );

    // -------------------------------------------------------
    // RGB priority: ball > paddle > background
    // -------------------------------------------------------
    assign rgb = (ball_rgb   != 12'b0000_0000_0000) ? ball_rgb   :
                 (paddle_rgb != 12'b0000_0000_0000) ? paddle_rgb :
                 ball_background;

    assign background = ball_background;

    assign vgaR = rgb[11:8];
    assign vgaG = rgb[7:4];
    assign vgaB = rgb[3:0];

    assign QuadSpiFlashCS = 1'b1;

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

    // Difficulty ramps with score and allows overlapping milestones.
    assign ball_speed_level    = (score / 14'd5 >= 14'd4) ? 4'd4 : (score / 14'd5);
    assign paddle_shrink_level = (score / 14'd7 >= 14'd7) ? 4'd7 : (score / 14'd7);

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
