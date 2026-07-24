# aho4cj

`aho4cj` 是 [BurntSushi/aho-corasick](https://github.com/BurntSushi/aho-corasick) 的纯仓颉移植，
用于在一段文本中同时查找多个模式。库内部构建 Trie、失败指针和输出链，搜索阶段不会逐个模式扫描输入。

当前版本已在仓颉 1.0.5 LTS 和 1.1.3 STS 工具链中完成构建与测试。项目不包含 FFI 和第三方运行时依赖。

## 功能

- 标准 Aho-Corasick 多模式搜索
- 非重叠搜索与重叠搜索
- `Standard`、`LeftmostFirst`、`LeftmostLongest` 三种匹配语义
- ASCII 忽略大小写匹配
- 字符串、任意字节和回调替换
- 空模式和重复模式
- UTF-8 字符串搜索，匹配位置采用字节偏移，与 Rust 上游一致
- 任意字节数组搜索与替换，可处理非 UTF-8 数据
- `Input` 搜索范围、锚定搜索和最早匹配
- 非连续 NFA、连续 NFA、DFA 和自动选择
- 字节类、可调稠密深度和纯仓颉预过滤
- 独立的 `PackedSearcher` 左最搜索接口（纯仓颉标量实现）
- `AutomatonView`、`StateID` 与原始状态转移/输出查询
- 真正惰性的普通、重叠和流式匹配迭代器
- 基于 `InputStream`/`OutputStream` 的跨缓冲区搜索与替换
- 自动机类型、内存估算、状态数和模式长度查询

主要性能边界是 SIMD 预过滤：Rust 上游通过 `memchr` 使用平台向量指令，仓颉标准库目前没有等价的公开字节搜索接口。
本项目使用专门化并展开的纯仓颉标量预过滤；同一稀疏字节基准约为 Rust 默认实现的 `2.68x`，且快于关闭预过滤的
Rust 连续 NFA。详细数据见
[性能基准](doc/benchmark.md)。

## 安装

在项目的 `cjpm.toml` 中添加源码依赖：

```toml
[dependencies]
  aho4cj = { path = "../aho4cj" }
```

发布到中心仓后，也可以改用对应的中心仓版本声明。

## 快速开始

```cangjie
package demo

import aho4cj.*

main(): Int64 {
    let patterns = ["apple", "maple", "Snapple"]
    let text = "Nobody likes maple in their apple flavored Snapple."
    let ac = AhoCorasick.new(patterns)

    for (matched in ac.findIter(text)) {
        println("模式 ${matched.pattern}: [${matched.start}, ${matched.end})")
    }
    return 0
}
```

输出的三个匹配分别为模式 `1` 的 `[13, 18)`、模式 `0` 的 `[28, 33)` 和模式 `2` 的 `[43, 50)`。

## 配置匹配语义

```cangjie
let ac = AhoCorasickBuilder()
    .matchKind(MatchKind.LeftmostFirst)
    .asciiCaseInsensitive(true)
    .build(["Samwise", "Sam"])

let matched = ac.find("SAMWISE")
```

- `Standard`：最早结束的匹配优先；同一位置结束时，更早开始的匹配优先。
- `LeftmostFirst`：最左位置优先，同一位置按模式传入顺序选择。
- `LeftmostLongest`：最左位置优先，同一位置选择最长模式。

重叠搜索仅支持 `Standard`。配置不支持重叠搜索或输入锚定模式不合法时会抛出带 `MatchErrorKind` 的
`MatchException`。与上游一致，锚定输入不能用于重叠迭代器，但可以配合 `OverlappingState` 逐次驱动。

## 范围与锚定搜索

```cangjie
let ac = AhoCorasickBuilder()
    .startKind(StartKind.Both)
    .build(["needle"])

let input = Input("xxneedle--needle")
    .span(2, 8)
    .anchored(Anchored.Yes)
let matched = ac.find(input)
// matched == Some(Match(pattern=0, start=2, end=8))
```

`Input` 的区间和 `Match` 均使用半开字节偏移。`StartKind.Unanchored` 是默认值；需要锚定查询时，应在构建时选择
`StartKind.Both` 或 `StartKind.Anchored`。

## 替换

```cangjie
let ac = AhoCorasick.new(["fox", "brown", "quick"])
let result = ac.replaceAll(
    "The quick brown fox.",
    ["sloth", "grey", "slow"]
)
// result == "The slow grey sloth."
```

替换数组必须与模式数组等长，并通过模式编号一一对应。

## 流式搜索

`streamFindIter` 从 `std.io.InputStream` 按需读取固定大小缓冲区，能识别跨读取边界的模式；`streamReplaceAll` 和
`streamReplaceAllWithBytes` 将结果写入 `OutputStream`，不会把完整输入载入内存。流式接口当前只支持
`MatchKind.Standard`、非锚定搜索和非空模式。

## 构建与测试

```bash
cjpm build
cjpm test
```

在同一工作树切换 1.0.5 与 1.1.3 时，建议为两个工具链指定不同的 `--target-dir`，避免增量缓存格式冲突。

测试覆盖三种运行时自动机、三种匹配语义、上游测试向量、穷举 oracle、锚定和范围搜索、重叠顺序、ASCII 大小写、任意字节、
空模式、回调替换、流式边界和异常分支。

## 文档

- [设计说明](doc/design.md)
- [功能与 API](doc/feature_api.md)
- [性能基准](doc/benchmark.md)
- [测试说明](test/README.md)
- [变更日志](CHANGELOG.md)

## 仓颉 AI 生态推荐

- [CangjieSkills](https://gitcode.com/Cangjie-SIG/CangjieSkills)：面向 AI 开发工具的仓颉程序开发 Skills，覆盖项目创建、配置、开发、构建、运行和单元测试。
- [ACEHarness](https://gitcode.com/Cangjie-SIG/ACEHarness)：面向工程任务的本地 AI Multi-Agent 协作平台，支持 Spec Driven Development、状态机工作流和 Supervisor 路由。
- [CangjieCorpus](https://gitcode.com/Cangjie/CangjieCorpus)：面向 RAG 的仓颉语言知识基座，整合开发指南、API 文档、示例和语法规范。
- [CangjieMagic](https://gitcode.com/Cangjie-TPC/CangjieMagic)：仓颉原生 LLM Agent 应用开发框架；示例见 [CangjieMagic-Examples](https://gitcode.com/Cangjie/CangjieMagic-Examples)。
- [magic-cli](https://gitcode.com/Cangjie-SIG/magic-cli)：基于 Cangjie Agent DSL 和 CangjieMagic 的 AI 命令行助手。
- [MagicExplorer](https://gitcode.com/Cangjie-TPC/MagicExplorer)：用于探索 Agent 开发与多 Agent 工程协作的示例应用。

## 许可证

本移植采用 MIT 许可证，详见 [LICENSE](LICENSE)。上游项目同时允许使用 MIT 或 Unlicense，来源信息见
[README.OpenSource](README.OpenSource)。
