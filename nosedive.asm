// ============================================================================
//  NOSEDIVE  -  Commodore 64  -  Kick Assembler
//  Version 0.5
//
//  You have jumped off the platform and are diving head first down a shaft.
//  Steer left and right (joystick in port 2) to dodge the ledges that stick
//  out of the left and right walls. Touch one and it's game over.
//  You drop down a brick alleyway past ledges hanging in mid-air, and the
//  odd bird that flaps across (touch one and you're dead).
//  Reach the bottom and dive into the big wooden pail of water to win - there
//  is a splash. Miss the pail, or clip its rim, and it's game over.
//  (the countdown in the top right corner is the time left to the ground).
//  Some rows have ledges on BOTH walls, leaving a narrow gap to steer through.
//  Score: +10 every second, +1000 for landing, +200 for each balloon you
//  touch. Balloons drift up the screen in front of the ledges.
//  The HUD (score bottom left, time bottom right) is drawn with sprites so
//  it stays put while the shaft scrolls.
//
//  How the scrolling works
//  -----------------------
//  The screen is put in 24-row mode and the VIC's vertical fine-scroll
//  register ($d011, bits 0-2) is stepped down SCROLL_SPEED pixels per frame,
//  which slides everything up smoothly. Every time the fine scroll wraps
//  round, the whole text screen is moved up one character row and a fresh
//  row is built at the bottom. Colour RAM never needs moving because every
//  character on screen uses the same colour.
//
//  Collision uses the VIC's own sprite-to-background collision register.
// ============================================================================

// ----------------------------------------------------------------------------
//  Hardware addresses
// ----------------------------------------------------------------------------
.const SCREEN         = $0400
.const CHARSET        = $2800          // our RAM copy of the character set
.const CPU_PORT       = $01            // bit 2 = I/O visible (0 = character ROM)
.const COLOR_RAM      = $d800
.const SPRITE_PTR     = $07f8          // sprite 0 data pointer

.const VIC_SPR0_X     = $d000
.const VIC_SPR0_Y     = $d001
.const VIC_SPR1_X     = $d002          // timer, tens digit
.const VIC_SPR1_Y     = $d003
.const VIC_SPR2_X     = $d004          // timer, ones digit
.const VIC_SPR2_Y     = $d005
.const VIC_SPR_XMSB   = $d010
.const VIC_CTRL1      = $d011          // bits 0-2 = vertical fine scroll
.const VIC_RASTER     = $d012
.const VIC_SPR_ENABLE = $d015
.const VIC_CTRL2      = $d016
.const VIC_SPR_YEXP   = $d017
.const VIC_MEMORY     = $d018
.const VIC_SPR_PRIO   = $d01b
.const VIC_SPR_MULTI  = $d01c
.const VIC_SPR_XEXP   = $d01d
.const VIC_SPR_BGHIT  = $d01f          // sprite/background collisions (read clears)
.const VIC_BORDER     = $d020
.const VIC_BACKGROUND = $d021
.const VIC_MC1        = $d022          // multicolour text colour %01
.const VIC_MC2        = $d023          // multicolour text colour %10
.const VIC_SPR0_COLOR = $d027
.const VIC_SPR1_COLOR = $d028
.const VIC_SPR2_COLOR = $d029
.const VIC_SPR3_X     = $d006          // balloons use sprites 3-6, the bird sprite 7
.const VIC_SPR3_Y     = $d007
.const VIC_SPR3_COLOR = $d02a
.const SPRITE_PTR1    = $07f9
.const SPRITE_PTR2    = $07fa
.const SPRITE_PTR3    = $07fb
.const SPRITE_PTR7    = $07ff
.const VIC_SPR7_X     = $d00e
.const VIC_SPR7_Y     = $d00f
.const VIC_SPR7_COLOR = $d02e

.const SID_V3_FREQ_LO = $d40e
.const SID_V3_FREQ_HI = $d40f
.const SID_V3_CONTROL = $d412
.const SID_V3_OSC     = $d41b          // voice 3 oscillator: our random numbers

.const CIA1_PORT_A    = $dc00          // joystick port 2 (bit 2 left, 3 right, 4 fire)

// Zero page scratch pointers (used by print_text)
.const ptr_src        = $fb
.const ptr_dst        = $fd
.const ptr_col        = $f9

// ----------------------------------------------------------------------------
//  Tunables
// ----------------------------------------------------------------------------
.const SCROLL_SPEED   = 1              // pixels per frame the shaft scrolls (1-8)
.const MOVE_SPEED     = 3              // pixels per frame the diver steers sideways
.const TIME_LIMIT     = 60             // seconds from jump to ground
.const LAND_LEAD      = 10             // rows of lead so the ground arrives as the clock hits 0
.const DOUBLE_MASK    = 3              // 1 ledge row in 4 has ledges on both walls
.const DOUBLE_GAP_MIN = 6              // narrow gap is 6-9 columns wide
.const TRIES          = 8              // attempts to find a fair ledge row
.const WALL_W        = 3              // brick walls: columns on each side
.const PF_L           = WALL_W         // playfield columns (inside the walls)
.const PF_R           = 39 - WALL_W
.const PF_W           = 40 - 2*WALL_W
.const LEDGE_MIN_LEN  = 8              // floating ledges are 8-16 columns long
.const MIN_FREE       = 5              // a gap must be at least this many columns
.const LEDGE_GAP_MIN  = 7              // blank rows between ledges: 7-10, so one
                                       // ledge every 8-11 rows
.const REACH          = floor(((LEDGE_GAP_MIN + 1)*8 - 29) / SCROLL_SPEED * MOVE_SPEED / 8) - 2
                                       // columns the diver can surely cover between two ledge
                                       // rows (a row passes him in 29 pixels of scroll), less 2
.const START_GAP      = 6              // blank rows before the first ledge
.const END_GAP        = 18             // blank rows between last ledge and ground
.const ANIM_DELAY     = 6              // frames per diver animation step

.const BALLOON_MIN_SEC = 3             // seconds between balloons: 3 to 6
.const BALLOON_RANGE_SEC = 3           // (range x fps must be 128 or more)
.const BIRD_MIN_SEC   = 10             // a bird every 10-17 seconds
.const BIRD_RANGE_MASK = 7
.const BIRD_SPEED     = 2              // pixels per frame across the screen
.const BIRD_ANIM_DELAY = 5             // frames per wing beat step
.const BIRD_Y_MIN     = 70             // bird flies at a random height from here ...
.const BIRD_Y_MASK    = 127            // ... up to this much lower
.const BIRD_HIT_Y_MIN = 128            // bird sprite Y range that overlaps the diver
.const BIRD_HIT_Y_MAX = 153
.const BIRD_HIT_DX    = 18             // and how many pixels sideways
.const BALLOON_START_Y = 247           // just below the window: rises into view
.const BALLOON_TOP    = 34             // gone once fully above the window
.const BALLOON_ANIM_DELAY = 8          // frames per balloon animation step
.const BALLOON_POINTS_HI = 2           // 200 points (BCD hundreds)
.const LAND_BONUS_HI  = $10            // 1000 points (BCD thousands)
.const LAND_X_MIN     = 96             // diver must be wholly over the water: X from
.const LAND_X_MAX     = 248            // 96 to 248 (pail opening, columns 9-30)
.const SPLASH_FRAMES  = 100            // length of the splash scene
.const SINK_FRAMES    = 30             // the shaft keeps scrolling this long: diver sinks
.const SURFACE_Y      = 159            // screen Y of the water when the diver touches it
.const WAVE_DELAY     = 8              // frames per water ripple step
.const HIT_Y_MIN      = 127            // balloon sprite Y range that overlaps the diver
.const HIT_Y_MAX      = 160
.const HIT_DX         = 20             // and how many pixels sideways
.const HUD_Y          = 228            // HUD sprites sit on the bottom rows
.const SCORE_X        = 28
.const TIME_X         = 318
.const HUD_MSB        = %00000100      // time sprite (sprite 2) is beyond X = 255
.const ROWS_PAL       = floor(TIME_LIMIT*50*SCROLL_SPEED/8) - LAND_LEAD
.const ROWS_NTSC      = floor(TIME_LIMIT*60*SCROLL_SPEED/8) - LAND_LEAD
.const PLAYER_Y       = 140            // sprite Y: vertically centred in the window
.const PLAYER_X_START = 172            // sprite X: horizontally centred
.const X_MIN          = 24 + 8*WALL_W  // leftmost sprite X: against the left wall
.const X_MAX          = 320 - 8*WALL_W // rightmost sprite X: against the right wall

.const CH_SPACE       = $20
.const CH_SOLID       = $a0            // ledge / floor: solid brown (redefined below)
.const CH_WOOD_A      = $c0            // pail characters (redefined below)
.const CH_WOOD_B      = $c1
.const CH_RIM         = $c2
.const CH_SURF_A      = $c3            // water surface, two wave shapes (rippled)
.const CH_SURF_B      = $c4
.const CH_WATER       = $c5
.const CH_HOOP        = $c6
.const CH_LEDGE       = $c7            // floating ledge
.const CH_BRICK       = $c8            // wall bricks
.const ROW_LAST       = SCREEN + 24*40 // the row new ledges are built on

.const COL_BORDER     = 14             // light blue
.const COL_BACKGROUND = 6              // blue
.const COL_LEDGE      = 9              // brown: ledges and the pail (multicolour %10)
.const COL_WOOD_LIGHT = 8              // orange: wood highlights (multicolour %01)
.const COL_WATER      = 3              // cyan: the water (cell colour, multicolour %11)
.const CELL_COLOUR    = 8 + COL_WATER  // colour RAM value: bit 3 = multicolour cell
.const COL_BRICK      = 2              // red: brick walls (cell colour, multicolour %11)
.const BRICK_CELL     = 8 + COL_BRICK
.const COL_BIRD       = 15             // light grey
.const COL_DIVER      = 7              // yellow
.const COL_TEXT       = 1              // white
.const COL_TIMER      = 1              // white
.const COL_SCORE      = 3              // cyan
.const COL_WIN        = 5              // green
.const COL_DEAD       = 2              // red

// ----------------------------------------------------------------------------
//  BASIC loader:  10 SYS 2061
// ----------------------------------------------------------------------------
* = $0801 "BASIC Upstart"
BasicUpstart2(start)

