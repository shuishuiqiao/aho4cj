# 性能基准源码

本目录包含 Rust 上游与 `aho4cj` 的对比基准：

- `rust/`：Rust `aho-corasick` 1.1.4，Rust 1.89，`opt-level = 2`。
- `cangjie/`：当前工作树中的 `aho4cj`，Cangjie 1.1.3，`-O2`。
- `report.py`：校验两端输入元数据并生成 HTML 对比报告。

每项操作先预热 3 次，再采集 5 组结果并取中位数。输出的时间单位为纳秒，并按单次操作归一化。两端还会输出输入元数据、
匹配数量和校验和，`report.py` 只在这些数据一致时生成报告。

## 本地复现

在仓库根目录运行：

```bash
mkdir -p benchmark-results

(
  cd benchmark/rust
  CARGO_TARGET_DIR=/tmp/aho4cj-rust-benchmark \
    cargo run --release --locked > ../../benchmark-results/rust.csv
)

(
  cd benchmark/cangjie
  cjpm build --target-dir /tmp/aho4cj-cangjie-benchmark
  /tmp/aho4cj-cangjie-benchmark/release/bin/main \
    > ../../benchmark-results/cangjie.csv
)

python3 benchmark/report.py \
  benchmark-results/rust.csv \
  benchmark-results/cangjie.csv \
  /tmp/aho4cj-benchmark-report \
  local
```

持续集成使用固定 Docker 镜像运行相同步骤。最新结果由 GitHub Actions 生成并发布，不保存在仓库中。
