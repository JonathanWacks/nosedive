# NOSEDIVE

A head-first diving game for the Commodore 64, written in [Kick Assembler](http://theweb.dk/KickAssembler/).

You've jumped off the platform and you're diving head first down a shaft. Ledges stick out of the
left and right walls at random. Steer left and right to dodge them, touch one and it's game over.
Reach the ground at the bottom and you win.

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
- **Ledges.** Each new bottom row is either blank or a ledge of 11-21 columns attached to a
  randomly chosen wall, one ledge every 8-11 rows. Random numbers come from SID voice 3 noise.
- **The diver** is hardware sprite 0, held in the middle of the screen, with three animation
  frames played as 0, 1, 2, 1. It moves sideways only.
- **Collision** uses the VIC sprite-to-background collision register, so it matches exactly
  what you see.
- **The ending.** After the last ledge there is a clear run-out, then solid ground scrolls up
  to meet the diver. Touching the ground is a safe landing rather than a crash.

At the default settings a run takes about 60 seconds on a PAL machine.

## Tuning

All the knobs are `.const` lines near the top of `nosedive.asm`:

| Constant | Default | Meaning |
|---|---|---|
| `SCROLL_SPEED` | 2 | pixels per frame the shaft scrolls (1-8) |
| `MOVE_SPEED` | 3 | pixels per frame the diver steers sideways |
| `LEDGE_COUNT` | 80 | ledges in the level, which sets the run length |
| `LEDGE_MIN_LEN` | 11 | shortest ledge in columns (longest is this + 10) |
| `LEDGE_GAP_MIN` | 7 | minimum blank rows between ledges (plus 0-3 random) |
| `ANIM_DELAY` | 6 | frames per diver animation step |

The ledge lengths and spacing are tuned so a player who looks ahead can always dodge, but the
tightest case (two long ledges on opposite walls, 8 rows apart) leaves little spare time. If you
raise `SCROLL_SPEED` or lengthen ledges, the spacing may need to grow with it.

## Memory map

| Address | Use |
|---|---|
| `$0400` | screen RAM (the game scrolls this) |
| `$0801` | BASIC loader, then the program |
| `$0c40` | diver sprite frames (64-byte aligned, must stay below `$1000`) |
| `$d800` | colour RAM, set once |
