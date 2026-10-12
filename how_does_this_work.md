This is a file for those who want to know how does vim_ALU work, and also for the stupid author who may forget about this completely in the next few weeks or even days

So let's begin with some basic knowledge about vim : the registers,

0 -- registers

In vim, you yank into registers and paste them out, you can use ' to store data in a specific register, or just yank and store into default register 0,

The registers also work with macros, 

You can press numbers and chars after pressing q for macro recording, then you can use `@` to replay them, 

What's interesting is that yanking and macro recording shares the same bunch of registers, which allows us to execute texts in vim by typing `y@0`

After learning this basic fact we can naturally come up with more complex structures that act like for loops and ifs in normal programming, and that's how this project starts.

1 -- booting

The whole program boots from pressing 5Gyy@0, which will execute everything in the 5th line as vim key bindings

The 5th line
`
6Gf>2li0<esc>lv$y0PJi <-<esc>f-3x0i <esc>7Gf>2li3<esc>lv$y0PJi <-<esc>f-3x0i <esc>8G$vhy20GpaGyy@0<esc>yy@0
`

` the first part
6Gf>2li0<esc>lv$y0PJi <-<esc>f-3x0i <esc>7Gf>2li3<esc>lv$y0PJi <-<esc>f-3x0i <esc>
`
This line does two things, the first part from 5:1 to 5:58 is data preprocessing, which makes a copy of 2 input letters and paste them in the front of the line, reversing the directions of the arrows by deleting > and adding <, due to the working principle of the program, a copy must be torn into parts, so making another copy makes it easier for users and testers to compare input and final output, but it doesn't really matter, just some directions,

The first part also set flags in the front of original data, for input 1 its 0, and for input 2 its 3, They will be processed the same way as input digits does, but leads to different outcomes, to be more specific, they lead the program to line 3, a special line that deal with clean up jobs and stop the program. We will get deep into it in the next chapter.