// ----------------------------------------------------------------------------
//  Program start
// ----------------------------------------------------------------------------
start:
    sei                                // we poll the raster, no KERNAL interrupts

    lda #$ff
    sta CIA1_PORT_A                    // release joystick lines

    // SID voice 3 as a noise generator: reading $d41b gives random bytes
    lda #$ff
    sta SID_V3_FREQ_LO
    sta SID_V3_FREQ_HI
    lda #$80
    sta SID_V3_CONTROL

    // Character set: ROM copy in RAM plus our own ledge/pail characters
    jsr setup_charset

    // VIC: 40 columns, multicolour text, screen at $0400, characters at $2800.
    // Game cells are multicolour; text cells (colour 0-7) stay hi-res.
    lda #$d8
    sta VIC_CTRL2
    lda #$1a
    sta VIC_MEMORY
    lda #COL_WOOD_LIGHT
    sta VIC_MC1
    lda #COL_LEDGE
    sta VIC_MC2

    // Sprite 0 is the diver: hires, in front of the background, normal size
    lda #0
    sta VIC_SPR_MULTI
    sta VIC_SPR_PRIO
    sta VIC_SPR_XEXP
    sta VIC_SPR_YEXP
    lda #COL_DIVER
    sta VIC_SPR0_COLOR
    // Sprites 1 and 2 are the HUD (score, time), drawn double size
    lda #COL_SCORE
    sta VIC_SPR1_COLOR
    lda #COL_TIMER
    sta VIC_SPR2_COLOR
    lda #HUD_Y
    sta VIC_SPR1_Y
    sta VIC_SPR2_Y
    lda #SCORE_X
    sta VIC_SPR1_X
    lda #<TIME_X
    sta VIC_SPR2_X
    lda #%00000110
    sta VIC_SPR_XEXP
    sta VIC_SPR_YEXP
    lda #(score_sprite/64)
    sta SPRITE_PTR1
    lda #(time_sprite/64)
    sta SPRITE_PTR2
    lda #7                             // sprites 0-2: diver, score, time
    sta VIC_SPR_ENABLE

    jsr detect_system                  // PAL or NTSC: sets fps and is_pal

    // Title screen
    jsr init_game
    lda #<txt_title
    ldx #>txt_title
    jsr print_text
    lda #<txt_help1
    ldx #>txt_help1
    jsr print_text
    lda #<txt_help2
    ldx #>txt_help2
    jsr print_text
    lda #<txt_help3
    ldx #>txt_help3
    jsr print_text
    lda #<txt_start
    ldx #>txt_start
    jsr print_text
    jsr wait_for_fire

new_game:
    jsr init_game

// ----------------------------------------------------------------------------
//  Main loop - one pass per video frame
// ----------------------------------------------------------------------------
game_loop:
    jsr wait_frame                     // just after the display window ends
    lda splash
    beq flying_frame
    jmp splash_frame                   // already in the water

flying_frame:
    // Did the diver touch anything during the frame we just displayed?
    lda VIC_SPR_BGHIT
    and #1
    beq still_flying
    lda ground_seen
    beq crash_far                      // a ledge: ouch
    jsr in_opening                     // the pail: did we hit the water?
    bcc crash_far                      // rim, wall or floor: ouch
    jmp start_splash
crash_far:
    jmp crashed

still_flying:
    jsr move_diver
    jsr animate_diver
    jsr animate_water
    jsr update_timer
    jsr update_bird                    // carry set = hit by the bird
    bcc bird_ok
    jmp crashed
bird_ok:
    jsr update_balloons
    jsr scroll_shaft
    jsr hud_update
    jmp game_loop

// ----------------------------------------------------------------------------
//  End of game
// ----------------------------------------------------------------------------
landed:
    lda #COL_WIN
    sta VIC_BORDER
    lda #<txt_landed
    ldx #>txt_landed
    jsr print_text
    lda #<txt_again
    ldx #>txt_again
    jsr print_text
    jmp game_over_wait

crashed:
    lda #COL_DEAD
    sta VIC_BORDER
    lda #<txt_crashed
    ldx #>txt_crashed
    jsr print_text
    lda #<txt_retry
    ldx #>txt_retry
    jsr print_text

game_over_wait:
    jsr wait_for_fire
    jmp new_game

// ----------------------------------------------------------------------------
//  wait_frame: wait for raster line 248, just below the 24-row window
// ----------------------------------------------------------------------------
wait_frame:
    lda VIC_RASTER
    cmp #248
    bne wait_frame
    rts

// ----------------------------------------------------------------------------
//  wait_for_fire: wait for the fire button to be released, then pressed
// ----------------------------------------------------------------------------
wait_for_fire:
    lda CIA1_PORT_A
    and #$10
    beq wait_for_fire                  // still held from before
fire_wait_press:
    lda CIA1_PORT_A
    and #$10
    bne fire_wait_press
    rts

// ----------------------------------------------------------------------------
//  init_game: clear the shaft and reset all game state
// ----------------------------------------------------------------------------
init_game:
    jsr wait_frame                     // do the rebuild while the display is off

    lda #CH_SPACE
    ldx #0
clear_screen:
    sta SCREEN,x
    sta SCREEN+$100,x
    sta SCREEN+$200,x
    sta SCREEN+$2e8,x
    inx
    bne clear_screen

    lda #CELL_COLOUR                   // one colour for everything: never scrolled
    ldx #0
clear_colour:
    sta COLOR_RAM,x
    sta COLOR_RAM+$100,x
    sta COLOR_RAM+$200,x
    sta COLOR_RAM+$2e8,x
    inx
    bne clear_colour

    lda #COL_BORDER
    sta VIC_BORDER
    lda #COL_BACKGROUND
    sta VIC_BACKGROUND

    // Brick walls on every row: brick characters in screen RAM, red cells in colour RAM
    lda #<SCREEN
    sta ptr_dst
    lda #>SCREEN
    sta ptr_dst+1
    lda #<COLOR_RAM
    sta ptr_col
    lda #>COLOR_RAM
    sta ptr_col+1
    ldx #25
iw_row:
    ldy #0
iw_left:
    lda #CH_BRICK
    sta (ptr_dst),y
    lda #BRICK_CELL
    sta (ptr_col),y
    iny
    cpy #WALL_W
    bne iw_left
    ldy #(40 - WALL_W)
iw_right:
    lda #CH_BRICK
    sta (ptr_dst),y
    lda #BRICK_CELL
    sta (ptr_col),y
    iny
    cpy #40
    bne iw_right
    clc
    lda ptr_dst
    adc #40
    sta ptr_dst
    bcc iw_d
    inc ptr_dst+1
iw_d:
    clc
    lda ptr_col
    adc #40
    sta ptr_col
    bcc iw_c
    inc ptr_col+1
iw_c:
    dex
    bne iw_row

    lda #7                             // fine scroll 7 (24-row mode, display on)
    sta yscroll
    ora #$10
    sta VIC_CTRL1

    lda #ANIM_DELAY
    sta anim_timer
    lda #0
    sta anim_index
    sta ground_seen
    sta splash
    sta pail_step
    sta wave_phase
    sta row_ready
    sta VIC_SPR_PRIO                   // diver in front of the shaft again
    lda #WAVE_DELAY
    sta wave_timer
    jsr put_wave                       // water ripple back to its first shape
    lda #START_GAP
    sta ledge_wait
    lda #1                             // before the first ledge anything is reachable
    sta pi_n
    lda #PF_L
    sta pi_a
    lda #(PF_R - 2)                    // (diver positions are left-hand columns)
    sta pi_b
    lda #0
    sta bird_active
    sta bird_en
    sta bird_msb
    jsr set_bird_wait

    // rows to build before the ground, for a TIME_LIMIT second dive
    lda is_pal
    beq init_rows_ntsc
    lda #<ROWS_PAL
    sta rows_lo
    lda #>ROWS_PAL
    sta rows_hi
    jmp init_rows_done
init_rows_ntsc:
    lda #<ROWS_NTSC
    sta rows_lo
    lda #>ROWS_NTSC
    sta rows_hi
init_rows_done:

    lda #TIME_LIMIT                    // countdown
    sta seconds
    lda fps
    sta fps_count

    lda #0                             // score, balloons
    sta score_lo
    sta score_hi
    sta msbmask
    ldx #4
init_balloons:
    sta b_y,x
    sta b_speed,x
    dex
    bpl init_balloons
    lda #7
    sta VIC_SPR_ENABLE                 // diver and HUD only
    lda #BALLOON_ANIM_DELAY
    sta banim_timer
    lda #0
    sta banim_index
    jsr set_spawn_interval
    lda #0
    sta score_dirty
    sta time_dirty
    sta shifted
    jsr render_score
    jsr render_time

    lda #<PLAYER_X_START
    sta player_x_lo
    lda #>PLAYER_X_START
    sta player_x_hi
    lda #PLAYER_Y
    sta VIC_SPR0_Y
    jsr update_sprite_x
    lda #(sprite_frames/64)
    sta SPRITE_PTR

    lda VIC_SPR_BGHIT                  // reading clears any stale collision flags
    rts

// ----------------------------------------------------------------------------
//  update_sprite_x: copy the 9-bit diver X position into the VIC
// ----------------------------------------------------------------------------
update_sprite_x:
    lda player_x_lo
    sta VIC_SPR0_X
    lda player_x_hi                    // bit 0 = X bit 8 of the diver
    ora #HUD_MSB                       // plus the fixed bit for the time sprite
    ora msbmask                        // and the balloons' bit 8s
    sta VIC_SPR_XMSB
    rts

// ----------------------------------------------------------------------------
//  move_diver: joystick left/right moves the diver, clamped to the screen
// ----------------------------------------------------------------------------
move_diver:
    lda CIA1_PORT_A
    and #$04                           // bit 2 clear = left
    bne check_right
    sec
    lda player_x_lo
    sbc #MOVE_SPEED
    sta player_x_lo
    lda player_x_hi
    sbc #0
    sta player_x_hi
    bne check_right                    // X >= 256, cannot be too far left
    lda player_x_lo
    cmp #X_MIN
    bcs check_right
    lda #X_MIN
    sta player_x_lo

