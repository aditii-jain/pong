# Pong

Verilog VGA Pong game for the Digilent Nexys A7 board. The top-level module is `vga_top` in `A7_vga_top.v`.

## Files

- `A7_vga_top.v`: top-level design.
- `A7_nexys7.xdc`: Nexys A7 pin constraints.
- `display_controller.v`, `pong_ball.v`, `pong_paddle.v`, `block_controller.v`: game and VGA logic.
- `accel_spi.v`, `uart_accel_debug.v`: on-board accelerometer support and UART debug output.
- `pong_sprite_12_bit_rom.v`: generated sprite ROM.
- `sprite.py`, `pong_sprite.png`: optional sprite ROM generation script and source image.

## Run on the Nexys A7

1. Open Vivado and create a new RTL project.
2. Add all `.v` files in this directory as design sources.
3. Add `A7_nexys7.xdc` as the constraints file.
4. Select the Nexys A7 target board, or use part `xc7a100tcsg324-1` for the Nexys A7-100T.
5. Set `vga_top` as the top module.
6. Run synthesis, implementation, and bitstream generation.
7. Connect a VGA monitor to the board and program the FPGA with the generated bitstream.

## Controls

- `BtnC`: reset the game, or restart after game over.
- `SW0 = 0`: move the paddle with `BtnU` and `BtnD`.
- `SW0 = 1`: move the paddle with the on-board accelerometer.

## Regenerate the Sprite ROM

If `pong_sprite.png` changes, regenerate `pong_sprite_12_bit_rom.v` with:

```sh
python3 -m pip install imageio
python3 sprite.py
```

