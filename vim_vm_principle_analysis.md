# Vim-VM / `asm_auto_set_addr_for_call_bk.txt` 原理分析

> 源文件：<https://shared.ymodatabase.top/asm_auto_set_addr_for_call_bk.txt>  
> 分析对象：一个完全依赖 Vim Normal mode 按键、寄存器、搜索、光标移动和文本编辑来执行自定义汇编的实验性虚拟机。  
> 说明：下面把“源码直接能确认的事实”和“根据 Vim 命令序列反推的实现”区分开。后者会用“推断”“大致”“很可能”等措辞标记。

---

## 0. 结论先行

这东西最准确的分类不是“真正的硬件 CPU”，也不是“在 Vim 里调用了某个脚本解释器”，而是：

**一个以 Vim 自身作为宿主执行引擎、以同一个文本 buffer 作为代码和机器状态、以 Normal-mode 宏作为微码的文本虚拟机。**

它可以分成两层：

```text
Guest（作者定义的 ISA）
    mov / add / sub / cmp / jmp / call / ret / push / pop / malloc ...
                         │
                         ▼
Host microcode（Vim Normal mode）
    G / gg / w / b / v / y / p / d / x / /search / marks / @0 ...
                         │
                         ▼
Host machine
                      Vim
```

这里最关键的抽象映射是：

| 传统机器概念 | 这份 Vim-VM 里的对应物 |
|---|---|
| 程序文本 | buffer 中 `please write asm...` 区域 |
| 微码 ROM | buffer 前部的大量 Vim 按键序列 |
| 通用寄存器 | buffer 中固定位置的文本槽 |
| RAM / 工作区 | 整个 Vim buffer |
| PC / IP | 当前光标位置 + mark |
| opcode decoder | `[ASM_manual]` 文本查表 |
| 间接执行 | `yy` + `@0` |
| load / store | yank / paste / replace |
| 地址计算 | 行号、word movement、搜索、mark |
| symbol table | `__ label` 文本本身 |
| jump | Vim `/` 或 `?` 搜索 |
| stack | `STACK` 区域 |
| heap | `HEAP` 区域 |
| stdout | `STDOUT` 区域 |
| assembler/linker 的一部分 | 文件尾部的 `call` 地址预处理宏 |

所以它的本质可以压缩成一句话：

> **用“编辑文本”模拟“改变机器状态”。**

---

# 1. 真正的启动原语：`yy@0`

整个系统能成立，核心不是某条复杂宏，而是 Vim 本身提供的一个非常强的“代码即数据”机制。

典型入口形态：

```vim
127Gyy@0
```

逻辑上可以拆成：

```text
127G    → 把光标移动到第 127 行
yy      → yank 当前整行
@0      → 执行 register 0 中的按键序列
```

关键细节：

- Vim 的普通 yank 会把最近 yank 的文本放入 numbered register `0`。
- 因此刚刚 `yy` 的那一行，马上可以用 `@0` 重新解释成 Vim 按键。
- 如果那一行本身不是普通文字，而是一串 Normal-mode 命令，那么它就变成“可执行代码”。

于是：

```text
buffer 中一行文本
      │
      │ yy
      ▼
register 0
      │
      │ @0
      ▼
被 Vim 当作按键重新执行
```

这相当于给这个系统提供了一个非常原始的：

```text
eval(buffer[line])
```

或者从 CPU 角度看：

```text
fetch microinstruction
execute microinstruction
```

---

# 2. 为什么网页看起来像乱码

源文件前半部分充满类似：

```text
G
yy
@0
v
p
x
以及不可见控制字符
```

其中最扎眼的是浏览器显示出来的 ESC、Ctrl-V 等控制字节。

这不是字符编码损坏，而是因为作者把**真实 Vim 按键序列直接存进了文本文件**。

例如：

- `ESC`：退出 Insert/Visual 等模式，回到 Normal mode。
- `Ctrl-V`：在 Vim 中既可进入 blockwise visual，也经常用于插入/引用特殊字符。
- `G`：按行移动。
- `w/b/e`：按 word 移动。
- `v/V`：进入字符/行可视选择。
- `y`：yank。
- `p/P`：paste。
- `d/x`：删除。
- `i/a/I/A/o/O`：进入不同形式的插入。
- `/pattern`、`?pattern`：搜索。
- `mA`、`` `A ``：mark 和跳回 mark。
- `@0`：执行寄存器内容。

所以在普通浏览器里看，它像乱码；在 Vim 看，这些字符是**操作码**。

---

# 3. 这不是“宏集合”，而是一台很小的微码机

文件里存在一行 `[ASM_manual]`，其中把 guest 指令和寄存器名映射到数字，例如：

```text
add → 某个数字
sub → 某个数字
mov → 某个数字
...
rax → 某个数字
rbx → 某个数字
...
call / ret / push / pop → 各自的数字
```

这些数字的意义不是普通的 opcode byte，而更接近：

> **“处理这个 token 时，应该去哪一行取 Vim 微码。”**

因此 `[ASM_manual]` 实际兼任了一张非常原始的 symbol table / dispatch table。

大致过程可以还原为：

```text
当前 ASM 行
   │
   ├─ 取第一个 token，例如 "add"
   │
   ▼