check_right:
    lda CIA1_PORT_A
    and #$08                           // bit 3 clear = right
    bne move_done
    clc
    lda player_x_lo
    adc #MOVE_SPEED
    sta player_x_lo
    lda player_x_hi
    adc #0
    sta player_x_hi
    beq move_done                      // X < 256, cannot be too far right
    lda player_x_lo
    cmp #(X_MAX - 255)
    bcc move_done
    lda #(X_MAX - 256)
    sta player_x_lo

move_done:
    jmp update_sprite_x

// ----------------------------------------------------------------------------
//  animate_diver: cycle through the diver frames 0,1,2,1 to suggest the arms
//  flapping in the rush of air
// ----------------------------------------------------------------------------
animate_diver:
    dec anim_timer
    bne anim_show
    lda #ANIM_DELAY
    sta anim_timer
    lda anim_index
    clc
    adc #1
    and #3
    sta anim_index
anim_show:
    ldx anim_index
    lda anim_sequence,x
    clc
    adc #(sprite_frames/64)
    sta SPRITE_PTR
    rts

anim_sequence:
    .byte 0, 1, 2, 1

// ----------------------------------------------------------------------------
//  scroll_shaft: move everything up SCROLL_SPEED pixels. When the fine scroll
//  runs out, shift the screen up a whole row and build a new bottom row.
// ----------------------------------------------------------------------------
scroll_shaft:
    lda yscroll
    sec
    sbc #SCROLL_SPEED
    bpl scroll_fine                    // still within the current character row
    clc
    adc #8                             // wrap back to the top of the 0-7 range
    sta yscroll
    ora #$10
    sta VIC_CTRL1
    jmp shift_rows

scroll_fine:
    sta yscroll
    ora #$10
    sta VIC_CTRL1
    rts

// ----------------------------------------------------------------------------
//  shift_rows: move screen rows 1-24 up to rows 0-23, then build row 24.
//  Copied top to bottom in four unrolled chunks of 240 bytes. The copy runs
//  just ahead of the raster beam, so there is no tearing.
// ----------------------------------------------------------------------------
shift_rows:
    lda #1
    sta shifted
    ldx #0
shift_chunk_0:
    lda SCREEN+40+0,x
    sta SCREEN+0,x
    lda SCREEN+40+1,x
    sta SCREEN+1,x
    lda SCREEN+40+2,x
    sta SCREEN+2,x
    lda SCREEN+40+3,x
    sta SCREEN+3,x
    inx
    inx
    inx
    inx
    cpx #240
    bne shift_chunk_0
    ldx #0
shift_chunk_1:
    lda SCREEN+40+240,x
    sta SCREEN+240,x
    lda SCREEN+40+241,x
    sta SCREEN+241,x
    lda SCREEN+40+242,x
    sta SCREEN+242,x
    lda SCREEN+40+243,x
    sta SCREEN+243,x
    inx
    inx
    inx
    inx
    cpx #240
    bne shift_chunk_1
    ldx #0
shift_chunk_2:
    lda SCREEN+40+480,x
    sta SCREEN+480,x
    lda SCREEN+40+481,x
    sta SCREEN+481,x
    lda SCREEN+40+482,x
    sta SCREEN+482,x
    lda SCREEN+40+483,x
    sta SCREEN+483,x
    inx
    inx
    inx
    inx
    cpx #240
    bne shift_chunk_2
    ldx #0
shift_chunk_3:
    lda SCREEN+40+720,x
    sta SCREEN+720,x
    lda SCREEN+40+721,x
    sta SCREEN+721,x
    lda SCREEN+40+722,x
    sta SCREEN+722,x
    lda SCREEN+40+723,x
    sta SCREEN+723,x
    inx
    inx
    inx
    inx
    cpx #240
    bne shift_chunk_3
    jmp new_row

// ----------------------------------------------------------------------------
//  new_row: put the prepared row on the bottom screen row. (The row itself was
//  built in an earlier, quieter frame by prepare_row - see hud_update. If that
//  hasn't happened it is built here, which is slower but still right.)
// ----------------------------------------------------------------------------
new_row:
    lda row_ready
    bne nr_copy
    jsr prepare_row
nr_copy:
    ldx #39
nr_loop:
    lda row_buf,x
    sta ROW_LAST,x
    dex
    bpl nr_loop
    lda #0
    sta row_ready
    rts

// ----------------------------------------------------------------------------
//  prepare_row: build the next bottom row in row_buf. The level is a fixed number of rows
//  (rows_lo/hi counts them down) so it lasts TIME_LIMIT seconds: random ledges,
//  then END_GAP clear rows, then the pail, then a solid floor.
// ----------------------------------------------------------------------------
prepare_row:
    lda ground_seen
    bne row_pail
    lda rows_lo                        // 16-bit decrement of the rows left
    bne nr_dec
    dec rows_hi
nr_dec:
    dec rows_lo
    lda rows_lo
    ora rows_hi
    beq row_pail                       // that was the last row: the pail
    lda rows_hi
    bne nr_ledges
    lda rows_lo
    cmp #END_GAP
    bcc row_blank                      // run-out above the ground
nr_ledges:
    lda ledge_wait
    bne nr_wait
    jmp row_ledge
nr_wait:
    dec ledge_wait

row_blank:
    lda #CH_SPACE
    jsr row_fill
    lda #CH_BRICK                      // the walls
    ldx #(WALL_W - 1)
rb_walls:
    sta row_buf,x
    sta row_buf + 40 - WALL_W,x
    dex
    bpl rb_walls
    rts

row_fill:
    ldx #39
row_fill_loop:
    sta row_buf,x
    dex
    bpl row_fill_loop
    rts

// ----------------------------------------------------------------------------
//  row_pail: the pail and floor, one table row per screen row. Kinds:
//  0 = water surface between rim caps, 1 = water between rim caps,
//  2 = front rim, 3 = wooden side, 4 = iron hoop, 5 = floor.
// ----------------------------------------------------------------------------
.const PAIL_ROWS      = 15

row_pail:
    lda #1
    sta ground_seen
    ldx pail_step
    cpx #(PAIL_ROWS-1)
    beq rp_draw                        // the last entry (floor) repeats forever
    inc pail_step
rp_draw:
    lda pail_kind,x
    cmp #5
    bne rp_shape
    lda #CH_SOLID                      // floor
    jmp row_fill
rp_shape:
    sta pk
    lda pail_a,x
    sta pa
    lda pail_b,x
    clc
    adc #1
    sta pb                             // one past the last column
    jsr row_blank
    ldx pa
rp_fill:
    txa
    and #1
    bne rp_odd
    ldy pk
    lda char_even,y
    jmp rp_put
rp_odd:
    ldy pk
    lda char_odd,y
rp_put:
    sta row_buf,x
    inx
    cpx pb
    bne rp_fill
    lda pk
    cmp #2
    bcs rp_done
    lda #CH_RIM                        // rim caps at both ends of the water
    ldx pa
    sta row_buf,x
    ldx pb
    dex
    sta row_buf,x
rp_done:
    rts

//               surface,      water,    rim,     wood,       hoop
char_even:  .byte CH_SURF_A,  CH_WATER, CH_RIM,  CH_WOOD_A,  CH_HOOP
char_odd:   .byte CH_SURF_B,  CH_WATER, CH_RIM,  CH_WOOD_B,  CH_HOOP

// The pail is 24 columns wide at the top, tapering to 16 at the base
pail_kind:  .byte 0,  1,  2,  3,  3,  4,  3,  3,  3,  3,  4,  3,  3,  2,  5
pail_a:     .byte 8,  8,  7,  8,  8,  9,  9,  9, 10, 10, 11, 11, 11, 12, 0
pail_b:     .byte 31, 31, 32, 31, 31, 30, 30, 30, 29, 29, 28, 28, 28, 27, 39

// ----------------------------------------------------------------------------
//  in_opening: carry set if the diver is wholly over the pail's water
// ----------------------------------------------------------------------------
in_opening:
    lda player_x_hi
    bne io_no
    lda player_x_lo
    cmp #LAND_X_MIN
    bcc io_no
    cmp #(LAND_X_MAX+1)
    bcs io_no
    sec
    rts
io_no:
    clc
    rts

// ----------------------------------------------------------------------------
//  row_ledge: build a ledge row. Pick a candidate: a single ledge hanging free
//  in mid-air, or (one row in four) ledges from both walls with a narrow gap
//  between them. Accept it only if its widest open space is within REACH
//  columns of the previous ledge row's, so the diver can always get there in
//  time. Otherwise try again, and after TRIES attempts leave the row empty.
// ----------------------------------------------------------------------------
row_ledge:
    jsr get_random                     // blank rows before the next ledge row
    and #3
    clc
    adc #LEDGE_GAP_MIN
    sta ledge_wait

    lda #TRIES
    sta tries
ledge_try:
    jsr pick_ledge                     // carry clear = unusable candidate
    bcc ledge_retry
    jsr check_reach                    // carry clear = too far from last gap
    bcs ledge_accept
ledge_retry:
    dec tries
    bne ledge_try
    jmp row_blank                      // nothing fair found: empty row

ledge_accept:
    jsr row_blank                      // walls only
    ldx seg1_s
    ldy seg1_n
    beq ledge_seg2
    jsr draw_seg
ledge_seg2:
    ldx seg2_s
    ldy seg2_n
    beq ledge_made
    jsr draw_seg
ledge_made:
    ldx #1                             // remember where the free space was
lm_copy:
    lda ci_a,x
    sta pi_a,x
    lda ci_b,x
    sta pi_b,x
    dex
    bpl lm_copy
    lda ci_n
    sta pi_n
    rts

// draw_seg: ledge characters in X..X+Y-1 of the new row
draw_seg:
    lda #CH_LEDGE
draw_seg_loop:
    sta row_buf,x
    inx
    dey
    bne draw_seg_loop
    rts

// ----------------------------------------------------------------------------
//  pick_ledge: choose a random candidate row. Sets seg1_s/seg1_n and
//  seg2_s/seg2_n (start column and length of up to two ledges) and the usable
//  open spaces ci_a/ci_b (range of left-hand columns the diver can take, 1-2
//  of them). Returns carry set if the candidate is OK.
// ----------------------------------------------------------------------------
pick_ledge:
    jsr get_random
    and #DOUBLE_MASK
    bne ps_single
    jmp pick_double
