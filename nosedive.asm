// ============================================================================
//  NOSEDIVE  -  Commodore 64  -  Kick Assembler
//  Version 0.3
//
//  You have jumped off the platform and are diving head first down a shaft.
//  Steer left and right (joystick in port 2) to dodge the ledges that stick
//  out of the left and right walls. Touch one and it's game over.
//  Reach the ground at the bottom and you win - before the clock runs out
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
.const VIC_SPR0_COLOR = $d027
.const VIC_SPR1_COLOR = $d028
.const VIC_SPR2_COLOR = $d029
.const VIC_SPR3_X     = $d006          // balloons use sprites 3-7
.const VIC_SPR3_Y     = $d007
.const VIC_SPR3_COLOR = $d02a
.const SPRITE_PTR1    = $07f9
.const SPRITE_PTR2    = $07fa
.const SPRITE_PTR3    = $07fb

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
.const SCROLL_SPEED   = 2              // pixels per frame the shaft scrolls (1-8)
.const MOVE_SPEED     = 3              // pixels per frame the diver steers sideways
.const TIME_LIMIT     = 60             // seconds from jump to ground
.const LAND_LEAD      = 10             // rows of lead so the ground arrives as the clock hits 0
.const DOUBLE_MASK    = 3              // 1 ledge row in 4 has ledges on both walls
.const DOUBLE_GAP_MIN = 6              // narrow gap is 6-9 columns wide
.const REACH          = 3              // next gap may be at most 3 columns from the last
.const TRIES          = 8              // attempts to find a fair ledge row
.const LEDGE_MIN_LEN  = 11             // ledges are 11-21 columns long
.const LEDGE_GAP_MIN  = 7              // blank rows between ledges: 7-10, so one
                                       // ledge every 8-11 rows
.const START_GAP      = 6              // blank rows before the first ledge
.const END_GAP        = 18             // blank rows between last ledge and ground
.const ANIM_DELAY     = 6              // frames per diver animation step

.const BALLOON_SPEED  = 3              // pixels per frame balloons rise
.const BALLOON_MIN_SEC = 3             // seconds between balloons: 3 to 6
.const BALLOON_RANGE_SEC = 3           // (range x fps must be 128 or more)
.const BALLOON_START_Y = 247           // just below the window: rises into view
.const BALLOON_TOP    = 34             // gone once fully above the window
.const BALLOON_ANIM_DELAY = 8          // frames per balloon animation step
.const BALLOON_POINTS_HI = 2           // 200 points (BCD hundreds)
.const LAND_BONUS_HI  = $10            // 1000 points (BCD thousands)
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
.const X_MIN          = 24             // leftmost sprite X that is fully on screen
.const X_MAX          = 319            // rightmost sprite X that is fully on screen

.const CH_SPACE       = $20
.const CH_SOLID       = $a0            // reverse space = solid block
.const ROW_LAST       = SCREEN + 24*40 // the row new ledges are built on

.const COL_BORDER     = 14             // light blue
.const COL_BACKGROUND = 6              // blue
.const COL_LEDGE      = 9              // brown
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

    // VIC: 40 columns, screen at $0400, ROM character set
    lda #$c8
    sta VIC_CTRL2
    lda #$14
    sta VIC_MEMORY

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

    // Did the diver touch anything during the frame we just displayed?
    lda VIC_SPR_BGHIT
    and #1
    beq still_flying
    lda ground_seen
    bne landed                         // it was the ground: safe landing
    jmp crashed                        // it was a ledge: ouch

still_flying:
    jsr move_diver
    jsr animate_diver
    jsr update_timer
    jsr update_balloons
    jsr scroll_shaft
    jsr hud_update
    jmp game_loop

// ----------------------------------------------------------------------------
//  End of game
// ----------------------------------------------------------------------------
landed:
    lda #0                             // landing bonus
    ldx #LAND_BONUS_HI
    jsr add_score
    jsr render_score                   // show it right away
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

    lda #COL_LEDGE                     // one colour for everything: never scrolled
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

    lda #7                             // fine scroll 7 (24-row mode, display on)
    sta yscroll
    ora #$10
    sta VIC_CTRL1

    lda #ANIM_DELAY
    sta anim_timer
    lda #0
    sta anim_index
    sta ground_seen
    lda #START_GAP
    sta ledge_wait
    lda #0                             // before the first ledge anything is reachable
    sta prev_lo
    lda #39
    sta prev_hi

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
//  new_row: build the next bottom row. The level is a fixed number of rows
//  (rows_lo/hi counts them down) so it lasts TIME_LIMIT seconds: random ledges,
//  then END_GAP clear rows, then solid ground.
// ----------------------------------------------------------------------------
new_row:
    lda ground_seen
    bne row_ground
    lda rows_lo                        // 16-bit decrement of the rows left
    bne nr_dec
    dec rows_hi
nr_dec:
    dec rows_lo
    lda rows_lo
    ora rows_hi
    beq row_ground                     // that was the last row: ground
    lda rows_hi
    bne nr_ledges
    lda rows_lo
    cmp #END_GAP
    bcc row_blank                      // run-out above the ground
nr_ledges:
    lda ledge_wait
    beq row_ledge
    dec ledge_wait

row_blank:
    lda #CH_SPACE
row_fill:
    ldx #39
row_fill_loop:
    sta ROW_LAST,x
    dex
    bpl row_fill_loop
    rts

