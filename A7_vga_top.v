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
    wire [3:0]  SSD3, SSD2, SSD1, SSD0;
    reg [7:0]   SSD_CATHODES;
    wire [1:0]  ssdscan_clk;

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
    // Paddle: controlled by ADXL362 X-axis
    // -------------------------------------------------------
    pong_paddle paddle_ctrl(
        .clk           (move_clk),
        .bright        (bright),
        .rst           (BtnC),
        .accel_x       (accel_x_data),
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
        .paddle_left   (paddle_left),
        .paddle_right  (paddle_right),
        .paddle_top    (paddle_top),
        .paddle_bottom (paddle_bottom),
        .hCount        (hc),
        .vCount        (vc),
        .rgb           (ball_rgb),
        .background    (ball_background)
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

    // -------------------------------------------------------
    // Seven-segment display (available for score/time)
    // -------------------------------------------------------
    assign SSD3 = 4'b0000;
    assign SSD2 = 4'b0000;
    assign SSD1 = 4'b0000;
    assign SSD0 = 4'b0000;

    assign ssdscan_clk = DIV_CLK[19:18];
    assign An0 = !(~ssdscan_clk[1] && ~ssdscan_clk[0]);
    assign An1 = !(~ssdscan_clk[1] &&  ssdscan_clk[0]);
    assign An2 =  !(ssdscan_clk[1] && ~ssdscan_clk[0]);
    assign An3 =  !(ssdscan_clk[1] &&  ssdscan_clk[0]);
    assign {An7, An6, An5, An4} = 4'b1111;

    always @ (ssdscan_clk, SSD0, SSD1, SSD2, SSD3)
    begin : SSD_SCAN_OUT
        case (ssdscan_clk)
            2'b00: SSD = SSD0;
            2'b01: SSD = SSD1;
            2'b10: SSD = SSD2;
            2'b11: SSD = SSD3;
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

    assign {Ca, Cb, Cc, Cd, Ce, Cf, Cg, Dp} = SSD_CATHODES;

endmodule