ps_single:
    jsr get_random                     // single ledge: length = MIN + 0..7 + 0..1
    and #7
    sta seg1_n
    jsr get_random
    and #1
    clc
    adc seg1_n
    clc
    adc #LEDGE_MIN_LEN
    sta seg1_n
    lda #(PF_W + 1)                    // possible start positions
    sec
    sbc seg1_n
    sta tmpv
    jsr get_random
    and #31
    cmp tmpv
    bcc ps_start
    sbc tmpv                           // fold into range
ps_start:
    clc
    adc #PF_L
    sta seg1_s
    lda #0
    sta seg2_n
    lda seg1_s                         // open space to the left of the ledge
    sec
    sbc #PF_L
    sta w1
    lda #(PF_R + 1)                    // and to the right
    sec
    sbc seg1_s
    sec
    sbc seg1_n
    sta w2
    lda #0                             // list the open spaces wide enough to use
    sta ci_n
    lda w1
    cmp #MIN_FREE
    bcc ps_noleft
    ldx ci_n
    lda #PF_L
    sta ci_a,x
    lda seg1_s
    sec
    sbc #3                             // last column the diver's left edge can take
    sta ci_b,x
    inc ci_n
ps_noleft:
    lda w2
    cmp #MIN_FREE
    bcc ps_noright
    ldx ci_n
    lda seg1_s
    clc
    adc seg1_n
    sta ci_a,x
    lda #(PF_R - 2)
    sta ci_b,x
    inc ci_n
ps_noright:
    lda ci_n
    beq pick_bad
    sec
    rts

pick_double:
    jsr get_random                     // gap width 6-9 columns
    and #3
    clc
    adc #DOUBLE_GAP_MIN
    sta gap_w
    jsr get_random                     // gap starts at column PF_L+3 ...
    and #31
    clc
    adc #(PF_L + 3)
    sta free_lo
    clc
    adc gap_w                          // first column of the right ledge
    sta tmpv
    cmp #(PF_R - 1)                    // keep at least 3 columns of right ledge
    bcs pick_bad
    lda #PF_L
    sta seg1_s
    lda free_lo
    sec
    sbc #PF_L
    sta seg1_n                         // left ledge: PF_L to the gap
    lda tmpv
    sta seg2_s
    lda #(PF_R + 1)
    sec
    sbc tmpv
    sta seg2_n                         // right ledge: from the gap to PF_R
    lda #1
    sta ci_n
    lda free_lo
    sta ci_a                           // diver positions in the gap
    lda tmpv
    sec
    sbc #3
    sta ci_b
    sec
    rts
pick_bad:
    clc
    rts

// ----------------------------------------------------------------------------
//  check_reach: carry set if, wherever the diver is in the previous ledge
//  row's open spaces (pi_a/pi_b), some open space of the candidate (ci_a/ci_b)
//  is within REACH columns. The diver sees only a row or two ahead, so this
//  must hold from every open space he could have picked, at its two ends and
//  its middle.
// ----------------------------------------------------------------------------
check_reach:
    ldx #0
cr_prev:
    cpx pi_n
    bcs cr_ok
    lda pi_a,x
    jsr near_any
    bcc cr_fail
    lda pi_b,x
    jsr near_any
    bcc cr_fail
    lda pi_a,x
    clc
    adc pi_b,x
    lsr
    jsr near_any
    bcc cr_fail
    inx
    bne cr_prev
cr_ok:
    sec
    rts
cr_fail:
    clc
    rts

// near_any: A = diver column; carry set if a candidate open space is within REACH
near_any:
    sta chk_p
    ldy #0
na_loop:
    cpy ci_n
    bcs na_no
    lda ci_a,y
    sta ja
    lda ci_b,y
    sta jb
    lda chk_p
    jsr dist_pj
    cmp #(REACH + 1)
    bcc na_yes
    iny
    bne na_loop
na_yes:
    sec
    rts
na_no:
    clc
    rts

// dist_pj: A = column p; distance (in columns) to the range ja..jb
dist_pj:
    sta dpp
    lda ja
    sec
    sbc dpp
    bcs dpj_ret                        // p at or left of the range
    lda dpp
    sec
    sbc jb
    bcs dpj_ret                        // p right of the range
    lda #0                             // inside it
dpj_ret:
    rts

// ----------------------------------------------------------------------------
//  detect_system: PAL (50 Hz) or NTSC (60 Hz)? PAL has raster lines above 263.
//  Sets is_pal and fps.
// ----------------------------------------------------------------------------
detect_system:
    ldx #0
    ldy #12                            // poll for about 2-3 frames
det_loop:
    lda VIC_CTRL1
    bpl det_next                       // raster bit 8 clear
    lda VIC_RASTER
    cmp #8
    bcs det_pal                        // line 264 or more: PAL
det_next:
    inx
    bne det_loop
    dey
    bne det_loop
    lda #0
    sta is_pal
    lda #60
    sta fps
    rts
det_pal:
    lda #1
    sta is_pal
    lda #50
    sta fps
    rts

// ----------------------------------------------------------------------------
//  update_timer: once per frame. Counts fps frames per second; each second
//  ticks the display down to 00 and scores 10 points.
// ----------------------------------------------------------------------------
update_timer:
    dec fps_count
    bne timer_done
    lda fps
    sta fps_count
    lda #$10                           // +10 points each second
    ldx #0
    jsr add_score
    lda bird_active                    // count seconds to the next bird
    bne ut_bird_done
    dec bird_wait
    bne ut_bird_done
    jsr spawn_bird
    jsr set_bird_wait
ut_bird_done:
    lda seconds
    beq timer_done
    dec seconds
    lda #1
    sta time_dirty
timer_done:
    rts

// hud_update: the quiet-frame jobs, one per frame, never on a frame that shifted
// the screen (those already use most of the frame): build the next shaft row,
// else redraw one changed HUD sprite.
hud_update:
    lda shifted
    beq hu_go
    lda #0
    sta shifted
    rts
hu_go:
    lda row_ready                      // first, get the next shaft row ready
    bne hu_hud
    lda #1
    sta row_ready
    jmp prepare_row
hu_hud:
    lda score_dirty
    beq hu_time
    lda #0
    sta score_dirty
    jmp render_score
hu_time:
    lda time_dirty
    beq hu_done
    lda #0
    sta time_dirty
    jmp render_time
hu_done:
    rts

// render_time: draw 'seconds' into the time sprite
render_time:
    lda seconds
    ldx #0                             // X = tens
show_tens:
    cmp #10
    bcc show_ones
    sbc #10                            // carry is set here
    inx
    bne show_tens
show_ones:
    sta dig1
    stx dig0
    lda #10                            // 10 = blank glyph
    sta dig2
    sta dig3
    lda #<time_sprite
    sta ptr_dst
    lda #>time_sprite
    sta ptr_dst+1
    jmp render_digits

// ----------------------------------------------------------------------------
//  Score. Kept as 4 BCD digits: score_hi = thousands/hundreds, score_lo =
//  tens/units. add_score: A = BCD to add to score_lo, X = BCD to add to
//  score_hi. Stops at 9999 and redraws the HUD.
// ----------------------------------------------------------------------------
add_score:
    sed
    clc
    adc score_lo
    sta score_lo
    txa
    adc score_hi
    sta score_hi
    cld
    bcc add_score_done
    lda #$99
    sta score_lo
    sta score_hi
add_score_done:
    lda #1
    sta score_dirty                    // HUD redraws soon
    rts

render_score:
    lda score_hi
    lsr
    lsr
    lsr
    lsr
    sta dig0
    lda score_hi
    and #15
    sta dig1
    lda score_lo
    lsr
    lsr
    lsr
    lsr
    sta dig2
    lda score_lo
    and #15
    sta dig3
    lda #<score_sprite
    sta ptr_dst
    lda #>score_sprite
    sta ptr_dst+1

// ----------------------------------------------------------------------------
//  render_digits: draw four 5x7 glyphs (numbers dig0-dig3, 10 = blank) into
//  the sprite at ptr_dst, 6 pixels apart. Only the top 7 sprite rows are
//  written; the sprite is shown double size.
// ----------------------------------------------------------------------------
render_digits:
    lda dig0
    asl
    asl
    asl
    sta fnt0
    lda dig1
    asl
    asl
    asl
    sta fnt1
    lda dig2
    asl
    asl
    asl
    sta fnt2
    lda dig3
    asl
    asl
    asl
    sta fnt3
    ldy #0                             // byte offset into the sprite
    ldx #0                             // glyph row 0-6
rd_row:
    stx rowi
    lda fnt0
    clc
    adc rowi
    tax
    lda font_rows,x
    sta gly0
    lda fnt1
    clc
    adc rowi
    tax
    lda font_rows,x
    sta gly1
    lda fnt2
    clc
    adc rowi
    tax
    lda font_rows,x
    sta gly2
    lda fnt3
    clc
    adc rowi
    tax
    lda font_rows,x
    sta gly3
    // sprite byte 0 = glyph 0 at x 0-4, glyph 1 top two bits at x 6-7
    lda gly0
    asl
    asl
    asl
    sta tmpv
    lda gly1
    lsr
    lsr
    lsr
    ora tmpv
    sta (ptr_dst),y
    iny
    // byte 1 = rest of glyph 1 (x 8-10), glyph 2 top four bits (x 12-15)
    lda gly1
    and #7
    asl
    asl
    asl
    asl
    asl
    sta tmpv
    lda gly2
    lsr
    ora tmpv
    sta (ptr_dst),y
    iny
    // byte 2 = last bit of glyph 2 (x 16), glyph 3 at x 18-22
    lda gly2
    lsr                                // carry = last bit
    lda #0
    ror                                // moves it to bit 7
    sta tmpv
    lda gly3
    asl
    ora tmpv
    sta (ptr_dst),y
    iny
    ldx rowi
    inx
    cpx #7
    beq rd_done
    jmp rd_row
rd_done:
    rts

// ----------------------------------------------------------------------------
//  Balloons. Five slots (sprites 3-7). b_y = 0 means the slot is free.
//  They rise a few pixels a frame (balloon_speeds, by colour) in front of the ledges. Touching
//  one removes it and scores 200.
// ----------------------------------------------------------------------------
update_balloons:
    jsr spawn_tick
    dec banim_timer
    bne ub_ptr
    lda #BALLOON_ANIM_DELAY
    sta banim_timer
    lda banim_index
    clc
    adc #1
    and #3
    sta banim_index
