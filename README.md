# HQC-ASP: HQC 稀疏多项式乘法硬件加速器

基于移位累加 (Add-and-Shift) 的 HQC-KEM 多项式乘法器 RTL 实现，支持 HQC-1/3/5 三个安全等级。

在 GF(2)[x]/(x^n - 1) 上计算稠密多项式与稀疏多项式的乘积：

$$\text{result} = \bigoplus_{i=0}^{w-1} (dense \lll pos_i)$$

其中 $pos_i$ 为稀疏多项式的非零位位置，$w$ 为汉明重量。

## HQC 参数集

| Instance | Security | $n$    | $\omega$ | $\omega_{r,e}$ | $n/128$ | $n\bmod 128$ |
| -------- | -------- | ------ | -------- | --------------- | ------- | ------------- |
| HQC-1    | NIST-1   | 17,669 | 66       | 75              | 138     | 5             |
| HQC-3    | NIST-3   | 35,851 | 100      | 114             | 280     | 11            |
| HQC-5    | NIST-5   | 57,637 | 131      | 149             | 450     | 37            |

## 性能 (Verilator 仿真)

| 配置 | 汉明重量 | 周期数 | 每位置平均周期 |
| ---- | -------- | ------ | -------------- |
| HQC-1 ($\omega$) | 66 | 9,572 | ~145 |
| HQC-1 ($\omega_{r,e}$) | 75 | 10,876 | ~145 |
| HQC-3 ($\omega$) | 100 | 28,702 | ~287 |
| HQC-3 ($\omega_{r,e}$) | 114 | 32,720 | ~287 |
| HQC-5 ($\omega$) | 131 | 59,869 | ~457 |
| HQC-5 ($\omega_{r,e}$) | 149 | 68,095 | ~457 |

每位置周期数约为 $\lceil n/128 \rceil + 7$，整体复杂度 $O(\omega \cdot \lceil n/128 \rceil)$。

## 架构

核心模块 `HQC_ASP_Top` 采用两级状态机设计：

- **外层 FSM (out_state)**：控制整体流程，包括预取尾部/头部数据、加载稀疏位置、启动单次计算
- **内层 FSM (calc_state)**：执行单个位置的移位异或，分三段处理：
  - **SEG_A**：处理循环移位的回绕部分 (wrap-around)
  - **SEG_B**：处理跨越 128-bit 字边界的拼接
  - **SEG_C**：处理正常顺序部分

数据通路为 128-bit 宽，通过桶形移位器 (barrel shifter) 从 256-bit 缓冲区中提取对齐后的 128-bit 数据，与输出 RAM 中的已有结果异或后写回。

### 存储接口

| BRAM | 用途 | 访问模式 |
| ---- | ---- | -------- |
| dense_ram | 稠密多项式 (128-bit × n_words) | 只读 |
| sparse_ram | 稀疏位置 (8 × 16-bit per word) | 只读 |
| result_ram | 输出多项式 | 读写 |

### HQC_MODE 编码

| HQC_MODE[2:0] | 含义 |
| ------------- | ---- |
| 3'b010 | HQC-1, weight = $\omega$ |
| 3'b011 | HQC-1, weight = $\omega_{r,e}$ |
| 3'b100 | HQC-3, weight = $\omega$ |
| 3'b101 | HQC-3, weight = $\omega_{r,e}$ |
| 3'b110 | HQC-5, weight = $\omega$ |
| 3'b111 | HQC-5, weight = $\omega_{r,e}$ |

## HQC-KEM 中的乘法调用

| 操作 | 多项式乘法 | 右操作数重量 |
| ---- | ---------- | ------------ |
| KeyGen | $h \cdot y$ | $\omega$ |
| Encaps | $h \cdot r_2,\ s \cdot r_2$ | $\omega_{r,e}$ |
| Decaps | $u \cdot y,\ h \cdot r_2',\ s \cdot r_2'$ | $\omega$ 和 $\omega_{r,e}$ |

## 项目结构

```
HQC-ASP/
├── vsrc/
│   ├── HQC_ASP_Top.sv      # 核心乘法器 RTL
│   ├── TEST_PLATFORM.sv     # 仿真顶层 (连接 BRAM)
│   └── TEST_MEMORY.sv       # DPI-C BRAM 模型
├── csrc/
│   ├── sim.cpp              # Verilator 仿真驱动
│   ├── memory.cpp/h         # DPI-C 内存读写实现
│   └── config.h             # 仿真配置 (MAX_SIM_TIME)
├── pysrc/
│   ├── regression_test_all.py   # 全等级回归测试
│   ├── regression_test_multi.py # 多系数回归测试
│   └── test_single_pos.py      # 单位置调试测试
└── makefile                 # 构建脚本
```

## 快速开始

### 依赖

- Verilator
- Python 3 + NumPy

### 构建

```bash
make build
```

### 运行仿真

```bash
# 指定 HQC_MODE (默认 2 = HQC-1)
./obj_dir_fst/VTEST_PLATFORM 2    # HQC-1
./obj_dir_fst/VTEST_PLATFORM 4    # HQC-3
./obj_dir_fst/VTEST_PLATFORM 6    # HQC-5
```

### 回归测试

```bash
# 测试所有等级 (每个 10 组随机向量)
python3 pysrc/regression_test_all.py

# 仅测试 HQC-5, 50 组
python3 pysrc/regression_test_all.py --mode 5 --num-tests 50

# 跳过编译
python3 pysrc/regression_test_all.py --no-build
```

## 波形调试

```bash
make run          # 生成 waveform.fst
make see          # GTKWave 打开波形
```

在 `csrc/config.h` 中添加 `#define TRACE_ON` 可启用波形输出（会显著降低仿真速度）。
