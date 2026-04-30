`timescale 1ns / 1ps
//
// Transmit-only UART debug output for the accelerometer.
// Prints the latest X-axis byte as: AX=0xHH
//

module uart_accel_debug(
    input  wire       clk,      // 100 MHz system clock
    input  wire       rst,      // active-high reset
    input  wire [7:0] x_data,
    output reg        tx
);

    localparam integer CLKS_PER_BIT = 868;        // 100 MHz / 115200 baud
    localparam integer PRINT_PERIOD = 10_000_000; // 10 Hz debug print rate

    localparam [1:0]
        TX_IDLE  = 2'd0,
        TX_START = 2'd1,
        TX_DATA  = 2'd2,
        TX_STOP  = 2'd3;

    reg [1:0]  tx_state;
    reg [9:0]  baud_cnt;
    reg [2:0]  bit_idx;
    reg [7:0]  tx_byte;
    reg        tx_start;
    reg        tx_busy;

    reg [23:0] print_cnt;
    reg [3:0]  msg_idx;
    reg        sending_msg;
    reg [7:0]  x_latched;

    function [7:0] hex_ascii;
        input [3:0] nibble;
        begin
            hex_ascii = (nibble < 4'd10) ? (8'h30 + nibble) : (8'h41 + nibble - 4'd10);
        end
    endfunction

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            tx       <= 1'b1;
            tx_state <= TX_IDLE;
            baud_cnt <= 10'd0;
            bit_idx  <= 3'd0;
            tx_busy  <= 1'b0;
        end else begin
            case (tx_state)
                TX_IDLE: begin
                    tx       <= 1'b1;
                    baud_cnt <= 10'd0;
                    bit_idx  <= 3'd0;
                    tx_busy  <= 1'b0;
                    if (tx_start) begin
                        tx_busy  <= 1'b1;
                        tx       <= 1'b0;
                        tx_state <= TX_START;
                    end
                end

                TX_START: begin
                    if (baud_cnt == CLKS_PER_BIT - 1) begin
                        baud_cnt <= 10'd0;
                        tx       <= tx_byte[0];
                        tx_state <= TX_DATA;
                    end else begin
                        baud_cnt <= baud_cnt + 10'd1;
                    end
                end

                TX_DATA: begin
                    if (baud_cnt == CLKS_PER_BIT - 1) begin
                        baud_cnt <= 10'd0;
                        if (bit_idx == 3'd7) begin
                            bit_idx  <= 3'd0;
                            tx       <= 1'b1;
                            tx_state <= TX_STOP;
                        end else begin
                            bit_idx <= bit_idx + 3'd1;
                            tx      <= tx_byte[bit_idx + 3'd1];
                        end
                    end else begin
                        baud_cnt <= baud_cnt + 10'd1;
                    end
                end

                TX_STOP: begin
                    if (baud_cnt == CLKS_PER_BIT - 1) begin
                        baud_cnt <= 10'd0;
                        tx_state <= TX_IDLE;
                    end else begin
                        baud_cnt <= baud_cnt + 10'd1;
                    end
                end
            endcase
        end
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            print_cnt   <= 24'd0;
            msg_idx     <= 4'd0;
            sending_msg <= 1'b0;
            x_latched   <= 8'h00;
            tx_byte     <= 8'h00;
            tx_start    <= 1'b0;
        end else begin
            tx_start <= 1'b0;

            if (!sending_msg) begin
                if (print_cnt == PRINT_PERIOD - 1) begin
                    print_cnt   <= 24'd0;
                    sending_msg <= 1'b1;
                    msg_idx     <= 4'd0;
                    x_latched   <= x_data;
                end else begin
                    print_cnt <= print_cnt + 24'd1;
                end
            end else if (!tx_busy && !tx_start) begin
                case (msg_idx)
                    4'd0: tx_byte <= "A";
                    4'd1: tx_byte <= "X";
                    4'd2: tx_byte <= "=";
                    4'd3: tx_byte <= "0";
                    4'd4: tx_byte <= "x";
                    4'd5: tx_byte <= hex_ascii(x_latched[7:4]);
                    4'd6: tx_byte <= hex_ascii(x_latched[3:0]);
                    4'd7: tx_byte <= 8'h0D;
                    4'd8: tx_byte <= 8'h0A;
                    default: tx_byte <= 8'h00;
                endcase

                if (msg_idx == 4'd9) begin
                    sending_msg <= 1'b0;
                end else begin
                    tx_start <= 1'b1;
                    msg_idx  <= msg_idx + 4'd1;
                end
            end
        end
    end

endmodule