在 ASM_manual 中搜索 "add"
   │
   ├─ 移动到它后面的数字
   │
   ▼
得到 handler 的位置
   │
   ▼
构造/执行类似 <N>Gyy@0
   │
   ▼
进入 add 的 Vim 微码
```

寄存器也一样：

```text
"rax"
   │
   ▼
在 ASM_manual 中找 rax
   │
   ▼
得到一个固定位置
   │
   ▼
定位保存 rax 内容的文本槽
```

源码中反复出现的几类片段：

```text
/ASM_manual
2w
v...y
...G
yy@0
```

和这种设计高度一致：**先把 token 当字符串查表，再通过表中的数字完成间接分派。**

这不是传统意义的机器码 decoder，但逻辑职责完全相同。

---

# 4. Fetch–Decode–Execute 在这里是什么样

传统 CPU 的主循环：

```text
fetch instruction
decode
read operands
execute
write back
advance PC
```

在这里大致变成：

```text
1. 光标/mark 指向当前 guest ASM 指令
2. Visual/yank 取出 opcode token
3. 在 ASM_manual 文本中搜索该 token
4. 取出映射数字
5. 跳到相应 Vim 微码行
6. yy@0 执行该行
7. 微码再次解析 operand token
8. 修改寄存器/ALU scratch/STACK/HEAP/STDOUT
9. 回到 guest 程序
10. 定位下一行或进行搜索式跳转
```

所以所谓“instruction pointer”并不是某个整数寄存器：

**Vim 光标、mark 和搜索位置共同承担了 PC/IP 的职责。**

这也是为什么源码里大量使用：

```text
mA
`A
G
j
k
/search
?search
```

这些本来只是编辑器导航功能，但在这里都成为控制流基础设施。

---

# 5. 同一个 buffer 同时是代码、ROM、RAM 和 I/O

这是整个设计最反常、也最漂亮的一点。

一般虚拟机至少会把：

```text
解释器代码
guest 程序
寄存器状态
heap
stack
输出
```

放在不同对象里。

这个文件却把它们全塞进一个 Vim buffer。

可以抽象成：

```text
┌──────────────────────────────────────────────┐
│                一个 Vim buffer              │
├──────────────────────────────────────────────┤
│ ALU scratch / Boolean microcode             │
├──────────────────────────────────────────────┤
│ ASM dispatch / register mapping             │
├──────────────────────────────────────────────┤
│ instruction handler microcode               │
├──────────────────────────────────────────────┤
│ register text slots                         │
├──────────────────────────────────────────────┤
│ STACK                                       │
├──────────────────────────────────────────────┤
│ HEAP                                        │
├──────────────────────────────────────────────┤
│ ASM_usage / metadata                        │
├──────────────────────────────────────────────┤
│ STDOUT                                      │
├──────────────────────────────────────────────┤
│ user guest ASM program                      │
├──────────────────────────────────────────────┤
│ call-address preprocessor                   │
└──────────────────────────────────────────────┘
```

因此它具有很强的**自解释 / 自修改**性质：

- 微码读取 buffer。
- 微码修改 buffer。
- guest 状态也是 buffer。
- 某些临时 Vim 命令甚至也是动态拼接进 buffer 再执行的。

从体系结构角度看，这比“Harvard architecture”更接近一种极端的统一存储结构：

> **所有东西都是文本，只是文本所在的位置决定了它被当成程序、数据还是元数据。**

---

# 6. “寄存器”其实只是固定文本槽

作者支持：

```text
rax rbx rcx rdx r5 ... r16
```

但这些当然不是真实 CPU register，也不是 Vimscript 变量。

更合理的模型是：

```text
某个固定 buffer 位置 = rax
另一个固定位置       = rbx
...
```

`ASM_manual` 里的寄存器映射告诉微码应该去哪一个位置读写。

于是：

```asm
mov rax,101010101
```

本质不是“CPU MOV”，而是：

```text
1. 找到 guest operand "rax"
2. 查表得到 rax 对应的文本槽
3. 找到立即数字符串
4. yank 那段字符串
5. 到 rax 槽位删除旧内容
6. paste 新内容
```