ub_ptr:
    ldx banim_index
    lda anim_sequence,x
    clc
    adc #(balloon_frames/64)
    sta balloon_ptr
    lda #7
    ora bird_en                        // sprite 7 is the bird
    sta emask
    lda bird_msb
    sta msbmask
    ldx #3                             // balloon slots 0-3 = sprites 3-6
ub_loop:
    lda b_y,x
    bne !+
    jmp ub_next
!:
    sec
    sbc b_speed,x
    cmp #BALLOON_TOP
    bcs ub_alive
    lda #0                             // floated off the top
    sta b_y,x
    sta b_speed,x
    jmp ub_next
ub_alive:
    sta b_y,x
    cmp #HIT_Y_MIN                     // level with the diver?
    bcc ub_show
    cmp #(HIT_Y_MAX+1)
    bcs ub_show
    sec                                // balloon X minus diver X (9 bit)
    lda b_xl,x
    sbc player_x_lo
    sta tmpv
    lda b_xh,x
    sbc player_x_hi
    beq ub_right
    cmp #$ff
    bne ub_show
    lda tmpv                           // balloon to the left
    cmp #(256-HIT_DX)
    bcs ub_hit
    bcc ub_show
ub_right:
    lda tmpv                           // balloon to the right (or level)
    cmp #(HIT_DX+1)
    bcs ub_show
ub_hit:
    lda #0                             // pop!
    sta b_y,x
    sta b_speed,x
    txa
    pha
    lda #0
    ldx #BALLOON_POINTS_HI
    jsr add_score
    pla
    tax
    jmp ub_next
ub_show:
    txa
    asl
    tay
    lda b_y,x
    sta VIC_SPR3_Y,y
    lda b_xl,x
    sta VIC_SPR3_X,y
    lda balloon_ptr
    sta SPRITE_PTR3,x
    lda emask
    ora slot_bit,x
    sta emask
    lda b_xh,x
    beq ub_next
    lda msbmask
    ora slot_bit,x
    sta msbmask
ub_next:
    dex
    bmi ub_end
    jmp ub_loop
ub_end:
    lda emask
    sta VIC_SPR_ENABLE
    jmp update_sprite_x                // sets the X bit 8s

// spawn_tick: count down to the next balloon
spawn_tick:
    lda spawn_lo
    bne st_lo
    dec spawn_hi
st_lo:
    dec spawn_lo
    lda spawn_lo
    ora spawn_hi
    bne st_done
    jsr spawn_balloon
    jmp set_spawn_interval
st_done:
    rts

// set_spawn_interval: 3 to 6 seconds, in frames, random
set_spawn_interval:
    lda #0
    ldx #BALLOON_RANGE_SEC
ssi_range:
    clc
    adc fps
    dex
    bne ssi_range
    sta tmpv                           // range in frames
    lda #0
    ldx #BALLOON_MIN_SEC
ssi_base:
    clc
    adc fps
    dex
    bne ssi_base
    sta tmpv2                          // minimum in frames
    jsr get_random
    cmp tmpv
    bcc ssi_ok
    sbc tmpv                           // 0-255 folded into 0..range-1
ssi_ok:
    clc
    adc tmpv2
    sta spawn_lo
    lda #0
    adc #0
    sta spawn_hi
    rts

// spawn_balloon: new balloon in a free slot, at a random column
spawn_balloon:
    ldx #3
sb_find:
    lda b_y,x
    beq sb_found
    dex
    bpl sb_find
    rts                                // all slots busy: skip this one
sb_found:
    jsr get_random                     // column 0-30 within the walls
    and #31
    cmp #31
    bcc sb_col
    sbc #31
sb_col:
    sta tmpv
    lda #0
    sta b_xh,x
    lda tmpv
    asl                                // x = column * 8 (9 bit)
    rol b_xh,x
    asl
    rol b_xh,x
    asl
    rol b_xh,x
    sta b_xl,x
    jsr get_random                     // plus 0-7 pixels of jitter
    and #7
    clc
    adc b_xl,x
    sta b_xl,x
    bcc sb_jit
    inc b_xh,x
sb_jit:
    lda b_xl,x                         // plus the left wall
    clc
    adc #X_MIN
    sta b_xl,x
    bcc sb_edge
    inc b_xh,x
sb_edge:
    lda #BALLOON_START_Y
    sta b_y,x
    jsr get_random
    and #3
    tay
    lda balloon_colors,y
    sta VIC_SPR3_COLOR,x
    lda balloon_speeds,y
    sta b_speed,x
    rts

slot_bit:
    .byte %00001000, %00010000, %00100000, %01000000, %10000000
balloon_colors:
    .byte 2, 4, 5, 10                  // red, purple, green, light red
balloon_speeds:
    .byte 3, 2, 3, 4                   // purple is slow, red and green are normal, light red  is fast


// ----------------------------------------------------------------------------
//  The bird (sprite 7). Every 10-17 seconds one flaps across the screen at a
//  random height, bobbing up and down with each wing beat. It is in front of
//  everything. Touching it is fatal. Runs before update_balloons, which
//  folds bird_en / bird_msb into the sprite enable and X bit 8 registers.
// ----------------------------------------------------------------------------
set_bird_wait:
    jsr get_random
    and #BIRD_RANGE_MASK
    clc
    adc #BIRD_MIN_SEC
    sta bird_wait
    rts

spawn_bird:
    lda #1
    sta bird_active
    jsr get_random
    and #1
    sta bird_dir                       // 0 = flies right, 1 = flies left
    bne sbd_left
    lda #0                             // start hidden behind the left border
    sta bird_xl
    sta bird_xh
    beq sbd_y
sbd_left:
    lda #<344                          // start hidden behind the right border
    sta bird_xl
    lda #>344
    sta bird_xh
sbd_y:
    jsr get_random
    and #BIRD_Y_MASK
    clc
    adc #BIRD_Y_MIN
    sta bird_y
    lda #0
    sta bird_anim
    lda #BIRD_ANIM_DELAY
    sta bird_timer
    lda #COL_BIRD
    sta VIC_SPR7_COLOR
    rts

// update_bird: returns carry set if the bird hit the diver
update_bird:
    lda bird_active
    bne bird_fly
    clc
    rts
bird_fly:
    lda bird_dir
    bne bird_left
    clc                                // flying right
    lda bird_xl
    adc #BIRD_SPEED
    sta bird_xl
    lda bird_xh
    adc #0
    sta bird_xh
    beq bird_flap
    lda bird_xl
    cmp #<344
    bcc bird_flap
    jmp bird_gone                      // behind the right border
bird_left:
    sec                                // flying left
    lda bird_xl
    sbc #BIRD_SPEED
    sta bird_xl
    lda bird_xh
    sbc #0
    sta bird_xh
    bmi bird_left_gone
    ora bird_xl
    bne bird_flap
bird_left_gone:
    jmp bird_gone                      // behind the left border
bird_flap:
    dec bird_timer
    bne bird_show
    lda #BIRD_ANIM_DELAY
    sta bird_timer
    lda bird_anim
    clc
    adc #1
    and #3
    sta bird_anim
bird_show:
    ldx bird_anim
    lda anim_sequence,x                // wings up, level, down, level
    ldy bird_dir
    beq bird_ptr
    clc
    adc #3                             // second set of frames faces left
bird_ptr:
    clc
    adc #(bird_frames/64)
    sta SPRITE_PTR7
    lda bird_y                         // bob with the wing beat
    clc
    adc bird_bob,x
    sta bird_ysc
    sta VIC_SPR7_Y
    lda bird_xl
    sta VIC_SPR7_X
    lda #%10000000
    sta bird_en
    lda #0
    sta bird_msb
    lda bird_xh
    beq bird_hit_test
    lda #%10000000
    sta bird_msb
bird_hit_test:
    lda bird_ysc                       // level with the diver?
    cmp #BIRD_HIT_Y_MIN
    bcc bird_miss
    cmp #(BIRD_HIT_Y_MAX + 1)
    bcs bird_miss
    sec                                // bird X minus diver X (9 bit)
    lda bird_xl
    sbc player_x_lo
    sta tmpv
    lda bird_xh
    sbc player_x_hi
    beq bird_right_of
    cmp #$ff
    bne bird_miss
    lda tmpv                           // bird to the left
    cmp #(256 - BIRD_HIT_DX)
    bcs bird_hit
    bcc bird_miss
bird_right_of:
    lda tmpv
    cmp #(BIRD_HIT_DX + 1)
    bcs bird_miss
bird_hit:
    sec
    rts
bird_miss:
    clc
    rts
bird_gone:
    lda #0
    sta bird_active
    sta bird_en
    sta bird_msb
    clc
    rts

bird_bob:
    .byte 3, 0, -3, 0                  // body dips with wings up, rises on the downstroke

// ----------------------------------------------------------------------------
//  The splash. start_splash: the diver has touched the water. Score the
//  landing, put the diver behind the water (so the pail swallows him as the
//  shaft keeps scrolling for SINK_FRAMES), and throw up five droplets, using
//  the balloon sprites and arrays: b_y = Y, b_xl/b_xh = X, b_speed = vertical
//  speed (signed, negative = up), b_vx = horizontal speed (signed).
// ----------------------------------------------------------------------------
start_splash:
    lda #0                             // the bird flies off: its sprite becomes a droplet
    sta bird_active
    sta bird_en
    sta bird_msb
    lda #SPLASH_FRAMES
    sta splash
    lda #1
    sta VIC_SPR_PRIO                   // diver (sprite 0) behind the water
    lda #SURFACE_Y
    sta water_y
    lda #0
    ldx #LAND_BONUS_HI
    jsr add_score
    ldx #4
ss_loop:
    lda player_x_lo
    sta b_xl,x
    lda player_x_hi
    sta b_xh,x
    lda splash_dx,x
    jsr add_drop_x                     // start beside the diver
    lda water_y                        // start just above the water
    sec
    sbc #18
    sta b_y,x
    lda splash_vy,x
    sta b_speed,x
    lda splash_vx,x
    sta b_vx,x
    lda splash_colors,x
    sta VIC_SPR3_COLOR,x
    dex
    bpl ss_loop
    // fall into the first splash frame

