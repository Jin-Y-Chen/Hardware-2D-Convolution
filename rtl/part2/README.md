part 2 of the project
Simulate your design for a variety of different parameters. Importantly, make sure you do some
tests with extreme values of INPUT_TVALID_PROB; you want to make sure that the system works correctly
even if it has to stall frequently, and that it works correctly if data arrives as quickly as possible.
Synthesize your full design twice, with the following parameters:
• WIDTH=24, R=9, C=8, K=4
• WIDTH=10, R=15, C=13, K=7
For each design, correct any synthesis problems you find, and find the maximum possible clock frequency.
Don’t forget that you need to set the parameter values in your top-level module. The params.sv file used
in simulation only affects the testbench; to set the values in synthesis, you must make sure the default
parameter values in your top-level module are set correctly. Save your synthesis reports with descriptive
names and include them in your Part 2 submission.
Your Part 2 submission should include your code, your synthesis reports, your AI usage log, and a
brief plaintext status report. Please see Section 6 in the Project Overview document, which explains the
submission requirements and procedure. Additionally, in your status report, explain which testbench
stages you used and where you had problems. (For example, maybe you tested with Stage 1, found and
fixed some bugs, then Stage 2 worked immediately, and then Stage 3 had more bugs.)
