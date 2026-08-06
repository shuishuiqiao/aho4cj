# 功能与 API

## 核心类型

| 类型 | 作用 |
|---|---|
| `MatchKind` | `Standard`、`LeftmostFirst`、`LeftmostLongest` 三种匹配策略 |
| `Match` | 模式编号及 `[start, end)` 字节区间 |
| `Input` | 输入字节、搜索范围、锚定方式和最早匹配配置 |
| `Anchored` | 单次搜索是否必须从 `Input.start` 开始匹配 |
| `StartKind` | 自动机支持 `Unanchored`、`AnchoredOnly` 或 `Both` |
| `AhoCorasickKind` | `NoncontiguousNFA`、`ContiguousNFA` 或 `DFA` |
| `OverlappingState` | 保存逐次重叠搜索的迭代状态 |
| `MatchException` | 带稳定 `MatchErrorKind` 分类的搜索配置异常 |
| `AutomatonView` / `StateID` | 原始状态转移、状态属性与输出查询 |
| `PackedSearcher` | 最多 128 个非空模式的独立最左匹配搜索器 |

`Match.start`、`Match.end`、`Span` 和 `Input.span` 全部使用半开字节偏移。字符串先编码为 UTF-8，因此中文字符通常占
三个字节。

## 构建器

| API | 默认值 | 说明 |
|---|---|---|
| `matchKind(MatchKind)` | `Standard` | 设置匹配策略 |
| `asciiCaseInsensitive(Bool)` | `false` | 仅折叠 ASCII `A-Z`/`a-z` |
| `startKind(StartKind)` | `Unanchored` | 声明自动机支持的搜索起点模式 |
| `kind(AhoCorasickKind)` | 自动选择 | 强制运行时存储类型 |
| `automaticKind()` | 是 | 恢复自动选择 |
| `prefilter(Bool)` | `true` | 启用纯仓颉首字节预过滤 |
| `byteClasses(Bool)` | `true` | 合并等价输入字节以压缩表 |
| `denseDepth(Int64)` | `2` | 连续 NFA 的稠密状态深度 |
| `build(Array<String>)` | - | 从 UTF-8 字符串模式构建 |
| `buildBytes(Array<Array<Byte>>)` | - | 从任意字节模式构建 |

自动选择与 Rust 上游的高层策略一致：模式数不超过 100 且 `StartKind` 不是 `Both` 时选 DFA，否则选连续 NFA。

## 搜索

字符串 API 均有 `Bytes` 版本，并且主要搜索操作都接受 `Input`：

| API | 返回值 | 说明 |
|---|---|---|
| `find` | `Option<Match>` | 第一个非重叠匹配 |
| `isMatch` | `Bool` | 是否存在匹配 |
| `findIter` | `MatchIterator` | 惰性非重叠迭代器 |
| `findAll` | `Array<Match>` | 一次性收集非重叠结果 |
| `findOverlappingIter` | `MatchIterator` | 惰性重叠结果，仅 `Standard` |
| `findOverlapping` | `Option<Match>` | 配合 `OverlappingState` 逐次推进 |
| `findOverlappingAll` | `Array<Match>` | 优化的批量重叠扫描 |

`Input.earliest(true)` 忽略最左匹配策略，允许在确定任意最早结束匹配时立即返回。搜索方式与构建时的 `StartKind`
不兼容、使用最左匹配策略请求重叠结果等配置错误会抛出 `MatchException`；普通参数越界仍抛出
`IllegalArgumentException`。

锚定输入不能传给重叠迭代器或批量收集接口；如需锚定重叠语义，应使用 `OverlappingState` 逐次调用
`findOverlapping`。

## 替换

| API | 说明 |
|---|---|
| `replaceAll` | 按模式编号从字符串替换数组取值 |
| `replaceAllBytes` | 任意字节版本 |
| `replaceAllWith` | 回调接收 `Match` 和原始匹配字符串 |
| `replaceAllWithBytes` | 回调接收 `Match` 和原始匹配字节 |
| `replaceAllWithControlled` | 回调返回 `StringReplacement`，可替换后提前停止 |
| `replaceAllWithBytesControlled` | 任意字节的可停止回调替换 |

固定替换数组必须与模式数组等长。

## 流式接口

| API | 说明 |
|---|---|
| `streamFindIter(InputStream[, bufferSize])` | 固定 buffer 惰性搜索，支持跨读取边界匹配 |
| `streamReplaceAll(InputStream, OutputStream, replacements[, bufferSize])` | 固定替换数组 |
| `streamReplaceAllWithBytes(InputStream, OutputStream, callback[, bufferSize])` | 回调替换 |
| `streamReplaceAllWithBytesControlled(...)` | 可停止的回调替换，停止后原样复制剩余输入 |

流式操作只支持 `MatchKind.Standard`、允许非锚定搜索的自动机和非空模式。buffer 大小必须大于零。

## Packed 搜索

`PackedConfig`、`PackedBuilder` 和 `PackedSearcher` 对应上游公开的 `packed` 功能层，支持
`LeftmostFirst` 与 `LeftmostLongest`、范围搜索及惰性非重叠迭代。构建失败用 `Option.None` 表示；空模式、空模式集或
超过 128 个模式无法构建。

当前实现是语义等价的纯仓颉标量搜索器。Rust 上游会按架构选择 Teddy SIMD 或 Rabin-Karp；仓颉端未伪造同名 SIMD
实现，`PackedSearcher` 也暂未接入高层自动机预过滤器。

## 低层自动机

`ac.lowLevel()` 返回只读 `AutomatonView`，可查询起始状态、逐字节转移、死状态/匹配状态/特殊状态、状态输出、模式长度、
状态数和内存估算。锚定转移使用构建时冻结的 Trie 直接边，失败后进入稳定死状态；非锚定转移使用所选 NFA/DFA 后端。

## 元数据

`AhoCorasick` 提供 `kind`、`memoryUsage`、`stateCount`、`patternCount`、`minPatternLength`、
`maxPatternLength`、`configuredMatchKind` 和 `configuredStartKind`。`memoryUsage` 是自动机数组存储的近似字节数，
用于比较配置，不表示进程完整堆占用。

## 与 Rust 上游的不同

高层搜索、匹配选择、锚定范围、三种自动机、字节类、低层状态访问、packed 功能层、重叠状态、回调替换和流式处理均已
移植。API 采用仓颉的 `Array`、`Option`、`Iterator` 和异常模型，不复制 Rust 的 trait、生命周期、泛型 `PatternID`、
模块层级或 `Result` 外形；项目尚未发布，因此不提供旧 API 兼容层。

Rust 的 `memchr`/Teddy SIMD 预过滤没有纯仓颉等价实现。本项目使用标量预过滤并对常见单首字节场景做循环展开，保持
结果语义一致；稀疏吞吐仍低于启用 SIMD 的 Rust 默认实现。

## 工具链兼容性

- Cangjie 1.0.5 LTS，`cjnative`，Linux x86_64。
- Cangjie 1.1.3 STS，`cjnative`，Linux x86_64。
- 切换工具链时使用不同的 `--target-dir`，避免增量缓存格式冲突。
