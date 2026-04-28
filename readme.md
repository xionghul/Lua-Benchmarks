# Lua Benchmarks

Compare the performance of different Lua implementations

## Sample Results

Computer information:

```
Distro: CentOS release 6.8 (Final)
Kernel: 2.6.32-642.13.1.el6.x86_64
CPU:    Intel(R) Core(TM) i7-4770 CPU @ 3.40GHz
```
![](https://raw.githubusercontent.com/gligneul/Lua-Benchmarks/master/results/speedup_luajit.png)
![](https://raw.githubusercontent.com/gligneul/Lua-Benchmarks/master/results/speedup_lua53.png)
![](https://raw.githubusercontent.com/gligneul/Lua-Benchmarks/master/results/speedup_lua5.png)

## Usage

```
usage: lua runbenchmarks.lua [options]
options:
    --preset <name>  lua | luajit | combined | all (default = lua)
                     lua=仅 lua-base vs lua-perf；luajit=luajit-base vs luajit-perf；
                     combined=同一轮测四项后输出 (lua-base+luajit-base) vs (lua-perf+luajit-perf)；
                     all=一次跑四项，生成三组 txt/png：<output>_lua / _luajit / _combined
    --nruns <n>      number of times that each test is executed (default = 3)
    --no-supress     don't supress error messages from tests
    --output <name>  name of the benchmark output
    --normalize      normalize the result based on the first binary
    --speedup        compute the speedup based on the first binary
    --no-plot        don't create the plot with gnuplot
    --help           show this message
```

完整参数以 `lua runbenchmarks.lua --help` 为准。

## 运行说明（本仓库扩展）

### 依赖

- 系统已有：`lua`、`luajit`、`bash`、`time`；需要柱图时再安装 **`gnuplot`**。
- 对比 **PGO/perf** 构建时，需在本目录生成解压目录（见下）。

### 生成 `pgo_lua_root/` 与 `pgo_luajit_root/`

脚本会从仓库中的 **`PGO_RPMS`**（默认：本仓库向上两级目录下的 `PGO_RPMS`，即 `<hp_repo>/PGO_RPMS`）选取 `*.tl4.perf.x86_64.rpm` 并解压：

```bash
./extract_pgo_roots.sh
```

若 RPM 不在默认路径：

```bash
PGO_RPMS=/你的路径/PGO_RPMS ./extract_pgo_roots.sh
```

脚本会重建 **`pgo_lua_root`**（lua-libs + lua）、**`pgo_luajit_root`**（luajit）。末尾可按其提示执行 `lua -v` / `luajit -v` 自检。

### 运行基准

在 **`Lua-Benchmarks` 目录下**：

```bash
# 三组对比一次跑出：<prefix>_lua / _luajit / _combined（txt + png）
lua runbenchmarks.lua --preset all --speedup --output groups

# 仅 Lua base vs perf
lua runbenchmarks.lua --preset lua --speedup --output only_lua

# 仅 LuaJIT base vs perf
lua runbenchmarks.lua --preset luajit --speedup --output only_luajit

# 仅「同案例上 lua+luajit 耗时之和」base vs perf
lua runbenchmarks.lua --preset combined --speedup --output only_sum

# 快速试跑（少重复、不画图）
lua runbenchmarks.lua --preset all --nruns 1 --no-plot --output quick
```

`--speedup` 时：**第一列固定为 1.0（基准）**，第二列为 `T_基准 / T_对比`（**数值越大表示对比列越快**）。

### 输出

- 文本：`<output>.txt` 或 `--preset all` 时的 `<output>_lua.txt` 等。
- 图像：`gnuplot` 成功时生成对应的 `.png`（柱图依赖可用字体，Linux 下已改用 DejaVu Sans，见 `plot.gpi`）。

