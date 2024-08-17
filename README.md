# sixfiveohtwo

What started as a simple little project to learn Zig has turned into a trip to not only learn Zig, but also dip my toes into SDL and building an actually working emulator. Sure, it might not be cycle accurate or even working 100%, but it's running WozMon and Apple Basic alright, so I'm counting this as a win.

## Known issues

- I've used the 6502 tests by Tom Harte ([link to repo](https://github.com/SingleStepTests/ProcessorTests/tree/main/6502)) and it's failing between 100 and 200 tests for every SBC instruction. Considering that's about 1% of the tests per instruction I didn't bother to fix that yet.
- It's also not cycle or even speed accurate at all at the moment and I'm not sure I want to prioritize that right now.
- Also this code isn't really cleaned at all. It's the first working state and can definitely use improvement in a lot of places.

## Nice to know

- The instruction decoding isn't done in the typical 256 cases long switch statement fashion but rather in several stages deconstructing the read instruction into the parts of information like what the operand of the instruction is and where it has to be sourced from (and thus where the result has to be returned to if applicable). The inspiration for doing it this way came from looking at [masswerks documentation](https://www.masswerk.at/6502/6502_instruction_set.html) of the 6502 instruction set and the tables in the "instruction layout" section near the bottom.
- Testing is done by converting the Tom Harte tests that are inserted into the test case template. I intentionally didn't push them into this repo, because doing so would inflate it to about 800MB. I'm gonna push it later to a separate branch, so you can check it out if you want to.

## How to use the emulator

On start it automatically loads Wozmon and Apple BASIC to memory locations 0xFF00 and 0xE000 respectively. Both memory sections are write protected by default, causing an error when writing to them is attempted.

Technically there is a emulated PIA at 0xD010 and while ih helps with the emulator you should not rely on it working the way the original does at all.

For RAM there's a section from 0x0000 to 0x3FFF. That covers the zeropage and stack as well as the default locations BASIC uses to store data and should also be more than enough for the rest you could ever run on this thing.

## To do

- Actually clean up this mess
- Extend the Apple I emulation so that it can also read and write to emulated cassette tapes
- (in the distant future) Use the 6502 core and bus to emulate other, more advanced 6502-based systems like the Apple 2, VIC-20 or even the NES. Would have to get it more or less cycle accurate though.
