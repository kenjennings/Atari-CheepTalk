# Atari-CheepTalk
Simple VBI Driver for Cheep Talk Voice Synthesizer

---

The assembly code for the Atari depends on my MADS include library here: https://github.com/kenjennings/Atari-Mads-Includes.  

The MADS 6502 assembler is here: http://http://mads.atari8.info

I generally build in eclipse from the WUDSN ide.  WUDSN can be found here: https://www.wudsn.com/index.php 

---

2020-01-02.   This is defintely broken.   The VBI is not maintaining the control variables properly.   Wrong flag testing, and wrong method of decrementing for the length.

May be fixed now, but have neot uploaded the reassembled XEX.

Also, these code changes will have moved the control data, so the PEEK() for BASIC to check VBI status will be different.

---
