# aho4cj

`aho4cj` 是 [BurntSushi/aho-corasick](https://github.com/BurntSushi/aho-corasick) 的纯仓颉移植，
用于在一段文本中同时查找多个模式。库内部构建 Trie（字典树）、失败转移和输出链，搜索时无需逐个模式扫描输入。

当前版本已在仓颉 1.0.5 LTS 和 1.1.3 STS 工具链中完成构建与测试。项目不包含 FFI 和第三方依赖。

## 功能

- 标准 Aho-Corasick 多模式搜索
- 非重叠搜索与重叠搜索
- `Standard`、`LeftmostFirst`、`LeftmostLongest` 三种匹配策略
- ASCII 忽略大小写匹配
- 字符串替换、字节替换和回调替换
- 空模式和重复模式
- UTF-8 字符串搜索，匹配位置采用字节偏移，与 Rust 上游一致
- 任意字节数组搜索与替换，可处理非 UTF-8 数据
- `Input` 搜索范围、锚定搜索和最早匹配
- 非连续 NFA、连续 NFA、DFA 和自动选择
- 字节类、可调稠密深度和纯仓颉预过滤
- 独立的 `PackedSearcher` 最左匹配接口（纯仓颉标量实现）
- `AutomatonView`、`StateID` 与原始状态转移/输出查询
- 按需计算的普通、重叠和流式匹配迭代器
- 基于 `InputStream`/`OutputStream` 的跨 buffer 搜索与替换
- 自动机类型、内存估算、状态数和模式长度查询

仓颉实现目前采用纯标量预过滤，尚未使用 SIMD 等底层优化。性能对比及最新测试结果见[性能基准](doc/benchmark.md)。

## 安装

在项目的 `cjpm.toml` 中添加源码依赖：

```toml
[dependencies]
  aho4cj = { path = "../aho4cj" }
```

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

## 配置匹配策略

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

重叠搜索仅支持 `Standard`。如果自动机配置不支持重叠搜索，或者锚定方式与构建配置不兼容，接口会抛出包含
`MatchErrorKind` 的 `MatchException`。与上游一致，锚定输入不能用于重叠迭代器，但可以配合
`OverlappingState` 逐次驱动。

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

`Input` 的搜索范围和 `Match` 的匹配范围均采用以字节为单位的半开区间。`StartKind.Unanchored` 是默认值；需要
锚定查询时，应在构建时选择 `StartKind.Both` 或 `StartKind.AnchoredOnly`。

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

`streamFindIter` 从 `std.io.InputStream` 按需读取固定大小 buffer，支持跨 buffer 匹配；`streamReplaceAll` 和
`streamReplaceAllWithBytes` 将结果写入 `OutputStream`，不会把完整输入载入内存。流式接口当前只支持
`MatchKind.Standard`、非锚定搜索和非空模式。

## 构建与测试

```bash
cjpm build
cjpm test
```

在同一工作树切换 1.0.5 与 1.1.3 时，建议为两个工具链指定不同的 `--target-dir`，避免增量缓存格式冲突。

测试覆盖三种运行时自动机、三种匹配策略、上游测试向量、穷举对照验证、锚定与范围搜索、重叠匹配顺序、ASCII 大小写、
任意字节、空模式、回调替换、流式处理和异常分支。

## 双版本维护

`main` 保持对仓颉 1.0.5 LTS 的最低版本兼容，并同时通过 1.1.3 STS 测试。版本发布线分别为
`aho4cj_lt_1.0.5` 和 `aho4cj_st_1.1.3`，详细规则见[双版本维护说明](doc/version-support.md)。

## 文档

- [设计说明](doc/design.md)
- [功能与 API](doc/feature_api.md)
- [性能基准](doc/benchmark.md)
- [基准源码](benchmark/README.md)
- [测试说明](test/README.md)
- [双版本维护](doc/version-support.md)