这也解释了源码中特别强调的一件事：

**register 实际上可以保存普通字符串。**

因为对 Vim 来说：

```text
101010101
hello
data
现在开始计算...
```

全都只是文本。

只有当某个值进入 ALU 指令时，微码才会假设它满足预期的二进制格式。

所以这里的 register 在类型系统上更接近：

```text
register : String
```

而不是：

```text
register : uint9
```

ALU 只是选择性地把这个 String 当 bit-vector 使用。

---

# 7. ALU：把文本位置当逻辑线路

源码开头有：

```text
input1
input2
output
```

形式的工作区域，并给出：

```text
NOT
AND
OR
XOR
plus
minus
+1
left shift
arithmetic right shift
logical right shift
```

等操作入口。

因此 ALU 的最合理还原是：

```text
register A
    │
    ├──复制──► input1 scratch
    │
register B
    │
    └──复制──► input2 scratch
                   │
                   ▼
          Boolean/shift microcode
                   │
                   ▼
               output scratch
                   │
                   └──写回──► destination register
```

### 7.1 位运算为什么能只靠 Vim 做

假设 bit-string 是：

```text
010101001
```

Vim 完全有能力：

- 移到第 n 个字符；
- 选中字符；
- 查找 `0` 或 `1`；
- 根据当前字符选择不同处理路径；
- 把字符替换为另一个字符；
- 向左/右移动到下一位。

因此一个 Boolean gate 可以非常机械地实现。

概念上：

```text
A[n], B[n]
    │
    ▼
利用字符搜索 / 位置移动判断当前组合
    │
    ▼
选择结果 "0" 或 "1"
    │
    ▼
写入 output[n]
```

效率极低，但逻辑完全可行。

### 7.2 加法不是 Vim 的数字 `+` 运算

这里有一个容易产生误解的地方。

Vim 自己当然拥有某些数字操作，但这个项目展示的 ALU 结构明显是围绕 bit-string 和 Boolean primitive 组织的。

因此 `add` 更像：

```text
逐 bit 处理
sum   = XOR
carry = AND / OR 组合
carry 传递到下一位
```

也就是说，这个项目有意把“加法器”降到文本上的逻辑门级别，而不是把整个数偷偷交给某个高级脚本语言处理。

这也是它被作者称作 “CPU” 而不仅仅是“汇编解释器”的主要趣味所在。

---

# 8. bit width 为什么必须提前配置

源码要求用户先在 bit-setting 区域改变一串 `0` 的长度，再运行生成宏。

例如概念上：

```text
000000000
```

表示一个固定宽度的 bit-vector。

在真实 CPU 上，寄存器位宽天然存在：

```text
8 / 16 / 32 / 64 bit
```

这里没有物理位宽，因此作者只能让**字符串长度承担 word size**。

于是：

```text
000000000
```

不是普通常量，而同时定义了：

- 二进制值的工作宽度；
- ALU 要循环多少个字符；
- decimal↔binary 表要生成多宽；
- heap 地址可以覆盖多大范围；
- overflow / carry 的边界。

所以这台 VM 的“字长”实际上是：

```text
len(bit_string)
```

---

# 9. 十进制并不是原生类型，而是一层编解码

源码区分：

```text
mov / out
dmov / dout
```

其中 `d` 版本用于 decimal。

这说明 guest ISA 的核心数据格式仍然更接近二进制字符串，而十进制是附加语法糖。

逻辑上：

```text
dmov rax,d5
      │
      ▼
decimal "5"
      │
      ▼
查预生成 decimal→binary chart
      │
      ▼
固定宽度 bit-string
      │
      ▼
写入 rax
```

反方向：

```text
dout rax
      │
      ▼
rax 中的 bit-string
      │
      ▼
binary→decimal 映射
      │
      ▼
把可读十进制写到 STDOUT
```

源码明确要求 decimal 功能先生成转换表，也再次说明：

> **转换本身也是文本映射，不是某个隐藏的整数对象。**

---

# 10. `STDOUT` 不是终端，是 buffer 中的一段文本

文件中直接存在一个：

```text
STDOUT
```

区域。

因此：

```asm
out rax
```

最合理的实现不是 `printf` 或 `echo`，而是：

```text
找到 rax 文本
   │
   ├─ yank
   ▼
找到 STDOUT
   │
   └─ paste
```

也就是说，输出设备也是“内存映射文本”。

从机器模型看，它类似：

```text
memory-mapped I/O
```

只不过所谓 “device register” 是一段叫 `STDOUT` 的文本区域。

---

# 11. Label 和 `jmp`：把 Vim 搜索当 branch unit

