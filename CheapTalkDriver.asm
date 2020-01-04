; ==========================================================================
; Minimal VBI driver for the SPO256-AL2 speech processor.
; Interface is via the PIA ports.
; Assuming all lines wired according to common ANTIC and ANALOG 
; magazine documentation.
; Bit 7 = status (READ: 1 = Speech busy)
; Bit 6 = command (WRITE: 1 = Accept data.  0 = this is the data)
; Bit 5 to 0 = data (WRITE: phoneme value 0 to 63)
; January 2020 by Ken Jennings
; for the Atari 8-bit computers
; Assuming MADS Assembler.
; --------------------------------------------------------------------------

; ==========================================================================
; The assembly code for the Atari depends on my MADS include library here: 
; https://github.com/kenjennings/Atari-Mads-Includes
;
; The MADS 6502 assembler is here: http://http://mads.atari8.info
;
; I generally build in eclipse from the WUDSN ide.  
; WUDSN can be found here: https://www.wudsn.com/index.php
; --------------------------------------------------------------------------

; ==========================================================================
; Atari System Includes (MADS assembler)
;	icl "ANTIC.asm" ; Display List registers
;	icl "GTIA.asm"  ; Color Registers.
;	icl "POKEY.asm" ;
	icl "PIA.asm"   ; Controllers
	icl "OS.asm"    ;
	icl "DOS.asm"   ; LOMEM, load file start, and run addresses.
; --------------------------------------------------------------------------

; ==========================================================================
; Macros (No code/data declared)
	icl "macros.asm"
; --------------------------------------------------------------------------

; ==========================================================================
; We need a page 0 pointer.   The return var from USR to BASIC is
; convenient enough.  Just ignore the return value in BASIC.
; --------------------------------------------------------------------------

ZRET =  $D4     ; this is FR0 $D4/$D5 aka Return Value to BASIC.

; ==========================================================================
; The INIT and the SPEAK routines are expected to be called by BASIC, so
; there is additional stack management in those entry points.
; The actual work is done by the VBI.
;
; The starting address here is arbitrary.  $9B is the page BEFORE the 
; location where the Display list occurs on any Atari with 40K or 
; more RAM and running 8K cartridge BASIC.
; --------------------------------------------------------------------------

	ORG $9B00

; ==========================================================================
; Init is called ONCE by BASIC and it will setup PIA 
; and start the VBI routine.
; --------------------------------------------------------------------------

CheepTalkInit
	pla ; ugliness that assumes no parameters passed.
	
	lda CT_InitFlag       ; Is this already initialized? 
	bne ExitCheepTalkInit ; Yes.  Do not repeat.

	; Zero the block of variables
	ldx #5
bCTI_LoopClear
	sta CT_Status,x
	dex
	bpl bCTI_LoopClear
	
	; Configure the PIA to do I/O.

	ldx CT_PIA                ; X = PIA number.  (Atari 400/800 have 0 and 1)
	lda PACTL,x               ; Get current value of port control.
	pha                       ; Save to put back later.

	lda #MASK_PORT_ADDRESSING ; This value is "Accept Read/Write control".  See PIA.asm %11111011 ; 
	sta PACTL,x               ; Set PIA control to configure Read/Write...

	lda #%01111111            ; highest bit is read. lowest 7 bits are write.  
	sta PORTA,x               ; and now I/O directions are set.

	pla                       ; Get original PACTL value.
	sta PACTL,x               ; Set the normal value of port control.

	; Set up the deferred VBI.

	ldy #<CheepTalkVBI        ; Add the VBI to the system 
	ldx #>CheepTalkVBI
	lda #7                    ; 7 = Deferred VBI
	jsr SETVBV                ; Tell OS to set it up

	inc CT_InitFlag           ; Flag to not do the setup again.
	
ExitCheepTalkInit
	rts


; ==========================================================================
; Speak is called by BASIC.  
; If speaking is busy it will wait until speaking is done.  
; (In another version this could exit instead.  
; Or this could be made to override the current string to begin a new one.) 
;
; The function expects there must be two parameters, address, and length.
; --------------------------------------------------------------------------

CheepTalkSpeech
	pla                     ; Get argument count
	tay                     ; copy to Y for cleanup
	beq ExitCheepTalkSpeech ; 0 arguments means incorrect setup.  Leave.  Immediately.

	lda CT_InitFlag         ; VBI and ports not initialized.
	beq ExitAndCleanArgs    ; Therefore quit cleanly.

	cmp #2                  ; This must be 2 arguments, address and length
	bne ExitAndCleanArgs    ; Not 2 arguments.  clean up what is there.

bCTS_CheckStatus
	lda CT_Status           ; Get current VBI status.
	bne bCTS_CheckStatus    ; Wait here until the VBI is done with the previous string.

	; This seems redundant, but I'm paranoid and need to be sure there's no possibility of 
	; hitting the VBI in the middle of BASIC attempting to get control of the data.

	lda RTCLOK60            ; Get the jiffy clock
