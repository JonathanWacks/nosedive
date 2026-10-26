# NOSEDIVE

A head-first diving game for the Commodore 64, written in [Kick Assembler](http://theweb.dk/KickAssembler/).

You've jumped off the platform and you're diving head first down a shaft. Ledges stick out of the
left and right walls at random. Steer left and right to dodge them, touch one and it's game over.
Reach the ground at the bottom and you win. A countdown in the bottom right corner shows how many
seconds are left until the ground, and it starts at 60.

**Score** (bottom left): 10 points every second, 200 for each balloon you touch, and 1000 for
landing. **Balloons** drift up the screen in front of the ledges, one every 3-6 seconds at a
random column. Fly into one to pop it.

## Build and run

```
java -jar KickAss.jar nosedive.asm
x64sc nosedive.prg          # or any C64 emulator / real hardware
```

It starts with a BASIC `SYS` line, so `LOAD "NOSEDIVE",8,1` then `RUN` works too.

## Controls

Joystick in **port 2**: left and right steer the diver, fire starts and restarts the game.

## How it works

- **Smooth scrolling.** The screen runs in 24-row mode and the VIC's vertical fine-scroll
  (`$d011` bits 0-2) is stepped down `SCROLL_SPEED` pixels every frame. When the fine scroll wraps
  the text screen is moved up one row and a new row is built at the bottom. The copy runs just
  ahead of the raster beam so there is no tearing, and colour RAM never needs scrolling because
  every character uses the same colour.
- **Ledges.** Each new bottom row is either blank or a ledge row, one every 8-11 rows. Most ledge
  rows are a single ledge of 11-21 columns on a random wall. About one in four has ledges on
  **both** walls, leaving a gap of 6-9 columns to steer through. The generator only accepts a row
  whose open space is within 3 columns of the previous ledge row's open space, so a narrow gap is
  never out of reach. Random numbers come from SID voice 3 noise.
- **The HUD** is two hardware sprites (1 = score, 2 = time), drawn double size from a 5x7 font. The
  program redraws their pixels only when a number changes, one sprite per frame and never on a
  frame that is busy scrolling, so they stay still while the shaft scrolls.
- **Balloons** use sprites 3-7 (five slots). Each has three frames: the balloon sways one way while
  its string wiggles the other. Touching is tested in code against the diver's position. Score is
  kept in decimal (BCD) and stops at 9999.
- **The timer** works like this: The program detects PAL or NTSC at startup, counts 50 or 60 frames per
  second, and sizes the level (a fixed number of rows) so the ground arrives as the clock reaches 0.
- **The diver** is hardware sprite 0, held in the middle of the screen, with three animation
  frames played as 0, 1, 2, 1. It moves sideways only.
- **Collision** uses the VIC sprite-to-background collision register, so it matches exactly
  what you see.
- **The ending.** After the last ledge there is a clear run-out, then solid ground scrolls up
  to meet the diver. Touching the ground is a safe landing rather than a crash.

A run takes `TIME_LIMIT` seconds (60 by default) on both PAL and NTSC machines.

## Tuning

All the knobs are `.const` lines near the top of `nosedive.asm`:

| Constant | Default | Meaning |
|---|---|---|
| `SCROLL_SPEED` | 1 | pixels per frame the shaft scrolls (1-8) |
| `MOVE_SPEED` | 3 | pixels per frame the diver steers sideways |
| `TIME_LIMIT` | 60 | seconds from jump to ground; the level length follows from it |
| `LAND_LEAD` | 10 | rows of lead so the ground arrives as the timer hits 0 |
| `DOUBLE_MASK` | 3 | 1 ledge row in (mask+1) has ledges on both walls |
| `DOUBLE_GAP_MIN` | 6 | narrow gap is this many columns plus 0-3 |
| `REACH` | 3 | how far, in columns, a gap may be from the previous one |
| `LEDGE_MIN_LEN` | 11 | shortest ledge in columns (longest is this + 10) |
| `LEDGE_GAP_MIN` | 7 | minimum blank rows between ledges (plus 0-3 random) |
| `ANIM_DELAY` | 6 | frames per diver animation step |
| `BALLOON_MIN_SEC` / `BALLOON_RANGE_SEC` | 3 / 3 | balloons appear every 3 to 6 seconds |
| `balloon_speeds` | 3, 2, 3, 4 | table by balloon colour (red, purple, green, light red): pixels per frame it rises |
| `BALLOON_POINTS_HI` | 2 | balloon score in hundreds (200) |
| `LAND_BONUS_HI` | $10 | landing bonus in BCD hundreds (1000) |

The ledge lengths and spacing are tuned so a player who looks ahead can always dodge, but the
tightest case (two long ledges on opposite walls, 8 rows apart) leaves little spare time. If you
raise `SCROLL_SPEED` or lengthen ledges, the spacing may need to grow with it.

## Memory map

| Address | Use |
|---|---|
| `$0400` | screen RAM (the game scrolls this) |
| `$0801` | BASIC loader, then the program |
| `$2000` | sprite data: diver frames, balloon frames, then the score and time sprites (outside `$1000-$1fff`, where the VIC sees ROM) |
| `$d800` | colour RAM, set once |
