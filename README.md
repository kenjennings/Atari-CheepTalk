# Atari-CheepTalk
Simple VBI Driver for the Cheep Talk Voice Synthesizer based on the SPO256-AL2 speech synthesizer chip.

---

The assembly code for the Atari depends on my MADS include library here: https://github.com/kenjennings/Atari-Mads-Includes.  

The MADS 6502 assembler is here: http://http://mads.atari8.info

I generally build in eclipse from the WUDSN ide.  WUDSN can be found here: https://www.wudsn.com/index.php 

---

The code is assembled at $9B00 (39680) through $9BCF (less than one page.)   That is the page before the default GRAPHICS 0 display list for a 40K (or more) Atari running 8K Atari BASIC.   

(Boot up with BASIC, go to DOS, binary load the AtariCheepTalk.xex file, then it should be in memory, and you can return to BASIC.  [I think].)

**USR(39680)**  is the CheepTalkInit routine for BASIC.   It will set up the PIA port, and it will attach the VBI.

**USR(39728, ADR(STRINGVARIABLE), LEN(STRINGVARIABLE) )** is the CheepTalkSpeech routine for BASIC to pass the address and length of the phoneme string to the VBI.   The routine will sit and wait for the the VBI to finish sending a string to the speech synthesizer before loading up the address for the new string.   (Therefore, one string of phonemes at a time.  Do not modify/rebuild a string that is currently being serviced by the VBI.)

**PEEK(39883)** is a status byte that BASIC can check  to see if the VBI is busy running the speech.   0 means the VBI is not servicing a speech string.  nonzero (2) means it is busy sending a string. 

---