guest label 使用类似：

```text
__ label
```

的形式。

而跳转引用使用：

```text
__label
```

一类约定。

作者的 usage 说明明确规定了 label 的设置和使用格式。

有了这个规则以后，就根本不需要真正的数值 PC：

```text
jmp __loop
```

可以退化为：

```text
在 guest program 中搜索 "__ loop"
把光标移动过去
从那里恢复 dispatch
```

所以这台机器里：

```text
symbolic address resolution ≈ Vim search
```

这其实非常聪明。

传统 assembler/linker 需要把：

```text
loop
```

解析成：

```text
0x00401234
```

而 Vim 自己已经有字符串搜索，于是作者直接让**symbolic label 永远保持 symbolic**。

这种机器不需要真正做“label → byte offset”的链接，只需要：

```text
label → search pattern
```

---

# 12. PC/IP 其实是“光标 + mark”

这也是理解整个项目的关键。

真实 CPU：

```text
RIP = 当前机器指令地址
```

Vim-VM：

```text
current cursor / mark = 当前 guest 指令位置
```

于是：

```text
下一条指令
≈ j

前一条
≈ k

绝对微码地址
≈ <N>G

保存当前位置
≈ mA

恢复当前位置
≈ `A

跳到 label
≈ /pattern 或 ?pattern
```

因此这里根本不需要一枚专门的 PC register。

**Vim 编辑器本身已经提供了一个可移动的“指令指针”。**

---

# 13. `cmp / jz / jnc`：状态标志也是文本状态

源码提供：

```text
cmp
jz
jnc
```

因此 ALU 必须把某些结果状态保留下来，例如：

```text
zero
carry / no-carry
```

从源码结构看，这些状态不会是宿主 CPU 的 EFLAGS，而只能是：

- 某个 scratch 字符；
- 某段 buffer 状态；
- 某个特定工作区位置；
- 或一次 ALU 操作后遗留的可搜索文本条件。

因此：

```asm
cmp rax,rbx
jz __equal
```

大致是：

```text
cmp:
    把 A/B 放入 ALU 工作区
    做比较/减法
    将 zero/carry 条件编码进 scratch

jz:
    读取 zero scratch
    如果满足 → 搜索 __equal
    否则 → 继续下一条 guest 指令
```

具体 carry 的极性属于实现细节，不能只凭高层测试代码百分之百断言；但“flag 是 buffer 状态而不是硬件 flag”基本可以确定。

---

# 14. `push / pop`：真的在编辑一个叫 STACK 的文本区域

源码明确存在：

```text
STACK
```

而后面相关 Vim 微码大量出现对 `STACK` 的搜索、追加、选择最后一项、删除等操作。

因此：

```asm
push r6
```

可以还原成：

```text
定位 r6
  │
  ├─ yank value
  ▼
搜索 STACK
  │
  └─ append value
```

而：

```asm
pop r6
```

就是：

```text
搜索 STACK
  │
  ▼
选择 top
  │
  ├─ yank
  ├─ delete
  ▼
定位 r6
  │
  └─ replace
```

这不是“模拟一个数组作为栈”那么抽象：

**它真的就是一段随着 push/pop 而增长、缩短的文本。**

---

# 15. Heap：地址最终也是文本位置

源码还存在：

```text
HEAP
```

并支持：

```text
malloc
free
store
load
insert
```

作者特别说明：

> `malloc` / `free` 在这个 VM 中表示改变 heap 的大小。

这一点很重要。

它不像 C：

```c
ptr = malloc(n);
```

返回一块宿主内存的真实地址。

这里更像：

```text
malloc N
→ 让 HEAP 区域多出 N 个逻辑槽

free N
→ 缩短 HEAP 区域
```

guest 中的“地址”只是一个整数/bit-string，然后 handler 把它转换为：

```text
HEAP 基准位置 + 第 N 个逻辑文本槽
```

因此：

```asm
store [rbx],rax
```

可以理解为：

```text
decode rbx as N
      │
      ▼
定位 HEAP[N]
      │
      ▼