splash_frame:
    jsr animate_water
    jsr splash_update
    lda splash
    cmp #(SPLASH_FRAMES - SINK_FRAMES)
    bcc sf_still                       // the diver is under: stop scrolling
    jsr scroll_shaft
    lda water_y                        // the water rises with the shaft
    sec
    sbc #SCROLL_SPEED
    sta water_y
sf_still:
    jsr hud_update
    dec splash
    beq sf_end
    jmp game_loop
sf_end:
    jmp landed

// splash_update: move the droplets (ballistic arcs) and show them
splash_update:
    lda splash
    cmp #(SPLASH_FRAMES - SINK_FRAMES)
    lda #7
    bcs su_emask
    lda #6                             // fully under: hide the diver sprite
su_emask:
    sta emask
    lda water_y                        // droplets vanish into the water
    sec
    sbc #14
    sta tmpv2
    lda #0
    sta msbmask
    ldx #4
su_loop:
    lda b_y,x
    beq su_next
    clc
    adc b_speed,x                      // Y += vertical speed (signed)
    sta b_y,x
    lda splash
    and #3
    bne su_move
    inc b_speed,x                      // gravity, every 4th frame
su_move:
    lda b_speed,x
    bmi su_show                        // still rising
    lda b_y,x
    cmp tmpv2
    bcc su_show
    lda #0                             // back in the water
    sta b_y,x
    beq su_next
su_show:
    lda b_vx,x
    jsr add_drop_x
    txa
    asl
    tay
    lda b_y,x
    sta VIC_SPR3_Y,y
    lda b_xl,x
    sta VIC_SPR3_X,y
    lda #(drop_frame/64)
    sta SPRITE_PTR3,x
    lda emask
    ora slot_bit,x
    sta emask
    lda b_xh,x
    beq su_next
    lda msbmask
    ora slot_bit,x
    sta msbmask
su_next:
    dex
    bpl su_loop
    lda emask
    sta VIC_SPR_ENABLE
    jmp update_sprite_x

// add_drop_x: slot X's 9-bit X position += A (signed). Keeps X.
add_drop_x:
    sta tmpv
    clc
    adc b_xl,x
    sta b_xl,x
    lda tmpv
    bmi adx_neg
    lda #0
    beq adx_hi
adx_neg:
    lda #$ff
adx_hi:
    adc b_xh,x
    and #1
    sta b_xh,x
    rts

splash_dx:      .byte -18, -8, 0, 8, 18
splash_vx:      .byte -2, -1, 0, 1, 2
splash_vy:      .byte -3, -4, -5, -4, -3
splash_colors:  .byte 1, 3, 14, 3, 1   // white, cyan, light blue

// ----------------------------------------------------------------------------
//  Water ripple: the two surface characters swap shape every WAVE_DELAY frames
// ----------------------------------------------------------------------------
animate_water:
    dec wave_timer
    bne aw_done
    lda #WAVE_DELAY
    sta wave_timer
    lda wave_phase
    eor #1
    sta wave_phase
put_wave:
    lda wave_phase
    asl
    asl
    asl
    asl                                // 16 bytes per phase
    tax
    ldy #0
pw_loop:
    lda wave_data,x
    sta CHARSET + CH_SURF_A*8,y
    inx
    iny
    cpy #16
    bne pw_loop
aw_done:
    rts

wave_data:
    .byte $00, $0c, $33, $ff, $ff, $ff, $ff, $ff     // surface A
    .byte $00, $30, $cc, $ff, $ff, $ff, $ff, $ff     // surface B
    .byte $00, $30, $cc, $ff, $ff, $ff, $ff, $ff     // (phase 2: swapped)
    .byte $00, $0c, $33, $ff, $ff, $ff, $ff, $ff

// ----------------------------------------------------------------------------
//  setup_charset: copy the ROM characters to RAM (so text still works), then
//  redefine the ledge/floor block and add the pail characters. These are
//  multicolour characters: each 2-pixel pair is %00 background, %01 orange,
//  %10 brown or %11 the cell colour (water). Pairs %10 and %11 count as
//  solid for sprite collisions and hide sprites that are set behind them.
// ----------------------------------------------------------------------------
setup_charset:
    lda CPU_PORT
    and #%11111011                     // character ROM visible at $d000
    sta CPU_PORT
    ldx #0
sc_copy:
    lda $d000,x
    sta CHARSET,x
    lda $d100,x
    sta CHARSET+$100,x
    lda $d200,x
    sta CHARSET+$200,x
    lda $d300,x
    sta CHARSET+$300,x
    lda $d400,x
    sta CHARSET+$400,x
    lda $d500,x
    sta CHARSET+$500,x
    lda $d600,x
    sta CHARSET+$600,x
    lda $d700,x
    sta CHARSET+$700,x
    inx
    bne sc_copy
    lda CPU_PORT
    ora #%00000100                     // I/O back
    sta CPU_PORT
    ldx #7
sc_solid:
    lda #$aa                           // all %10: solid brown
    sta CHARSET + CH_SOLID*8,x
    dex
    bpl sc_solid
    ldx #(9*8 - 1)
sc_custom:
    lda custom_glyphs,x
    sta CHARSET + CH_WOOD_A*8,x
    dex
    bpl sc_custom
    rts

custom_glyphs:
    .byte $a9, $a9, $a9, $a9, $a9, $a9, $a9, $a9     // wood plank
    .byte $a6, $a6, $a6, $a6, $a6, $a6, $a6, $a6     // wood plank, grain elsewhere
    .byte $55, $aa, $aa, $aa, $aa, $aa, $a9, $a9     // rim
    .byte $00, $0c, $33, $ff, $ff, $ff, $ff, $ff     // water surface A
    .byte $00, $30, $cc, $ff, $ff, $ff, $ff, $ff     // water surface B
    .byte $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff     // water
    .byte $aa, $55, $55, $55, $55, $55, $55, $aa     // iron hoop (orange band)
    .byte $55, $aa, $aa, $aa, $aa, $aa, $aa, $55     // floating ledge (light edges)
    .byte $55, $fd, $fd, $fd, $55, $df, $df, $df     // brick wall: red bricks, orange mortar

// ----------------------------------------------------------------------------
//  get_random: A = random byte (SID voice 3 noise)
// ----------------------------------------------------------------------------
get_random:
    lda SID_V3_OSC
    rts

// ----------------------------------------------------------------------------
//  print_text: A/X = address of a message record (screen address word, then
//  screen codes, then $ff). Prints it in white.
// ----------------------------------------------------------------------------
print_text:
    sta ptr_src
    stx ptr_src+1
    ldy #0
    lda (ptr_src),y                    // destination, low byte
    sta ptr_dst
    sta ptr_col
    iny
    lda (ptr_src),y                    // destination, high byte
    sta ptr_dst+1
    clc
    adc #>(COLOR_RAM - SCREEN)         // same cell in colour RAM
    sta ptr_col+1

    clc                                // step the source over the address word
    lda ptr_src
    adc #2
    sta ptr_src
    lda ptr_src+1
    adc #0
    sta ptr_src+1

    ldy #0
print_loop:
    lda (ptr_src),y
    cmp #$ff
    beq print_done
    sta (ptr_dst),y
    lda #COL_TEXT
    sta (ptr_col),y
    iny
    bne print_loop
print_done:
    rts

// ----------------------------------------------------------------------------
//  5x7 digit font, 8 bytes per glyph (digits 0-9, then 10 = blank)
// ----------------------------------------------------------------------------
font_rows:
    .byte %01110, %10001, %10011, %10101, %11001, %10001, %01110, 0   // 0
    .byte %00100, %01100, %00100, %00100, %00100, %00100, %01110, 0   // 1
    .byte %01110, %10001, %00001, %00010, %00100, %01000, %11111, 0   // 2
    .byte %11110, %00001, %00001, %01110, %00001, %00001, %11110, 0   // 3
    .byte %00010, %00110, %01010, %10010, %11111, %00010, %00010, 0   // 4
    .byte %11111, %10000, %11110, %00001, %00001, %10001, %01110, 0   // 5
    .byte %00110, %01000, %10000, %11110, %10001, %10001, %01110, 0   // 6
    .byte %11111, %00001, %00010, %00100, %01000, %01000, %01000, 0   // 7
    .byte %01110, %10001, %10001, %01110, %10001, %10001, %01110, 0   // 8
    .byte %01110, %10001, %10001, %01111, %00001, %00010, %01100, 0   // 9
    .byte %00000, %00000, %00000, %00000, %00000, %00000, %00000, 0   // blank

// ----------------------------------------------------------------------------
//  Messages
// ----------------------------------------------------------------------------
.encoding "screencode_upper"

txt_title:
    .word SCREEN + 4*40 + 16
    .text "NOSEDIVE"
    .byte $ff
txt_help1:
    .word SCREEN + 7*40 + 3
    .text "DIVE HEAD FIRST. AVOID THE LEDGES."
    .byte $ff
txt_help2:
    .word SCREEN + 9*40 + 8
    .text "REACH THE GROUND TO WIN."
    .byte $ff
txt_help3:
    .word SCREEN + 19*40 + 5
    .text "JOYSTICK PORT 2: LEFT / RIGHT"
    .byte $ff
txt_start:
    .word SCREEN + 21*40 + 10
    .text "PRESS FIRE TO START"
    .byte $ff
txt_landed:
    .word SCREEN + 5*40 + 11
    .text "YOU LANDED SAFELY!"
    .byte $ff
txt_again:
    .word SCREEN + 7*40 + 8
    .text "PRESS FIRE TO PLAY AGAIN"
    .byte $ff
txt_crashed:
    .word SCREEN + 5*40 + 15
    .text "GAME OVER"
    .byte $ff
txt_retry:
    .word SCREEN + 7*40 + 8
    .text "PRESS FIRE TO TRY AGAIN"
    .byte $ff

