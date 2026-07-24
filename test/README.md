# 测试说明

仓颉 `cjpm` 要求单元测试文件以 `_test.cj` 结尾并与被测包源码放在同一包目录，因此可执行测试位于
[`src/aho_corasick_test.cj`](../src/aho_corasick_test.cj)。本目录保留测试入口说明，以满足三方库统一交付结构。

运行全部测试：

```bash
cjpm test
```

当前测试包含 52 个用例，覆盖以下内容：

- 上游 README 的基础搜索示例
- Trie 失败指针和后缀输出
- 三种 `MatchKind` 的优先级
- 重叠匹配顺序
- ASCII 忽略大小写
- 中文输入的 UTF-8 字节偏移
- 非 UTF-8 字节数组的搜索与替换
- 构建后模式字节的所有权隔离
- 按模式编号替换
- 空模式
- 非法操作配置与参数校验
- 非连续 NFA、连续 NFA 和 DFA 的结果一致性
- 字节类与稠密深度的内存/语义验证
- `Input` 范围、锚定与 earliest
- 惰性迭代器、重叠状态和跨缓冲区流式处理
- 锚定重叠迭代器的拒绝，以及 `OverlappingState` 的显式锚定驱动
- UTF-8 码点边界替换与可提前停止的内存/流式回调
- `MatchException` 稳定错误分类和流式空模式限制
- `AutomatonView` 的直接转移、失败转移、死状态和后缀输出
- `PackedSearcher` 的构建限制、字节所有权和穷举左最语义 oracle
- Rust 上游的 Standard、LeftmostFirst、LeftmostLongest、锚定、重叠和回归向量
- 小字母表穷举 oracle，交叉验证三种语义、三种后端、锚定和两条重叠实现路径
- 自动机状态、模式长度和内存统计

验证工具链：Cangjie 1.0.5 LTS 与 Cangjie 1.1.3 STS，均为 Linux x86_64 `cjnative`。

生成覆盖率：

```bash
cjpm test --coverage --target-dir target-coverage-1.1.3
cjcov \
  --root=. \
  --source=src \
  --exclude=src/aho_corasick_test.cj \
  --html-details \
  --output=coverage-site
```