把 rax 的文本复制进去
```

`load` 则反向复制。

所以这里所谓 pointer，本质是：

> **一个经过 decimal/binary 编码的“文本槽索引”。**

---

# 16. `call / ret` 为什么比 `jmp` 难

`jmp` 很简单：

```text
搜索目标 label
```

但 `call` 必须多解决一个问题：

```text
跳过去以后，ret 怎么知道回哪里？
```

如果只有 Vim cursor，那么一旦搜索到 callee：

```text
caller 的旧位置就丢了
```

可以用 mark 保存一次，但递归调用会覆盖 mark，所以不能作为完整 call stack。

因此需要一个真正可嵌套的 return-address 机制。

---

# 17. 旧版 `call`：调用者手写唯一返回标识

源码的 usage 里保留了一段历史说明：

旧版需要调用者为每个 `call` 写一个唯一 flag，形式大意是：

```text
call <callee>,<unique-return-id>
```

这很好理解。

如果每个 call site 都有唯一字符串：

```text
addrA
addrB
addrC
```

那么进入 callee 前，只要把该字符串保存到 stack。

`ret` 时：

```text
pop return-id
search return-id
继续 call site 后一行
```

就完成了一个纯文本 return address。

这相当于把传统机器里的：

```text
return address = integer PC
```

替换成：

```text
return address = unique string
```

---

# 18. 新版 `call`：文件尾部其实藏了一个小型 linker/preprocessor

这也是文件名：

```text
asm_auto_set_addr_for_call_bk.txt
```

最有价值的部分。

源码 usage 说明：

```text
新版不再要求用户手写 unique flag，会自动设置
```

而在文件末尾可以观察到几个非常明确的线索：

```text
call _0
/search call _
,addr0000
```

以及一组用于：

- 扫描 guest 程序；
- 搜索下一个 `call _...`；
- 修改 call 行；
- 操作 `addr0000`；
- 再继续扫描；

的 Vim 宏。

因此可以相当有把握地判断：

> **执行 guest 程序之前，会先做一次 call-site 预处理，给 call 自动附加唯一返回 ID。**

概念上：

```text
原程序：

call __foo
...
call __bar
...
call __foo
```

被预处理为类似：

```text
call __foo,addr0000
...
call __bar,addr0001
...
call __foo,addr0010
```

实际编号格式以源文件宏为准，但核心思想就是：

```text
每个 call site → 一个唯一文本地址
```

这一步已经很像一个极简 linker。

---

# 19. 自动地址计数器为什么也很“Vim”

文件尾部不是简单写：

```text
counter++
```

而是保存一个：

```text
addr0000
```

样式的文本计数器，再通过 Vim 文本操作修改它。

因此 linker 自己也遵守这台机器的哲学：

```text
地址不是 integer object
地址是 string
递增不是 CPU add
递增是文本变换
```

这是整个工程最一致的地方之一：

> 它几乎从不跳出“所有状态都用文本表示”的模型。

---

# 20. `call / ret` 的完整推测路径

结合：

- usage 对 unique flag 的说明；
- 文件尾部自动生成 `addr...` 的宏；
- `STACK` 附近的 call/ret/push/pop 微码；
- 递归测试；

最合理的执行过程是：

```text
call __foo,addrNNNN
        │
        ├─ 保存 addrNNNN 到 STACK
        │
        ├─ 搜索 callee "__ foo"
        │
        └─ 从 callee 开始 dispatch
```

而：

```text
ret
        │
        ├─ 从 STACK 取出最近的 return-id
        │
        ├─ 搜索该 ID 对应的 call site
        │
        ├─ 移到 call 后一条 guest 指令
        │
        └─ 恢复 dispatch
```

这自然支持递归，因为：

```text
call A
  call A
    call A
```

会形成：

```text
STACK:
addr_outer
addr_middle
addr_inner
```

`ret` 按 LIFO 顺序恢复即可。

源码中的递归 `countdown` / `log2` 测试正是在验证这一点。

---

# 21. 数据 stack 和 call stack 很可能是同一个 STACK

测试里存在这种结构：

```text
push r6
call ...
pop r6
```

如果 call/ret 也使用同一个 `STACK`，布局会是：

```text
push r6
STACK = [r6-value]

call f
STACK = [r6-value, return-address]

ret
STACK = [r6-value]

pop r6
STACK = []
```

这正好符合预期。

因此没有必要为 return address 再创建第二个独立栈。

从源码中 call/ret/push/pop 都在同一片 `STACK` 微码附近这一点看，**共享一个 LIFO 文本区**是最合理的解释。

---

# 22. 为什么递归真的能成立

递归需要至少：

1. 可保存 caller 的返回位置；
2. 多层返回位置不能互相覆盖；
3. callee 可以再 call 自己；
4. ret 必须恢复最近一层；
5. 局部需要保存的寄存器可用 push/pop 保留。

这个 VM 已经具备：

```text
unique textual return-id
+
STACK
+
label search
+
push/pop
```

所以递归并不需要任何额外“魔法”。

传统机器：

```text
CALL:
    push RIP_next
    RIP = target

RET:
    RIP = pop()
```

Vim-VM：

```text
CALL:
    push textual_return_id
    search(target)

RET:
    id = pop()
    search(id)
    move to next guest line
