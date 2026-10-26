# NOSEDIVE

A head-first diving game for the Commodore 64, written in [Kick Assembler](http://theweb.dk/KickAssembler/).

You've jumped off the platform and you're diving head first down a shaft. You're falling down an
alleyway with brick walls, and ledges stick out of the walls or hang in mid-air across it. Steer left and right to dodge them
(and the occasional bird); touch either and it's game over.
Reach the bottom and dive into a big wooden pail of water to win. Miss the pail or clip its rim and it's game over. A counter in the bottom right corner shows how many
rows are left until the water (about 376 at the start). It counts rows, not seconds, so anvils make it fall faster.

**Score** (bottom left): 10 points every second, 200 for each balloon you touch, and 1000 for
landing. **Balloons** drift up the screen in front of the ledges, one every 3-6 seconds at a
random column. Fly into one to pop it. A **bird** flaps across the shaft every 10-17 seconds;
flying into it is fatal. **Anvils** (small black blocks with a grey top) sit in the gaps between ledges, never directly above or below a ledge; touch one and it disappears and the fall speeds up by 1 pixel per frame (up to `SPEED_MAX`, 3).

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
- **Brick walls.** The outer `WALL_W` (3) columns on each side are a red brick character, set once
  in colour RAM; every new row is built with bricks at both ends.
- **Ledges.** Each new bottom row is either blank or a ledge row, one every 9-12 rows at the starting speed (further apart after an anvil, so the diver always has the same time to react). Three kinds:
  **wall ledges** (3 in 4 of the single ledges): 10-13 columns, flush with a wall, usually on the
  opposite wall to the previous wall ledge so the free side keeps changing; **floating ledges**
  of 10-18 columns; and (one row in four proposed) a **double**, one ledge from each wall leaving
  a gap of 6-9 columns to steer through. The diver only sees
  about 10 rows ahead, so the generator checks reachability: from every usable open space in the
  previous ledge row (both ends and the middle), some open space in the new row must be within
  `REACH` columns (14), which is derived from the row spacing and the steering speed.
  Random numbers come from SID voice 3 noise.
- **Quiet-frame row building.** The next row is built into `row_buf` on a frame that isn't busy
  scrolling and copied in on the shift frame, keeping every frame inside the NTSC cycle budget.
- **The HUD** is two hardware sprites (1 = score, 2 = time), drawn double size from a 5x7 font. The
  program redraws their pixels only when a number changes, one sprite per frame and never on a
  frame that is busy scrolling, so they stay still while the shaft scrolls.
- **The bird** is sprite 7. It enters from a random side below the diver, climbs with the scroll so it crosses the diver's height only briefly (so it can always be dodged sideways), moves `BIRD_SPEED`
  pixels per frame, flaps through three frames and bobs up and down with the flap. Hits are tested
  in code (bounding box), and it is cleared when it leaves the screen. Only one bird at a time; the
  wait to the next one counts down while none is on screen.
- **Balloons** use sprites 3-6 (four slots). Each has three frames: the balloon sways one way while
  its string wiggles the other. Touching is tested in code against the diver's position. Score is
  kept in decimal (BCD) and stops at 9999.
- **The row counter** is decremented every time the screen shifts up a row, and is sized
  (`DISPLAY_OFFSET`) so it reaches 0 as the water arrives. A frame counter still ticks seconds for
  the +10 score, balloons and birds.
- **The diver** is hardware sprite 0, held in the middle of the screen, with three animation
  frames played as 0, 1, 2, 1. It moves sideways only.
- **Collision** uses the VIC sprite-to-background collision register, so it matches exactly
  what you see.
- **The pail.** The screen uses multicolour text with a RAM copy of the character set, plus a few
  redefined characters: brown ledge blocks, wooden planks, an iron hoop, a rim, and two wave
  shapes that swap every few frames to ripple the water. After the last ledge there is a clear
  run-out, then the pail scrolls up (rim, water, tapering wooden body) with a floor under it.
  The diver counts as landed if the sprite is wholly over the water (`LAND_X_MIN`-`LAND_X_MAX`);
  touching the rim, the sides or the floor is a crash.
- **The splash.** On landing the diver is put behind the pail's foreground pixels, so as the shaft
  keeps scrolling for `SINK_FRAMES` the pail swallows him. Five droplets (the balloon sprites,
  reused) fly up in arcs and fall back into the rising water, then the landed screen appears.
  The landing bonus is scored at the moment of impact.

A run at the starting speed takes `TIME_LIMIT` seconds (60 by default); anvils shorten it.

## Tuning

All the knobs are `.const` lines near the top of `nosedive.asm`:

| Constant | Default | Meaning |
|---|---|---|
| `SCROLL_SPEED` | 1 | pixels per frame the shaft scrolls at the start (anvils raise it, up to `SPEED_MAX` = 3) |
| `ANVIL_MASK` | 63 | 1 in (mask+1) gap rows holds an anvil (one on screen at a time) |
| `COL_WOOD_LIGHT` | 12 | the shared %01 colour (mid grey): anvil tops, ledge edges, pail hoop, brick mortar |
| `MOVE_SPEED` | 3 | pixels per frame the diver steers sideways |
| `TIME_LIMIT` | 60 | seconds from jump to ground at the starting speed; the level length (in rows) follows from it |
| `DISPLAY_OFFSET` | 11 | added to the level's row count to give the HUD counter's start value (it reaches 0 at the water) |
| `FLOAT_MASK` | 3 | a single ledge floats free when (random AND mask) is 0 (one in four); otherwise it is wall-mounted |
| `LAND_LEAD` | 10 | rows of lead so the pail's water arrives as the timer hits 0 |
| `SPLASH_FRAMES` / `SINK_FRAMES` | 100 / 30 | length of the splash scene / frames the shaft keeps scrolling while the diver sinks |
| `LAND_X_MIN` / `LAND_X_MAX` | 96 / 248 | sprite X range that counts as inside the pail's opening |
| `DOUBLE_MASK` | 3 | 1 ledge row in (mask+1) has ledges on both walls |
| `DOUBLE_GAP_MIN` | 6 | narrow gap is this many columns plus 0-3 |
| `REACH1` | derived (14) | how far, in columns, the diver can move between ledge rows at the starting speed; computed from `LEDGE_GAP_MIN` and `MOVE_SPEED`. `GAP_S2` / `GAP_S3` (14 / 19) are the blank rows needed between ledges at speeds 2 and 3 to keep the same reach |
| `WALL_W` | 3 | width of the brick walls in columns |
| `LEDGE_MIN_LEN` | 10 | shortest ledge in columns (floating: up to 18; wall-mounted: up to 13, within `REACH`) |
| `MIN_FREE` | 5 | narrowest open space that counts as passable |
| `BIRD_MIN_SEC` / `BIRD_RANGE_MASK` | 10 / 7 | a bird every 10 to 17 seconds |
| `BIRD_SPEED` | 2 | pixels per frame the bird flies |
| `BIRD_ANIM_DELAY` | 5 | frames per flap step |
| `BIRD_Y_MIN` / `BIRD_Y_MASK` | 165 / 63 | bird starts below the diver at 165 plus a random 0-63 |
| `BIRD_RISE` | 1 | pixels per frame the bird climbs; it vanishes above `BIRD_Y_TOP` (50) |
| `BIRD_HIT_*` | | bounding box used for the bird hit test |
| `LEDGE_GAP_MIN` | 8 | minimum blank rows between ledges at speed 1 (plus 0-3 random) |
| `ANIM_DELAY` | 6 | frames per diver animation step |
| `BALLOON_MIN_SEC` / `BALLOON_RANGE_SEC` | 3 / 3 | balloons appear every 3 to 6 seconds |
| `balloon_speeds` | 3, 2, 3, 4 | table by balloon colour (red, purple, green, light red): pixels per frame it rises |
| `BALLOON_POINTS_HI` | 2 | balloon score in hundreds (200) |
| `LAND_BONUS_HI` | $10 | landing bonus in BCD hundreds (1000) |

The gap between ledges is looked up by the current scroll speed (`gap_tab`), so `REACH` stays the same however fast the fall. If you change `SCROLL_SPEED` or `SPEED_MAX`, extend that table.

## Memory map

| Address | Use |
|---|---|
| `$0400` | screen RAM (the game scrolls this) |
| `$0801` | BASIC loader, then the program |
| `$2000` | sprite data: diver frames, balloon frames, score and time sprites, splash droplet, bird frames (outside `$1000-$1fff`, where the VIC sees ROM) |
| `$2800` | character set: ROM copy plus the ledge, brick and pail characters, built at startup |
| `$d800` | colour RAM, set once |