// ----------------------------------------------------------------------------
//  Variables
// ----------------------------------------------------------------------------
yscroll:        .byte 0                // current vertical fine scroll, 0-7
anim_timer:     .byte 0
anim_index:     .byte 0
ground_seen:    .byte 0                // 1 once the ground has started to appear
rows_lo:        .byte 0                // rows still to build before the ground
rows_hi:        .byte 0
ledge_wait:     .byte 0                // blank rows still to go before the next ledge
seg1_s:         .byte 0                // candidate row: ledge 1 start column and length
seg1_n:         .byte 0
seg2_s:         .byte 0                // ledge 2 (0 length = none)
seg2_n:         .byte 0
w1:             .byte 0
w2:             .byte 0
free_lo:        .byte 0                // (double rows: gap start)
pi_n:           .byte 0                // last ledge row: number of open spaces ...
pi_a:           .fill 2, 0             // ... and the range of left-hand columns in each
pi_b:           .fill 2, 0
ci_n:           .byte 0                // candidate row: the same
ci_a:           .fill 2, 0
ci_b:           .fill 2, 0
ja:             .byte 0
jb:             .byte 0
dpp:            .byte 0
chk_p:          .byte 0
gap_w:          .byte 0
tries:          .byte 0
is_pal:         .byte 0
fps:            .byte 50
fps_count:      .byte 0
seconds:        .byte 0
score_lo:       .byte 0                // BCD: tens, units
score_dirty:    .byte 0                // HUD sprites needing a redraw
time_dirty:     .byte 0
shifted:        .byte 0                // 1 if this frame shifted the screen
row_ready:      .byte 0                // 1 when row_buf holds the next shaft row
row_buf:        .fill 40, 0
splash:         .byte 0                // frames of splash left (0 = not landed yet)
pail_step:      .byte 0                // which pail row is next
pk:             .byte 0
pa:             .byte 0
pb:             .byte 0
wave_timer:     .byte 0
wave_phase:     .byte 0
bird_active:    .byte 0
bird_wait:      .byte 0                // seconds until the next bird
bird_dir:       .byte 0
bird_xl:        .byte 0
bird_xh:        .byte 0
bird_y:         .byte 0
bird_ysc:       .byte 0                // Y on screen: bird_y plus the wing-beat bob
bird_anim:      .byte 0
bird_timer:     .byte 0
bird_en:        .byte 0                // sprite 7 enable bit while a bird is out
bird_msb:       .byte 0                // and its X bit 8
water_y:        .byte 0                // screen Y of the water surface during the splash
score_hi:       .byte 0                // BCD: thousands, hundreds
dig0:           .byte 0                // glyph numbers for render_digits
dig1:           .byte 0
dig2:           .byte 0
dig3:           .byte 0
fnt0:           .byte 0
fnt1:           .byte 0
fnt2:           .byte 0
fnt3:           .byte 0
gly0:           .byte 0
gly1:           .byte 0
gly2:           .byte 0
gly3:           .byte 0
rowi:           .byte 0
tmpv:           .byte 0
tmpv2:          .byte 0
spawn_lo:       .byte 0                // frames until the next balloon
spawn_hi:       .byte 0
banim_timer:    .byte 0
banim_index:    .byte 0
balloon_ptr:    .byte 0
emask:          .byte 0                // sprite enable bits being built
msbmask:        .byte 0                // balloons' X bit 8s
b_y:            .fill 5, 0             // balloon slots: Y (0 = free), X low, X bit 8
b_xl:           .fill 5, 0
b_xh:           .fill 5, 0
b_speed:        .fill 5, 0             // balloon speeds
b_vx:           .fill 5, 0             // droplet sideways speeds
player_x_lo:    .byte 0
player_x_hi:    .byte 0

// ----------------------------------------------------------------------------
//  Diver sprite: three 24x21 frames, head pointing down the screen.
//  Sprite data must be 64-byte aligned and outside $1000-$1fff, where the VIC
//  sees the character ROM instead of RAM. $2000 up is fine.
// ----------------------------------------------------------------------------
* = $2000 "Sprites"
sprite_frames:
// frame 0
.byte %00000110, %00000000, %01100000   // .....##..........##.....
.byte %00000011, %00000000, %11000000   // ......##........##......
.byte %00000001, %10000001, %10000000   // .......##......##.......
.byte %00000000, %11000011, %00000000   // ........##....##........
.byte %00000000, %01100110, %00000000   // .........##..##.........
.byte %00000000, %00111100, %00000000   // ..........####..........
.byte %00000000, %00111100, %00000000   // ..........####..........
.byte %00000000, %00111100, %00000000   // ..........####..........
.byte %00000000, %00111100, %00000000   // ..........####..........
.byte %00000000, %00111100, %00000000   // ..........####..........
.byte %00000000, %00111100, %00000000   // ..........####..........
.byte %01111111, %11111111, %11111110   // .######################.
.byte %11111111, %11111111, %11111111   // ########################
.byte %10000000, %00111100, %00000001   // #.........####.........#
.byte %00000000, %00111100, %00000000   // ..........####..........
.byte %00000000, %01111110, %00000000   // .........######.........
.byte %00000000, %11111111, %00000000   // ........########........
.byte %00000000, %11111111, %00000000   // ........########........
.byte %00000000, %11111111, %00000000   // ........########........
.byte %00000000, %01111110, %00000000   // .........######.........
.byte %00000000, %00111100, %00000000   // ..........####..........
.byte 0
// frame 1
.byte %00000000, %11000011, %00000000   // ........##....##........
.byte %00000000, %11000011, %00000000   // ........##....##........
.byte %00000000, %01100110, %00000000   // .........##..##.........
.byte %00000000, %01100110, %00000000   // .........##..##.........
.byte %00000000, %00111100, %00000000   // ..........####..........
.byte %00000000, %00111100, %00000000   // ..........####..........
.byte %00110000, %00111100, %00001100   // ..##......####......##..
.byte %00011000, %00111100, %00011000   // ...##.....####.....##...
.byte %00001100, %00111100, %00110000   // ....##....####....##....
.byte %00000111, %00111100, %11100000   // .....###..####..###.....
.byte %00000001, %10111101, %10000000   // .......##.####.##.......
.byte %00000000, %11111111, %00000000   // ........########........
.byte %00000000, %01111110, %00000000   // .........######.........
.byte %00000000, %00111100, %00000000   // ..........####..........
.byte %00000000, %00111100, %00000000   // ..........####..........
.byte %00000000, %01111110, %00000000   // .........######.........
.byte %00000000, %11111111, %00000000   // ........########........
.byte %00000000, %11111111, %00000000   // ........########........
.byte %00000000, %11111111, %00000000   // ........########........
.byte %00000000, %01111110, %00000000   // .........######.........
.byte %00000000, %00111100, %00000000   // ..........####..........
.byte 0
// frame 2
.byte %00000000, %00111100, %00000000   // ..........####..........
.byte %00000000, %00111100, %00000000   // ..........####..........
.byte %00000000, %00111100, %00000000   // ..........####..........
.byte %00000011, %00111100, %11000000   // ......##..####..##......
.byte %00000011, %00111100, %11000000   // ......##..####..##......
.byte %00000001, %10111101, %10000000   // .......##.####.##.......
.byte %00000001, %10111101, %10000000   // .......##.####.##.......
.byte %00000001, %10111101, %10000000   // .......##.####.##.......
.byte %00000000, %11111111, %00000000   // ........########........
.byte %00000000, %11111111, %00000000   // ........########........
.byte %00000000, %11111111, %00000000   // ........########........
.byte %00000000, %01111110, %00000000   // .........######.........
.byte %00000000, %01111110, %00000000   // .........######.........
.byte %00000000, %00111100, %00000000   // ..........####..........
.byte %00000000, %00111100, %00000000   // ..........####..........
.byte %00000000, %01111110, %00000000   // .........######.........
.byte %00000000, %11111111, %00000000   // ........########........
.byte %00000000, %11111111, %00000000   // ........########........
.byte %00000000, %11111111, %00000000   // ........########........
.byte %00000000, %01111110, %00000000   // .........######.........
.byte %00000000, %00111100, %00000000   // ..........####..........
.byte 0

// ----------------------------------------------------------------------------
//  Balloon: three 24x21 frames. The body sways one way while the string
//  wiggles the other.
// ----------------------------------------------------------------------------
balloon_frames:
// balloon frame 0: body left, string swings right
.byte %00000001, %11111000, %00000000   // .......######...........
.byte %00000111, %11111110, %00000000   // .....##########.........
.byte %00001100, %11111111, %00000000   // ....##..########........
.byte %00011100, %11111111, %10000000   // ...###..#########.......
.byte %00011111, %11111111, %10000000   // ...##############.......
.byte %00011111, %11111111, %10000000   // ...##############.......
.byte %00011111, %11111111, %10000000   // ...##############.......
.byte %00011111, %11111111, %10000000   // ...##############.......
.byte %00001111, %11111111, %00000000   // ....############........
.byte %00001111, %11111111, %00000000   // ....############........
.byte %00000111, %11111110, %00000000   // .....##########.........
.byte %00000011, %11111100, %00000000   // ......########..........
.byte %00000001, %11111000, %00000000   // .......######...........
.byte %00000000, %11110000, %00000000   // ........####............
.byte %00000000, %01100000, %00000000   // .........##.............
.byte %00000000, %01100000, %00000000   // .........##.............
.byte %00000000, %00110000, %00000000   // ..........##............
.byte %00000000, %00011000, %00000000   // ...........##...........
.byte %00000000, %00001100, %00000000   // ............##..........
.byte %00000000, %00001100, %00000000   // ............##..........
.byte %00000000, %00011000, %00000000   // ...........##...........
.byte 0
// balloon frame 1: centred
.byte %00000000, %01111110, %00000000   // .........######.........
.byte %00000001, %11111111, %10000000   // .......##########.......
.byte %00000011, %00111111, %11000000   // ......##..########......
.byte %00000111, %00111111, %11100000   // .....###..#########.....
.byte %00000111, %11111111, %11100000   // .....##############.....
.byte %00000111, %11111111, %11100000   // .....##############.....
.byte %00000111, %11111111, %11100000   // .....##############.....
.byte %00000111, %11111111, %11100000   // .....##############.....
.byte %00000011, %11111111, %11000000   // ......############......
.byte %00000011, %11111111, %11000000   // ......############......
.byte %00000001, %11111111, %10000000   // .......##########.......
.byte %00000000, %11111111, %00000000   // ........########........
.byte %00000000, %01111110, %00000000   // .........######.........
.byte %00000000, %00111100, %00000000   // ..........####..........
.byte %00000000, %00011000, %00000000   // ...........##...........
.byte %00000000, %00011000, %00000000   // ...........##...........
.byte %00000000, %00110000, %00000000   // ..........##............
.byte %00000000, %00011000, %00000000   // ...........##...........
.byte %00000000, %00001100, %00000000   // ............##..........
.byte %00000000, %00011000, %00000000   // ...........##...........
.byte %00000000, %00110000, %00000000   // ..........##............
.byte 0
// balloon frame 2: body right, string swings left
.byte %00000000, %00011111, %10000000   // ...........######.......
.byte %00000000, %01111111, %11100000   // .........##########.....
.byte %00000000, %11001111, %11110000   // ........##..########....
.byte %00000001, %11001111, %11111000   // .......###..#########...
.byte %00000001, %11111111, %11111000   // .......##############...
.byte %00000001, %11111111, %11111000   // .......##############...
.byte %00000001, %11111111, %11111000   // .......##############...
.byte %00000001, %11111111, %11111000   // .......##############...
.byte %00000000, %11111111, %11110000   // ........############....
.byte %00000000, %11111111, %11110000   // ........############....
.byte %00000000, %01111111, %11100000   // .........##########.....
.byte %00000000, %00111111, %11000000   // ..........########......
.byte %00000000, %00011111, %10000000   // ...........######.......
.byte %00000000, %00001111, %00000000   // ............####........
.byte %00000000, %00000110, %00000000   // .............##.........
.byte %00000000, %00000110, %00000000   // .............##.........
.byte %00000000, %00001100, %00000000   // ............##..........
.byte %00000000, %00011000, %00000000   // ...........##...........
.byte %00000000, %00110000, %00000000   // ..........##............
.byte %00000000, %00110000, %00000000   // ..........##............
.byte %00000000, %00011000, %00000000   // ...........##...........
.byte 0