```

两者的控制结构实际上高度同构。

---

# 23. `end` 和“故意的红色错误”

usage 有一个非常反直觉的说明：

- 每个 action 结束时看到 Vim 红色 error 是设计行为；
- 如果没有出现预期 error，却停在奇怪位置，反而才可能是真的错。

这说明作者把 Vim 某些失败状态当成了：

```text
macro delimiter / sentinel / stage terminator
```

在常规软件里：

```text
error = exception
```

在这个项目中部分场景更像：

```text
expected Vim error = “这段宏已经跑到边界”
```

这也是 shell-golf / editor-esolang 风格项目常见的技巧：

**利用宿主系统原本代表错误的行为作为控制流。**

因此不能用正常 Vim 用户的直觉判断它“有没有报错”。

---

# 24. 一个 `add rax,rbx` 大概经历什么

不追求逐字符复原，可以得到下面这个体系结构级 trace：

```text
Guest:
    add rax,rbx
```

### Phase A — fetch

```text
cursor/mark 指向 "add rax,rbx"
```

### Phase B — opcode decode

```text
select "add"
search ASM_manual
read add 对应 handler index
execute handler line with yy@0
```

### Phase C — operand decode

```text
select "rax"
search ASM_manual
resolve rax slot

select "rbx"
search ASM_manual
resolve rbx slot
```

### Phase D — stage inputs

```text
copy rax bit-string → ALU input1
copy rbx bit-string → ALU input2
```

### Phase E — ALU

```text
逐位 add / carry propagation
→ output scratch
```

### Phase F — write back

```text
copy output scratch → destination register
```

从测试写法看，二元 ALU 指令的目的寄存器通常就是第一个 operand。

### Phase G — resume

```text
restore guest program cursor/mark
advance to next instruction
dispatch again
```

---

# 25. 一个递归 `call __countdown` 大概经历什么

执行前：

```text
current guest line = call __countdown,addrNNNN
```

### Call

```text
1. 解析 callee
2. 解析/取得自动生成的 addrNNNN
3. 把 addrNNNN 追加进 STACK
4. 搜索 "__ countdown"
5. 把 cursor 移到目标位置
6. dispatch callee 第一条指令
```

如果 callee 再 call 自己：

```text
STACK
addr_outer
addr_inner
```

### Ret

```text
1. 找 STACK top
2. yank return-id
3. 删除 top
4. 在 guest 区搜索对应 call-site id
5. 移到该 call 的下一条指令
6. 恢复 dispatch
```

这样一来，即使 callee 深度递归，返回链仍然存在于 buffer 里的文本 STACK 中。

---

# 26. 它为什么能“像 CPU”，但又不是硬件 CPU

从抽象结构看，它确实包含很多 CPU/VM 部件：

```text
ISA
register file
ALU
flags
branch
stack
heap
load/store
call/ret
I/O
instruction dispatch
```

所以称它为 “CPU” 并非完全胡说。

但必须分清层级：

真正执行：

```text
character search
memory move
string replacement
cursor movement
```

的仍然是 Vim 本体，以及 Vim 背后的真实 CPU。

因此它更准确地属于：

```text
hosted virtual machine
+
esoteric interpreter
+
text-rewriting machine
```

而不是：

```text
hardware CPU emulator at transistor level
```

它模拟的是**抽象机器语义**，不是晶体管、电路时序或真实总线。

---

# 27. 从计算模型看，它更像“重写系统”

普通程序员会把状态写成：

```python
rax = ...
stack = [...]
heap = [...]
pc = ...
```

这个项目则把状态全部外化成文本，然后让每一步执行成为：

```text
寻找某段文本
→ 选中
→ 复制/删除/替换
→ 把光标移动到另一段文本
→ 把另一行重新解释成命令
```

所以更底层地说，这台机器是一种：

> **基于字符串定位和局部重写的状态机。**

guest 汇编只是一层更友好的表面语法。

---

# 28. 最值得注意的“自举”结构

它有一种很有意思的层层解释：

```text
ASM 文本
   │
   ▼
Vim 宏解析 ASM 文本
   │
   ▼
Vim 宏又从 buffer 中读取另一段 Vim 宏
   │
   ▼
yy@0 执行
   │
   ▼
宏修改同一个 buffer
   │
   ▼