row_ground:
    lda #1
    sta ground_seen
    lda #CH_SOLID
    jmp row_fill

// ----------------------------------------------------------------------------
//  row_ledge: build a ledge row. Pick a candidate (single ledge from one wall,
//  or ledges from both walls with a narrow gap); accept it only if its free
//  space is within REACH columns of the previous ledge row's free space, so
//  the diver can always get there in time. Otherwise try again, and after
//  TRIES attempts leave the row empty.
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
    jsr row_blank                      // start from an empty row
    ldx ledge_l                        // left wall: columns 0 to ledge_l-1
    beq ledge_no_left
    dex
    lda #CH_SOLID
ledge_left_loop:
    sta ROW_LAST,x
    dex
    bpl ledge_left_loop
ledge_no_left:
    lda ledge_r
    beq ledge_made
    lda #40                            // right wall: columns 40-ledge_r to 39
    sec
    sbc ledge_r
    tax
    lda #CH_SOLID
ledge_right_loop:
    sta ROW_LAST,x
    inx
    cpx #40
    bne ledge_right_loop

ledge_made:
    lda free_lo                        // remember where the free space was
    sta prev_lo
    lda free_hi
    sta prev_hi
    rts

// ----------------------------------------------------------------------------
//  pick_ledge: choose a random candidate row. Sets ledge_l / ledge_r (ledge
//  lengths in columns from the left / right wall) and free_lo / free_hi (the
//  columns left open). Returns carry set if the candidate is usable.
// ----------------------------------------------------------------------------
pick_ledge:
    jsr get_random
    and #DOUBLE_MASK
    beq pick_double

    jsr get_random                     // single ledge: length = MIN + 0..7 + 0..3
    and #7
    sta ledge_len
    jsr get_random
    and #3
    clc
    adc ledge_len
    clc
    adc #LEDGE_MIN_LEN
    sta ledge_len
    jsr get_random                     // bit 7 picks the wall
    bmi pick_right
    lda ledge_len                      // left wall: free columns len..39
    sta ledge_l
    sta free_lo
    lda #0
    sta ledge_r
    lda #39
    sta free_hi
    sec
    rts
pick_right:
    lda #0                             // right wall: free columns 0..39-len
    sta ledge_l
    sta free_lo
    lda #39
    sec
    sbc ledge_len
    sta free_hi
    lda ledge_len
    sta ledge_r
    sec
    rts

pick_double:
    jsr get_random                     // gap width 6-9 columns
    and #3
    clc
    adc #DOUBLE_GAP_MIN
    sta gap_w
    jsr get_random                     // gap starts at column 3-34
    and #31
    clc
    adc #3
    sta ledge_l                        // left ledge fills columns 0..start-1
    sta free_lo
    clc
    adc gap_w                          // first column of the right ledge
    cmp #38                            // keep at least 3 columns of right ledge
    bcs pick_bad
    sta ledge_r                        // (temporarily the start column)
    sec
    sbc #1
    sta free_hi
    lda #40
    sec
    sbc ledge_r
    sta ledge_r
    sec
    rts
pick_bad:
    clc
    rts

// ----------------------------------------------------------------------------
//  check_reach: carry set if free_lo..free_hi is within REACH columns of
//  prev_lo..prev_hi (the free space of the previous ledge row)
// ----------------------------------------------------------------------------
check_reach:
    lda prev_hi
    clc
    adc #REACH
    cmp free_lo
    bcc reach_fail                     // new free space starts too far right
    lda free_hi
    clc
    adc #REACH
    cmp prev_lo
    bcc reach_fail                     // new free space ends too far left
    sec
    rts
reach_fail:
    clc
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
    lda seconds
    beq timer_done
    dec seconds
    lda #1
    sta time_dirty
timer_done:
    rts

// hud_update: redraw one changed HUD sprite. Drawing is skipped on frames where
// the screen was shifted, because those already use most of the frame.
hud_update:
    lda shifted
    beq hu_go
    lda #0
    sta shifted
    rts
hu_go:
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
//  They rise BALLOON_SPEED pixels a frame in front of the ledges. Touching
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
    sta emask
    lda #0
    sta msbmask
    ldx #4
ub_loop:
    lda b_y,x
    beq ub_next
    sec
    sbc #BALLOON_SPEED
    cmp #BALLOON_TOP
    bcs ub_alive
    lda #0                             // floated off the top
    sta b_y,x
    beq ub_next
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
    ldx #4
sb_find:
    lda b_y,x
    beq sb_found
    dex
    bpl sb_find
    rts                                // all slots busy: skip this one
sb_found:
    jsr get_random                     // column 0-36
    and #63
    cmp #37
    bcc sb_col
    sbc #37
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
    lda b_xl,x                         // plus the left edge of the window
    clc
    adc #24
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
    rts

slot_bit:
    .byte %00001000, %00010000, %00100000, %01000000, %10000000
balloon_colors:
    .byte 2, 4, 5, 10                  // red, purple, green, light red


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
ledge_len:      .byte 0
ledge_l:        .byte 0                // candidate row: left / right ledge lengths
ledge_r:        .byte 0
free_lo:        .byte 0                // candidate row: open columns
free_hi:        .byte 0
prev_lo:        .byte 0                // last ledge row: open columns
prev_hi:        .byte 0
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

.errorif score_sprite + 128 > $4000, "Sprite data must end below $4000"
