.cpu arm7tdmi
.syntax unified

#include "SuperCardSDAddresses.h"

.section "scsd_read_sector", "ax"
@ bool scsd_readSector(uint32_t sector, uint8_t *buff, uint32_t readnum)
BEGIN_THUMB_FUNCTION scsd_readSector
    push {r1,r2-r7,lr}
    LOAD_SLOW_EXMEMCNT

    @ r1 for now holds the sector
.global scsd_readSectorSdhcLabel
scsd_readSectorSdhcLabel:
    @ if not sdhc this needs to be shifted to the left by 9
    lsls r1, r0, #9
    @ movs r1, r0

    @ enable sd access
    @ this function won't touch r1
    movs r0, #3
    CALL sccmn_changeMode readInterwork

    @ READ_MULTIPLE_BLOCK
    SD_COMMAND_ARGUMENT #18
    @ 2nd parameter is in r1 from above

    CALL scsd_sdCommandAndDropResponse6 readInterwork

    LOAD_FAST_EXMEMCNT

    @ loads the saved r1 (buff) and r2 (readnum)
    @ into r0 and r1
    pop {r0,r1}
read_sector_loop:
    @ all the functions called in this loop don't change the value of r0 or r1
    @ except scsd_readData, which will increase r0 by 512 automatically
    CALL scsd_readData readInterwork

    subs r1, #1
    bne read_sector_loop

    RELOAD_SLOW_EXMEMCNT

    @ STOP_TRANSMISSION
    SD_COMMAND_ARGUMENT #12
    @ 2nd parameter is passed in r1
    @ and from the loop above r1 is already 0
    LOAD_INTERWORK_FUNCTION sccmn_sdSendClock10 readInterwork r6
    CALL scsd_sdCommandAndDropResponse6 readInterwork

    movs r0, #1
    CALL sccmn_changeMode readInterwork

    RESTORE_EXMEMCNT

    @ returns true
    @ the change mode function above doesn't touch r0, so it's still 1
    @ movs r0, #1
    pop {r3-r7,pc}
INTERWORK readInterwork
INTERWORK_FUNCTION sccmn_changeMode readInterwork
INTERWORK_FUNCTION scsd_sdCommandAndDropResponse6 readInterwork
INTERWORK_FUNCTION scsd_readData readInterwork
INTERWORK_FUNCTION sccmn_sdSendClock10 readInterwork

.balign 4
.pool

.section "scsd_read_data", "ax"

@ this function will update r0 by incrementing it by 512
@ and will leave r1 unchanged
@ void scsd_readData(void* buffer);
BEGIN_THUMB_FUNCTION scsd_readData
    @ loads sd_dataread
    movs r2, #0x91
    lsls r2, r2, #20

waitOnReadTrue_loop:
    ldrh r4, [r2]
    lsrs r4, #9
    bcs waitOnReadTrue_loop

    @ amount of words to read
    @ use r4 as that register is already trashed by the caller to perform the interwork
    movs r4, #0x80

    @ (0x09100000 - 1) is 0xXXXXFFFF
    @ do it last so that it sets the condition flags for "gt" used below
    subs r3, r2, #1
    @ switch to arm, this instruction needs to be properly aligned at a +2 boundary
    @ so that it can properly jump to the arm code below, if needed, here's a nop,
    @ you can have it
    @ nop
    bx pc

.arm
    push {r1,r4-r11,lr}
read32_loop:
    bl LOAD_U32_ALIGNED_2WORDS
    bl LOAD_U32_ALIGNED_2WORDS
    @ we have read 4 words
    subs r4, #4
    bgt read32_loop
    @drop crc16
    ldmia r2, {r3-r10}
    @read end transmission bit
    ldrh r1, [r2]
    pop {r1,r4-r11,lr}
    @ fall through to the last bx
LOAD_U32_ALIGNED_2WORDS:
    @ we use gt conditional operations so that this piece of code is skipped over
    @ if we broke out of the read32 loop
    ldmiagt r2, {r1,r5-r11}
    @ (0x09100000 - 1) lsl 16 is 0xFFFF0000
    andgt    r7, r7, r3, lsl #16
    andgt    r11, r11, r3, lsl #16
    orrgt    r7, r7, r5, lsr #16
    orrgt    r11, r11, r9, lsr #16
    stmiagt r0!, {r7, r11}
    bx lr

.balign 4
.pool
