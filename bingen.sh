#!/bin/bash

# 检查参数
if [ $# -eq 0 ]; then
    echo "用法: $0 <位数>"
    echo "示例: $0 4"
    exit 1
fi

bits=$1

# 计算总数
max=$((2 ** bits))

# 生成对照表
for ((i=0; i<max; i++)); do
    # 生成指定位数的二进制字符串（前导零填充）
    binary=$(printf "%0${bits}d" $(echo "obase=2;$i" | bc))
    echo -n "${binary} for d${i} "
done