产生新的机器状态
```

即：

```text
text describes commands
commands manipulate text
some manipulated text is again interpreted as commands
```

这是一种很典型的 homoiconic / code-as-data 趣味，只不过它不是 Lisp AST，而是**编辑器按键流**。

---

# 29. 为什么 `ASM_manual` 这个设计很关键

如果作者直接为每条 ASM 指令硬编码一大段跳转逻辑：

```text
if add ...
if sub ...
if mov ...
```

源码会更加难维护。

现在用了：

```text
token → number
```

文本表，就把 parser 和 handler 解耦了。

于是新增一个 guest opcode，大致只需要：

```text
1. 写一个新的 Vim handler
2. 在 ASM_manual 添加 opcode → handler-location
```

寄存器也是一样。

因此 `[ASM_manual]` 实际承担了多个角色：

```text
opcode table
register table
symbol-to-microcode mapping
poor man's dictionary
```

在一个完全没有真正 hash map / struct 的环境里，这是很合理的做法。

---

# 30. 为什么有很多 `buffer` 行

源码中散落着多个字面量：

```text
buffer
```

并且 handler 附近经常可以看到：

```text
把某段 token yank 出来
→ 跳到 buffer
→ 插入搜索/跳转命令
→ yy@0
```

因此这些区域很可能是**命令拼装 scratchpad**。

也就是说，有些间接操作不是直接执行固定宏，而是：

```text
模板："gg/ASM_manual..."
+
动态 token："rax"
+
动态数字："37"
=
临时 Vim command string
```

然后：

```text
yy@0
```

执行拼出来的字符串。

这相当于：

```python
code = template.format(token)
eval(code)
```

只是全部通过 Normal mode 文本操作完成。

---

# 31. 这份文件实际上包含一个非常简陋的 toolchain

如果把它按编译系统术语重新命名，大概是：

```text
source language
    custom ASM
        │
        ▼
preprocessor
    label/call-site normalization
    auto return-address generation
        │
        ▼
decoder
    ASM_manual token lookup
        │
        ▼
microcode interpreter
    Vim Normal-mode command sequences
        │
        ▼
runtime state
    registers / stack / heap / flags / stdout
```

所以它不只是“CPU”。

它里面至少揉在一起了：

- assembler parser；
- symbol resolver；
- tiny linker；
- VM runtime；
- ALU；
- memory model；
- call stack；
- output device。

---

# 32. 性能为什么会极差

真实 CPU 做一次：

```text
ADD
```

可能只需几个内部微操作。

这台 VM 做一次 `add`，可能需要：

```text
搜索 ASM_manual
复制 token
解析两个 operand
多次跨 buffer 跳转
复制两个 bit-string
逐 bit 搜索/修改
传播 carry
写回结果
恢复 guest cursor
再次 dispatch
```

每一项底下又是 Vim 自己对文本结构的处理。

因此这是典型的：

```text
巨大的 interpretation overhead
×
巨大的 text manipulation overhead
×
逐 bit 运算
```

源码说完整测试大概要几十秒到约一分钟，这完全符合这种实现方式。

这个项目追求的显然不是速度，而是：

> **证明“仅凭 Vim Normal-mode 文本编辑原语，也可以搭出一套像样的计算机抽象”。**

---

# 33. 安全边界

虽然扩展名是 `.txt`，但这不是“被动文本”。

原因：

```text
yy@0
```

会主动执行文件里的按键序列。

Vim 的宏理论上还可以触发：

- Ex command；
- shell command；
- 写文件；
- 调用插件/映射；
- 其他宿主环境行为。

这份文件的设计目标看起来是文本 VM，但安全上仍然应采用：

```text
陌生文本 + 不执行宏
```

和：

```text
陌生文本 + @0 执行
```

完全不同的威胁模型。

如果要实验，合理做法是：

- 使用隔离环境；
- 用干净 Vim 配置；
- 不在有重要文件的工作目录；
- 先审查是否存在 `:`、shell escape、写文件等行为；
- 不因为后缀是 `.txt` 就认为执行其中宏天然安全。

---

# 34. 可以确定 vs. 反推的部分

| 结论 | 置信度 | 依据 |
|---|---:|---|
| 这是用 Vim Normal mode 构造的 CPU/VM | 很高 | 文件自己的 fast-start/usage |
| `yy@0` 是“取微码并执行”的核心原语 | 很高 | 启动方式和源码反复使用 |
| `[ASM_manual]` 是 opcode/register 的查表分派表 | 很高 | 明确存在 token→数字映射，handler 反复搜索它 |
| register 是 buffer 中固定文本状态 | 很高 | 映射结构 + 字符串可直接存 register 的说明 |
| `STDOUT` 是 buffer 输出区 | 很高 | 明确存在 `STDOUT` 区且 `out` handler 搜索它 |
| stack/heap 都由真实文本区域承载 | 很高 | 明确存在 `STACK`、`HEAP` 以及相关操作 |
| decimal 依赖预生成转换表 | 很高 | usage 明确要求 |
| label 跳转依赖 Vim 搜索 | 很高 | label 语法 + handler 中大量 `/`、`?` |
| 新版 call 会自动生成唯一文本返回地址 | 很高 | usage + 文件尾 `call _...` / `addr0000` 预处理 |
| return-id 被放进同一个 STACK | 高 | call/ret 与 STACK 微码结构 + 递归测试 |
| ALU 是逐 bit 的文本 Boolean 运算 | 高 | input/output scratch + Boolean primitive + bit width |
| 具体 carry flag 的 0/1 极性 | 中 | 可从测试推测，但需要逐字符执行才能完全确认 |
| 每一个 handler 的精确逐字符语义 | 中 | 控制字符密集，浏览器展示会损失可读性；需在隔离 Vim 中单步追踪才能做到逐键证明 |

---

# 35. 最终的机器模型

可以把整套系统压缩成下面这张图：

```text
                         ┌─────────────────┐
                         │   Guest ASM     │
                         │ add / call ...  │
                         └────────┬────────┘
                                  │ fetch token
                                  ▼
                         ┌─────────────────┐
                         │   ASM_manual    │
                         │ token → number  │
                         └────────┬────────┘
                                  │ indirect dispatch
                                  ▼
                         ┌─────────────────┐
                         │ Vim microcode   │
                         │ G w v y p / @0  │
                         └───────┬─────────┘
                                 │
                 ┌───────────────┼────────────────┐
                 ▼               ▼                ▼
          ┌────────────┐  ┌────────────┐   ┌────────────┐
          │ Registers  │  │    ALU     │   │  Control   │
          │ text slots │  │ bit text   │   │ cursor     │
          └──────┬─────┘  └──────┬─────┘   │ search     │
                 │               │          │ marks      │
                 └───────┬───────┘          └─────┬──────┘
                         │                        │
                         ▼                        ▼
                    ┌─────────┐              ┌─────────┐
                    │  STACK  │              │  HEAP   │
                    │  text   │              │  text   │
                    └────┬────┘              └────┬────┘
                         │                        │
                         └──────────┬─────────────┘
                                    ▼
                               ┌─────────┐
                               │ STDOUT  │
                               │  text   │
                               └─────────┘