` the second part
8G$vhy20GpaGyy@0<esc>yy@0
`
The second part form 5:59 to 5:$ copy and paste the option code from optput (short for option input) and use them to build a jump command in line 20 and do yy@0 on the same line to execute it, for example if you put 04 in optput for adding, the program will build 04yyG@0 in line 20, which makes the program jump to the 4th line and execute whatever I wrote there (well in this case it's the main program of adding)

So after reading this you may begin to realize that the key of this project is to keep using y@0 to launch the next step, and build tmp commends in buffers if we need "if" in normal programming

So lets see what happened in line 4 next, the adding command

2 -- adding machine

The 4th line
`
6G$x5G0P7G$x5G0p0laGyy@0|<esc>5Gyy@0
`

The 4th line is the command center for the whole adding machine

It will first cut the last char from input 1 (line 6), paste it in the start of the buffer for adding (line 5), then cut another char from input 2 (line 7) and paste after the first letter, then append Gyy@0| after them, press esc to exit insert mode, then jump to line 5 to execute the command that we just build.

For example if the last two numbers of input 1 and 2 is 0 and 1, you will get `01Gyy@0|` in line 5, then it will be executed, leading the program to jump to the corresponding line, it also works for 10, 11 and 00, though 00 is a bit special, because there is no line 0 in vim, so the meaning of this command will actually be going to the very front of this line twice and jump to the last line. 

I place different program on each line so that every combine of number will be processed separately, you may consider them as "if body" structures in normal coding, another thing you need to know is that the whole alu project shares the "if" structure because its all about 0 and 1, the program decides what to execute by finding special chars mixed in the code, we will talk about this later.

You may be worried that something unexpected will happen in 5th line because we also use it as booting area, it is a bit ugly but does not matter, because @0 in normal mode will just switch process to whatever it is in register 0, and since everything we have done to 5th line make sure that we only insert stuff in the very front, so our code will be clean.

There's another common doubt about the function of | sign in the back of yy@0, well it does nothing, just something to separate each jumping line, making it easier to debug

After jumping to one of the four bodies of the "if" lines, the program will first work from the start of the line, it will then build another jumping commend in the 13th line, here we use line 01 as an example.

The 1st line
`
13G0i1<esc>laG2f9v$y@0|<esc>13Gyy0i0<esc>@09G0i1<esc>4Gyy@0 n9G0i0<esc>21Gyy@0 d9G0i0<esc>26Gyy@0 o9G0i1<esc>27Gyy@0 X9G0i1<esc>28Gyy@0
`

However, some of the codes does not belong to our adding program so lets just delete them for better sight

` codes that belong to adding 
13G0i1<esc>laG2f9v$y@0|<esc>13Gyy0i0<esc>@09G0i1<esc>4Gyy@0
`

Well it doesn't look so scary now right? But it still contains two parts, let's take a deep look into it.

`the first part is letter 1:1 to 1:31
13G0i1<esc>laG2f9v$y@0|<esc>13Gyy0i0<esc>@0
`
 
`13G` enters another buffer that's specially prepared for handling carry bit

`0i1<esc>laG2f9v$y@0|<esc>` take in carry bit left by the former turn (in the first turn its 0) and write the next command which will switch the program to the line to deal with output of this bit and carry of the next turn

`0i1` for line 01 is because 0 XOR 1 is 1

`13Gyy` yank the whole line into register 0 preparing to execute, but before that, it types `0i0` to store the carry bit of this turn to prepare for the next turn, and that is why we need `l` to move right one step -- to include the carry bit from last turn!

` this is the command that will be generated if you jump from 10 or 01 (the first letter `1`), and there's no carry bit (the second letter 0)
10G2f9v$y@0|
` 

And after `0i0` it will be like `010G2f9v$y@0|`

And if next turn we jump from line 11, the changes will be like:

`010G2f9v$y@0|` -> `1010G2f9v$y@0|` -> `10G2f9v$y@0|10G2f9v$y@0|` -> (copy the whole line) -> `110G2f9v$y@0|10G2f9v$y@0|`

And `10G2f9v$y@0` will be executed

After `10G`, the cursor jump to the 10th line, `2f9` try to find the second f which is used as a marker to start copying from.

This trick will be used every often in all programs to stuff in multiple codes in just one line, characters like x d n are all those markers, while using 9 as a marker is due to historical reasons since I didn't notice the trick of setting special marks(LOL).

The reason for designing like this instead of opening new lines is that extra converting code will be needed to deal with lines other than those combined with 0 and 1, so just remember that the hole project shares the same if.

` the 10th line looks like this
13G0i1^[laG2f9v$y@0|^[13Gyy0i0^[@09G0i1^[4Gyy@0 d9G0i0^[26Gyy@0 o9G0i1^[27Gyy@0 X9G0i1^[28Gyy@0
`
`13G0i1^[laG2f9v$y@0|^[13Gyy0i0^[@` is the part used to generate code that we jump from, which we had learn just now, and `d9G0i0^[26Gyy@0` does not belong to adding

` so lets just remove all of them and focus on
09G0i1^[4Gyy@0
`

`09G0i1^[4` will write 1 in the front of output, since 1 XOR 0 is 1

While 4Gyy@0 will jump back to 4G, the core of adding machine, and start the next turn.

The rest of the other 3 if bodies work in the same mode, but line 11 is a bit special.

` this is part of 09
9^[13G0i1^[9G0i0^[4Gyy@0
`

`9<esc>` is just a marker to let jump code start from here (2f9, remember?), `<esc>` will cancel 9 to make sure nothing unexpected happens

`13G0i1<esc>` jump back to line 13 to set an extra 1 stands for carrying, because 1 AND 1 itself is 1, it needs carry itself, without this, the program will go wrong from the second bit if input is like 0001 + 1111

After all bits were processed, the program will receive 0 and 3 from input (the preprocess code in line 5 set them), the program generates 03Gyy@0 and jump to line 3 where end up jobs where done

` line 3
13G0x9G0P12Gyy@0o9Gi ^[@ X9Gi ^[@ d9Gi ^[@ n9Gi ^[@
`

All machines in the project will end up in line 3, so there is still much code that didn't belong to adding machine, lets delete them

`
13G0x9G0P12Gyy@0
`
`13G0x9G0P` jumps to line 13 -- the carry dump, where it cut the very first letter set by carry handlers, and paste it back to the front of result to use it as the overflow flag

`12Gyy@0` jumps to line 12

` line 12
2G^A12Gyy@
`
It's a line of code that occur with errors due to `@`, Invalid register name: '^@', what before that is a number counter that i made for fun, add an `0` at the end will make number in line 2 increase forever, which is of no use.

So that's how the adding machine work, in the next chapter we will talk about what will happen in the minus process

3 -- minus machine

After reading the last chapter you may realize that the alu works more like a LUT, which means when we need a new logic gate, we make a new structure like `f9` and store outcomes in.

While for minus machine, its actually a combination of a not gate, an adding machine for +1, and an adding machine for ~b +1 +a. What we have is a adding machine, and its quite simple to create another not gate in line 21 like this
`
7G$x22G0PaGfnlv$y@0|<esc>yy@0
`
and structures like `n9G0i0<esc>21Gyy@0` in if lines are lookup tables for not gate.

This seems easy, but another problem is how to connect them, minus machine has 3 processes, but we don't have native function calls in vim macro programming. Due to there is only one cursor in vim macro programming, we need to register a callback at the end of the function we call before calling it. Lets see the main program of minus machine to see how we make this come true.

`
3G$i9Gvf hx7G$a3p12Gf1xa5$a025G0i9Gf x9Gvf hx7G$a3p12Gf2i12lx$x3GvfPd13G0r04Gyy@021Gyy@0
`

To understand this program, we need to introduce the key <c-v> in insert mode(not normal mode in which it means vision block), it help us insert special keys like <esc> <c-a>, and <c-v> itself. Its used to delay the input of <esc> here to generate a code that can generate code.

Here is an example so show how this work, pleace press `yy@0` on the second line of marco below
`
jdd
k0ijII am Second insert     <-first insert yy@0
`

For those who is not reading this in vim, here is what it will become next.

`
jII am Second insert     <-first insert jdd
I am Second insert    k0ijII am Second insert     <-first insert yy@0
`

As you can see, the second line modifies the first line and executes it, who then write another string back to the second line instead of jdd which means delete the whole line below it.

This experiment shows we can modify other code while before running them, using <c-v> commend. So what we need to do is to modify the exit code of not gate before starting, making it copy outcomes and paste it back to input, modify exit code of +1 gate to start adding gate, then start the +1 gate.

So when we press yy@0 and start minus machine, it will actually modify the exit code of not gate, adding a code that will modify the exit code of +1 gate, which modify the exit code of adding machine. Its extreamly complex and hard to debug, i recomand you try to build your own minus machine instead of trying to understand mine if you want to figure out every detal of minus machine, it will be a lot easier.












