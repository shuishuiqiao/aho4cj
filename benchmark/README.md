# 性能基准源码

本目录保存 Rust 上游与 `aho4cj` 的同负载微基准驱动：

- `rust/`：Rust `aho-corasick` 1.1.4，Rust 1.89，`opt-level = 2`。
- `cangjie/`：当前工作树中的 `aho4cj`，Cangjie 1.1.3，`-O2`。
- `report.py`：校验两端输入元数据并生成 HTML 对比报告。

两端均预热 3 次，对 5 个样本取中位数；每个样本内部重复执行多次以降低计时分辨率和调度噪声。匹配结果会完整收集并
计算校验和，避免编译器删除搜索过程。

GitHub Actions 使用固定 digest 的 Rust 和仓颉镜像运行基准。原始 CSV 与 HTML 只发布到 Pages，不提交生成结果。
共享 CI 主机适合发现数量级回归；需要精确比较时，应在固定频率、固定硬件的隔离环境中重复运行。