// HUD sprites, redrawn by render_digits (64 bytes each, start empty)
score_sprite:
    .fill 64, 0
time_sprite:
    .fill 64, 0

// Splash droplet: a small round blob in the middle of the sprite
drop_frame:
    .fill 18, 0
    .byte %00000000, %00111100, %00000000   // ..........####..........
    .byte %00000000, %01111110, %00000000   // .........######.........
    .byte %00000000, %11111111, %00000000   // ........########........
    .byte %00000000, %11111111, %00000000   // ........########........
    .byte %00000000, %11111111, %00000000   // ........########........
    .byte %00000000, %11111111, %00000000   // ........########........
    .byte %00000000, %01111110, %00000000   // .........######.........
    .byte %00000000, %00111100, %00000000   // ..........####..........
    .fill 22, 0

// Bird: wings up, level, down - first facing right, then facing left
bird_frames:
// bird right, wings up
.byte %00001000, %00000000, %00000000   // ....#...................
.byte %00000100, %00000000, %00000000   // .....#..................
.byte %00000110, %00000000, %00000000   // .....##.................
.byte %00000011, %00000000, %00000000   // ......##................
.byte %00000011, %10000000, %00000000   // ......###...............
.byte %00000011, %11000000, %00000000   // ......####..............
.byte %00000001, %11100000, %01111000   // .......####......####...
.byte %00000001, %11110000, %11101100   // .......#####....###.##..
.byte %00000001, %11111111, %11111110   // .......################.
.byte %00000111, %11111111, %11111110   // .....##################.
.byte %00011111, %11111111, %11111100   // ...###################..
.byte %01111111, %11111111, %11100000   // .##################.....
.byte %00011111, %11111111, %11000000   // ...###############......
.byte %00000001, %11111111, %10000000   // .......##########.......
.byte %00000000, %00000000, %00000000   // ........................
.byte %00000000, %00000000, %00000000   // ........................
.byte %00000000, %00000000, %00000000   // ........................
.byte %00000000, %00000000, %00000000   // ........................
.byte %00000000, %00000000, %00000000   // ........................
.byte %00000000, %00000000, %00000000   // ........................
.byte %00000000, %00000000, %00000000   // ........................
.byte 0
// bird right, wings level
.byte %00000000, %00000000, %00000000   // ........................
.byte %00000000, %00000000, %00000000   // ........................
.byte %00000000, %00000000, %00000000   // ........................
.byte %00000000, %00000000, %00000000   // ........................
.byte %00000000, %00000000, %00000000   // ........................
.byte %00000000, %00000000, %00000000   // ........................
.byte %00000000, %00000000, %01111000   // .................####...
.byte %00011100, %00000000, %11101100   // ...###..........###.##..
.byte %00000011, %11111111, %11111110   // ......#################.
.byte %00000111, %11111111, %11111110   // .....##################.
.byte %00011111, %11111111, %11111100   // ...###################..
.byte %01111111, %11111111, %11100000   // .##################.....
.byte %00011111, %11111111, %11000000   // ...###############......
.byte %00000001, %11111111, %10000000   // .......##########.......
.byte %00000000, %00000000, %00000000   // ........................
.byte %00000000, %00000000, %00000000   // ........................
.byte %00000000, %00000000, %00000000   // ........................
.byte %00000000, %00000000, %00000000   // ........................
.byte %00000000, %00000000, %00000000   // ........................
.byte %00000000, %00000000, %00000000   // ........................
.byte %00000000, %00000000, %00000000   // ........................
.byte 0
// bird right, wings down
.byte %00000000, %00000000, %00000000   // ........................
.byte %00000000, %00000000, %00000000   // ........................
.byte %00000000, %00000000, %00000000   // ........................
.byte %00000000, %00000000, %00000000   // ........................
.byte %00000000, %00000000, %00000000   // ........................
.byte %00000000, %00000000, %00000000   // ........................
.byte %00000000, %00000000, %01111000   // .................####...
.byte %00000000, %00000000, %11101100   // ................###.##..
.byte %00000001, %11111111, %11111110   // .......################.
.byte %00000111, %11111111, %11111110   // .....##################.
.byte %00011111, %11111111, %11111100   // ...###################..
.byte %01111111, %11111111, %11100000   // .##################.....
.byte %00011111, %11111111, %11000000   // ...###############......
.byte %00000001, %11111111, %10000000   // .......##########.......
.byte %00000001, %11100000, %00000000   // .......####.............
.byte %00000011, %11000000, %00000000   // ......####..............
.byte %00000011, %10000000, %00000000   // ......###...............
.byte %00000111, %00000000, %00000000   // .....###................
.byte %00000100, %00000000, %00000000   // .....#..................
.byte %00001000, %00000000, %00000000   // ....#...................
.byte %00000000, %00000000, %00000000   // ........................
.byte 0
// bird left, wings up
.byte %00000000, %00000000, %00010000   // ...................#....
.byte %00000000, %00000000, %00100000   // ..................#.....
.byte %00000000, %00000000, %01100000   // .................##.....
.byte %00000000, %00000000, %11000000   // ................##......
.byte %00000000, %00000001, %11000000   // ...............###......
.byte %00000000, %00000011, %11000000   // ..............####......
.byte %00011110, %00000111, %10000000   // ...####......####.......
.byte %00110111, %00001111, %10000000   // ..##.###....#####.......
.byte %01111111, %11111111, %10000000   // .################.......
.byte %01111111, %11111111, %11100000   // .##################.....
.byte %00111111, %11111111, %11111000   // ..###################...
.byte %00000111, %11111111, %11111110   // .....##################.
.byte %00000011, %11111111, %11111000   // ......###############...
.byte %00000001, %11111111, %10000000   // .......##########.......
.byte %00000000, %00000000, %00000000   // ........................
.byte %00000000, %00000000, %00000000   // ........................
.byte %00000000, %00000000, %00000000   // ........................
.byte %00000000, %00000000, %00000000   // ........................
.byte %00000000, %00000000, %00000000   // ........................
.byte %00000000, %00000000, %00000000   // ........................
.byte %00000000, %00000000, %00000000   // ........................
.byte 0
// bird left, wings level
.byte %00000000, %00000000, %00000000   // ........................
.byte %00000000, %00000000, %00000000   // ........................
.byte %00000000, %00000000, %00000000   // ........................
.byte %00000000, %00000000, %00000000   // ........................
.byte %00000000, %00000000, %00000000   // ........................
.byte %00000000, %00000000, %00000000   // ........................
.byte %00011110, %00000000, %00000000   // ...####.................
.byte %00110111, %00000000, %00111000   // ..##.###..........###...
.byte %01111111, %11111111, %11000000   // .#################......
.byte %01111111, %11111111, %11100000   // .##################.....
.byte %00111111, %11111111, %11111000   // ..###################...
.byte %00000111, %11111111, %11111110   // .....##################.
.byte %00000011, %11111111, %11111000   // ......###############...
.byte %00000001, %11111111, %10000000   // .......##########.......
.byte %00000000, %00000000, %00000000   // ........................
.byte %00000000, %00000000, %00000000   // ........................
.byte %00000000, %00000000, %00000000   // ........................
.byte %00000000, %00000000, %00000000   // ........................
.byte %00000000, %00000000, %00000000   // ........................
.byte %00000000, %00000000, %00000000   // ........................
.byte %00000000, %00000000, %00000000   // ........................
.byte 0
// bird left, wings down
.byte %00000000, %00000000, %00000000   // ........................
.byte %00000000, %00000000, %00000000   // ........................
.byte %00000000, %00000000, %00000000   // ........................
.byte %00000000, %00000000, %00000000   // ........................
.byte %00000000, %00000000, %00000000   // ........................
.byte %00000000, %00000000, %00000000   // ........................
.byte %00011110, %00000000, %00000000   // ...####.................
.byte %00110111, %00000000, %00000000   // ..##.###................
.byte %01111111, %11111111, %10000000   // .################.......
.byte %01111111, %11111111, %11100000   // .##################.....
.byte %00111111, %11111111, %11111000   // ..###################...
.byte %00000111, %11111111, %11111110   // .....##################.
.byte %00000011, %11111111, %11111000   // ......###############...
.byte %00000001, %11111111, %10000000   // .......##########.......
.byte %00000000, %00000111, %10000000   // .............####.......
.byte %00000000, %00000011, %11000000   // ..............####......
.byte %00000000, %00000001, %11000000   // ...............###......
.byte %00000000, %00000000, %11100000   // ................###.....
.byte %00000000, %00000000, %00100000   // ..................#.....
.byte %00000000, %00000000, %00010000   // ...................#....
.byte %00000000, %00000000, %00000000   // ........................
.byte 0

.errorif bird_frames + 384 > CHARSET, "Sprite data must end before the character set at $2800"
