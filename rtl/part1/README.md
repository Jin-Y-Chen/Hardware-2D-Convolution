part 1 of the project

1. Use Synopsys DesignCompiler to synthesize your unpipelined design with WIDTH=16 and ACCW=48 for a range of different clock frequencies from slow to fast. Adapt the scripts you used in HW2.

For each frequency you try, record the area, power, the critical path location, and whether the timing constraint was met or violated. 

In your report, make a table that shows this data for each attempted
frequency. Make sure you include units on all values you report (here and everywhere else in the
report).

Make graphs that show the relationships you found between clock frequency and both area and power. Explain the trends that you observed and explain why they occur. (Make two graphs. On both, show clock frequency on the x axis; then show area as the y axis on one graph and power as the y axis on
the other.) Make sure you use graphs that plot both axes proportionally (like a scatter graph, not a line graph). Only include the design points where the timing constraint is MET.

For each frequency, give a description in your report of where the critical path is. Don’t just copy/paste
the endpoints from the synthesis report, but explain logically where the critical path lies in the module.

(For example, “the critical path starts at the output of register [register name], passes through logic
that computes [description of the logic], and ends at the input to register [register name].”)

2. Now, repeat the tasks from question 1 for your pipelined design with the same values of WIDTH and ACCW. Additionally, answer the following: 

Did pipelining help make this module faster? Explain why

or why not and show how this is reflected in the synthesis data and critical path.

3. For the pipelined design with the maximum clock frequency you found, how much energy would your system consume if it were to process a sequence of 50 sets of input values? Assume you have to wait
until the final output comes out of the system, and don’t forget that your pipelined design takes more than 50 cycles to compute 50 sets of inputs.

Remember: energy is measured in joules. Power = energy per time. 1 Watt = 1 Joule per second. Use the power obtained from synthesis and your understanding of the time it would take for your system to fully compute 50 sets of input values.

4. Would the energy you computed in question 3 change if you resynthesized the design targeting different clock frequencies? Explain and justify your answer. Think carefully about what changes when you change the target frequency and how those changes affect the power the system consumes.

5. Make a table that compares the power, area, latency, and throughput of your pipelined and unpipelined MAC designs (at the maximum clock frequency you previously found for each) with WIDTH=16 and ACCW=48. In your report show how you calculated the latency and throughput. Quantify latency in
seconds (or ns), and quantify throughput in terms of MACs per second. (If needed, review these
concepts in the Topic 6 slides.) Based on the trade offs seen in your table, explain when it would
make sense for a designer to choose the pipelined design and when it would make sense to use the
unpipelined design.

6. Your design is pipelined as much as possible if you assume that you cannot pipeline the arithmetic
units themselves. However, as we discussed in Topic 6, we could also pipeline the multiplier itself. For
example, you can replace the multiplier with one that is pipelined into more stages. Based on your
results to questions 1 and 2, would you expect that deeper pipelining in the multiplier might help you
reach higher clock frequencies? Justify why or why not.
If you were to pipeline the multiplier in this way, what other changes would you have to make in your
module? Be specific about each of the module’s control inputs: which of them would need to change,
and which would not?

Would pipelining inside of the adder be possible and a good idea? Why or why not?
(Answer this question based on your understanding of the design and your answers to prior questions.
You do not need to modify your design/code to answer this question.)

7. In questions 1 and 2, you always synthesized using the same parameter values of WIDTH=16 and
ACCW=48. Here, explore how changing WIDTH and ACCW affects the critical path location and maximum
clock frequency of your pipelined MAC module. 

First, do a set of experiments where you set WIDTH=12 and synthesize three designs with ACCW=24, 48, and 64.

Next, do a new set of experiments where you set ACCW=48 and synthesize three designs with WIDTH=8, 16, 24.

Do the clock frequency and critical path location change as ACCW changes? Do they change whenWIDTH changes? Explain what you see and what you learn from it. You should expect to see differences
in the scaling behavior of WIDTH and ACCW. Explain why they behave differently. In your explanation,
account for the shift and saturate logic on the output path as well as the multiplier and adder.
Include the six synthesis reports for this question along with your Final Report.

8. The MAC’s accumulator holds ACCW bits. As you know, if the value stored in the accumulator grows
large enough, it will overflow. That is, ACCW bits may not be enough to store the resulting number.
Assume WIDTH=5 and ACCW=16. What is the maximum number of MACs your system could perform
while guaranteeing that the accumulator cannot overflow? (Hint: what is the largest magnitude number
you could produce on the multiplier’s output? Then, how many accumulations would it take for that
number to produce an overflow in the accumulator?) Don’t forget that our values are all signed integers,
and don’t forget that the accumulator can be initialized to a signed WIDTH bit number. Show your
reasoning and justify your answer.