bCTS_WaitForFrame
	cmp RTCLOK60            ; Is it the same?
	beq bCTS_WaitForFrame   ; Keep looping until it changes.
	
	; Now, the code is running at the top of the frame, so it is not 
	; likely the VBI can interrupt this next line...

	inc CT_Status           ; Tell the VBI not to do anything
	
	pla                     ; Pull arguments from stack...
	sta CT_SpeakPointer+1   ; High byte...
	pla 
	sta CT_SpeakPointer     ; then Low byte....
	pla                     ; etc.
	sta CT_SpeakLen+1
	pla
	sta CT_SpeakLen
	
	dec CT_Status           ; Tell the VBI it's OK to work again. 
	rts                     ; And we're finished .
	
ExitAndCleanArgs            ; must pull parameters from stack. (count is in Y)
	
bCTS_Dispose                ; Displose of any number of arguments
	pla
	pla
	dey                     ; Minus one argument
	bne bCTS_Dispose        ; Loop if more to discard.

ExitCheepTalkSpeech
	rts                    ; Abandon ship.
	

; ==========================================================================
; VBI.  
; If BASIC is working on the controls, then exit.
; If speaking is inactive, then check if there is a new non-zero length
; to begin servicing a new string.
; If length is 0, then nothing to do, so exit.
; If the port indicates the speech synthesizer is busy, then exit.
; Write out the CURRENT byte per the address pointer.
; Increment the address.
; Decrement the length.
; If length is now 0, then update status to 0.
; --------------------------------------------------------------------------

CheepTalkVBI
	lda CT_Status
	cmp #1                ; Does Status say BASIC is working on the controls?
	beq ExitCheepTalkVBI  ; If BASIC is working on the controls, then do nothing.
	
	cmp #0                ; Check if speaking is running. 
	bne ServiceCheepTalk  ; Not zero, so yes, speaking is in progress, go maintain it.

	; Speaking is not in progress at this time.
	; Did BASIC put usable speaking data in the controls ??

	lda CT_SpeakLen       ; Get length
	ora CT_SpeakLen+1     ; Combine with high byte
	beq ExitCheepTalkVBI  ; zero length. So, nothing new to speak.  Exit.
	
	lda #2                ; Tell BASIC that speaking is in progress.
	sta CT_Status
	
	; So, here is what the VBI does...
	; If the speech synthesizer is busy, then exit.
	; Write out the CURRENT byte per the address pointer.
	; Increment the address.
	; Decrement the length.
	; If length is now 0, then update status to 0.

ServiceCheepTalk
	ldx CT_PIA                ; X = PIA number.  (Atari 400/800 have 0 and 1)
	lda PORTA,x               ; Get data from port.
	bmi ExitCheepTalkVBI      ; High bit set means chip is still busy.

	lda CT_SpeakPointer       ; Copy address pointer to 
	sta ZRET                  ; zero page for indirect addressing 
	lda CT_SpeakPointer+1
	sta ZRET+1
	ldy #0                    ; indirect index offset 0.

	lda (ZRET),y              ; Got the next byte.

	ora #%01000000            ; turn ON bit 6, value 64, or $40.
	sta PORTA,x               ; Send to the port. 

	; I remember this was absolutely needed, because the synthesizer is slower than 
	; the Atari, but I don't remember how many NOPs were needed to pause. 
	; It may need more....
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	
	and #%00111111            ; turn OFF bit 6, value 64, or $40.
	sta PORTA,x               ; Send to the port. 

	; Prep the control data for the next vertical blank.

	inc CT_SpeakPointer       ; Overflow  from 255 to 0 means increment high byte.
	bne bCTV_SkipHiAddress    ; If result is non-zero, then it did not overflow.
	inc CT_SpeakPointer+1
bCTV_SkipHiAddress

	sec                      ; Set carry for subtraction.
	lda CT_SpeakLen          ; dec not as simple as inc.
	sbc #1
	sta CT_SpeakLen
	bcs bCTV_SkipHiLength    ; Did not use carry, so skip dec high byte.
	dec CT_SpeakLen+1
bCTV_SkipHiLength

	lda CT_SpeakLen          ; Check if length is now 0.
	ora CT_SpeakLen+1
	bne ExitCheepTalkVBI     ; Not 0, so done.
	
	sta CT_Status            ; 0 in status means VBI is done speaking.

ExitCheepTalkVBI
	jmp XITVBV              ; Return to OS. 

; ==========================================================================
; The supporting data.

CT_PIA      ; Which PIA to use.  0 for Ports 1, 2, or 1 for Atari 400/800 Ports 3, 4
	.byte 0
		
CT_InitFlag	
	.byte 0 ; 0 means uninitialized.  1 means init is done.

CT_Status
	.byte 0 ; 1 means BASIC is working.  2 means speaking.  0 means done.

CT_SpeakPointer
	.word $0000 ; Current pointer to string of phonemes.
	
CT_SpeakLen
	.word $0000 ; Number of bytes to write.  At 0, speaking is over.
                ; Assume the caller uses a sound-off phoneme at the end of the string.

	END
