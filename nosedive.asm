// ============================================================================
//  NOSEDIVE  -  Commodore 64  -  Kick Assembler
//  Version 0.1
//
//  You have jumped off the platform and are diving head first down a shaft.
//  Steer left and right (joystick in port 2) to dodge the ledges that stick
//  out of the left and right walls. Touch one and it's game over.
//  Reach the ground at the bottom and you win.
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
.const LEDGE_COUNT    = 80             // ledges in the level (about 60s on PAL)
.const LEDGE_MIN_LEN  = 11             // ledges are 11-21 columns long
.const LEDGE_GAP_MIN  = 7              // blank rows between ledges: 7-10, so one
                                       // ledge every 8-11 rows
.const START_GAP      = 6              // blank rows before the first ledge
.const END_GAP        = 18             // blank rows between last ledge and ground
.const ANIM_DELAY     = 6              // frames per diver animation step

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
    lda #1
    sta VIC_SPR_ENABLE

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
    jsr scroll_shaft
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
    sta phase                          // 0 = ledges, 1 = run-out, 2 = ground
    sta ground_seen
    lda #LEDGE_COUNT
    sta ledges_left
    lda #START_GAP
    sta ledge_wait

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
    lda player_x_hi                    // only sprite 0 is used, so bit 0 = X bit 8
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
//  new_row: build the next bottom row. Phase 0 = random ledges, phase 1 = a
//  clear run-out below the last ledge, phase 2 = solid ground.
// ----------------------------------------------------------------------------
new_row:
    lda phase
    cmp #2
    beq row_ground
    cmp #1
    beq row_runout
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

row_runout:
    dec gap_left
    bne row_blank
    lda #2                             // next row is the ground
    sta phase
    jmp row_blank

row_ground:
    lda #1
    sta ground_seen
    lda #CH_SOLID
    jmp row_fill

row_ledge:
    jsr get_random                         // how many blank rows before the next one
    and #3
    clc
    adc #LEDGE_GAP_MIN
    sta ledge_wait

    jsr get_random                         // length = MIN + 0..7 + 0..3
    and #7
    sta ledge_len
    jsr get_random
    and #3
    clc
    adc ledge_len
    clc
    adc #LEDGE_MIN_LEN
    sta ledge_len

    jsr row_blank                      // start from an empty row

    jsr get_random                         // bit 7 picks the wall
    bmi ledge_right

    ldx ledge_len                      // left wall: columns 0 to len-1
    dex
    lda #CH_SOLID
ledge_left_loop:
    sta ROW_LAST,x
    dex
    bpl ledge_left_loop
    jmp ledge_made

ledge_right:
    lda #40                            // right wall: columns 40-len to 39
    sec
    sbc ledge_len
    tax
    lda #CH_SOLID
ledge_right_loop:
    sta ROW_LAST,x
    inx
    cpx #40
    bne ledge_right_loop

ledge_made:
    dec ledges_left
    bne ledge_done
    lda #1                             // that was the last ledge
    sta phase
    lda #END_GAP
    sta gap_left
ledge_done:
    rts

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
phase:          .byte 0
ground_seen:    .byte 0                // 1 once the ground has started to appear
ledges_left:    .byte 0
ledge_wait:     .byte 0                // blank rows still to go before the next ledge
gap_left:       .byte 0
ledge_len:      .byte 0
player_x_lo:    .byte 0
player_x_hi:    .byte 0

// ----------------------------------------------------------------------------
//  Diver sprite: three 24x21 frames, head pointing down the screen.
//  Sprite data must be 64-byte aligned, and inside the VIC's view of RAM
//  below $1000 (the VIC sees the character ROM at $1000-$1fff).
// ----------------------------------------------------------------------------
.align 64
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

.errorif sprite_frames + 192 > $1000, "Sprite data must end below $1000"