```

宿主层真正的“CPU”还是运行 Vim 的现实机器。

但在抽象层上：

```text
buffer = machine state
cursor = PC
marks = temporary pointers
search = branch/symbol resolver
yank/paste = data movement
text replacement = state transition
@0 = indirect execution
Vim macro lines = microcode
ASM_manual = decoder table
```

组合起来以后，它确实形成了一台完整度相当高的文本虚拟机。

---

# 36. 一句话评价

这个项目最厉害的地方不是“Vim 能做加法”。

而是作者发现了：

```text
Vim buffer 可充当统一存储
Vim cursor 可充当 PC
Vim search 可充当跳转和符号解析
Vim register 可充当代码搬运通道
@0 可充当间接执行
文本重写可充当状态转移
```

一旦这几个原语拼起来，剩下的：

```text
寄存器
ALU
栈
堆
分支
函数
递归
输出
```

都只是工程量问题。

所以从计算机原理的角度，这不是单纯的 Vim 炫技，而是一个很纯粹的例子：

> **只要一个系统能保存状态、按状态选择动作、修改状态并重新解释部分状态为动作，就足以在上面构造另一层抽象机器。**

---

## 附：源码中最值得继续单步验证的区域

如果以后要做到“逐按键级逆向”，优先级建议：

1. `[ASM_manual]` 附近：确认完整 fetch/decode 流程。
2. `add/sub` handler：确认 bit carry 的具体传播方式。
3. `cmp/jz/jnc`：确认 flag 的实际编码和 carry 极性。
4. `STACK` 附近：逐字符确认 call/ret 与 push/pop 是否完全共用一个栈。
5. 文件末尾：逐步跟踪 `addr0000` 如何递增、如何附着到每个 call site。
6. `HEAP` handler：确认一个 logical heap cell 究竟对应 word、line 还是 delimiter-separated field。
7. fast-start 的 decimal chart generator：确认生成表的精确布局。

这些部分如果放到一个隔离 Vim 里，通过 `:set showcmd`、寄存器查看、逐宏执行和每一步 buffer diff，可以进一步做成严格的“微码反汇编”。

---

## Source

原始文件：

<https://shared.ymodatabase.top/asm_auto_set_addr_for_call_bk.txt>

本文分析基于该文件当前公开版本的结构、usage 说明、ASM 测试程序、`ASM_manual` 映射、`STACK/HEAP/STDOUT` 区域以及文件尾部的 call-address 预处理宏。
