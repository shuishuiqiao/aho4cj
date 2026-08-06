# 性能基准

项目使用等价输入对比 Rust 上游与 `aho4cj` 的构建、稀疏搜索、字节搜索、纯字节遍历和高重叠搜索性能。
基准源码与本地复现方法见 [`benchmark/`](../benchmark/README.md)。

## 测试环境

- Rust：`aho-corasick` 1.1.4、Rust 1.89、`opt-level = 2`。
- 仓颉：当前提交中的 `aho4cj`、Cangjie 1.1.3、`-O2`。
- 两个实现由同一个 GitHub Actions runner 使用固定 Docker 镜像依次执行。

每项测试预热 3 次，再采集 5 组结果并取中位数。报告生成器会核对两端的输入长度、匹配数量和校验和；任一项不一致时，
工作流会失败。

## 最新结果

[GitHub Actions 工作流](../.github/workflows/tests-with-cov.yml)会在每次推送到 `main` 后重新运行基准，并将 HTML 报告和
原始 CSV 发布到项目的 GitHub Pages。共享 CI 主机存在计时抖动，结果适合发现明显的性能回归，不应替代固定硬件上的
严格性能评测。
