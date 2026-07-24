package aho4cj

import std.collection.ArrayList

/** packed 搜索器支持的左最匹配语义。 */
public enum PackedMatchKind {
    | LeftmostFirst
    | LeftmostLongest
}

/** packed 搜索器配置。 */
public class PackedConfig {
    private var configuredKind: PackedMatchKind = PackedMatchKind.LeftmostFirst

    public init() {}

    public func matchKind(kind: PackedMatchKind): PackedConfig {
        configuredKind = kind
        return this
    }

    public func builder(): PackedBuilder {
        return PackedBuilder(configuredKind)
    }
}

/** 累积最多 128 个非空模式并构建 PackedSearcher。 */
public class PackedBuilder {
    private let patterns = ArrayList<Array<Byte>>()
    private let configuredKind: PackedMatchKind
    private var inert = false

    public init() {
        configuredKind = PackedMatchKind.LeftmostFirst
    }

    init(kind: PackedMatchKind) {
        configuredKind = kind
    }

    public func add(pattern: String): PackedBuilder {
        return addBytes(pattern.toArray())
    }

    public func addBytes(pattern: Array<Byte>): PackedBuilder {
        if (inert) {
            return this
        }
        if (patterns.size >= 128 || pattern.size == 0) {
            inert = true
            patterns.clear()
            return this
        }
        patterns.add(copyPackedBytes(pattern))
        return this
    }

    public func addAll(newPatterns: Array<String>): PackedBuilder {
        for (pattern in newPatterns) {
            add(pattern)
        }
        return this
    }

    public func addAllBytes(newPatterns: Array<Array<Byte>>): PackedBuilder {
        for (pattern in newPatterns) {
            addBytes(pattern)
        }
        return this
    }

    public prop length: Int64 {
        get() {
            patterns.size
        }
    }

    public prop minimumPatternLength: Int64 {
        get() {
            if (patterns.size == 0) {
                return 0
            }
            var minimum = patterns[0].size
            for (pattern in patterns) {
                if (pattern.size < minimum) {
                    minimum = pattern.size
                }
            }
            return minimum
        }
    }

    public func build(): Option<PackedSearcher> {
        if (inert || patterns.size == 0) {
            return None
        }
        return Some(PackedSearcher(patterns.toArray(), configuredKind))
    }
}

/** 针对少量非空字节模式的独立左最搜索器。 */
public class PackedSearcher {
    private let patterns: Array<Array<Byte>>
    private let configuredKind: PackedMatchKind

    init(patterns: Array<Array<Byte>>, kind: PackedMatchKind) {
        this.patterns = Array<Array<Byte>>(patterns.size, {index => copyPackedBytes(patterns[index])})
        this.configuredKind = kind
    }

    public static func new(patterns: Array<String>): Option<PackedSearcher> {
        return PackedBuilder().addAll(patterns).build()
    }

    public static func newBytes(patterns: Array<Array<Byte>>): Option<PackedSearcher> {
        return PackedBuilder().addAllBytes(patterns).build()
    }

    public static func config(): PackedConfig {
        return PackedConfig()
    }

    public static func builder(): PackedBuilder {
        return PackedBuilder()
    }

    public func find(haystack: String): Option<Match> {
        return findBytes(haystack.toArray())
    }

    public func findBytes(haystack: Array<Byte>): Option<Match> {
        return findInBytes(haystack, Span(0, haystack.size))
    }

    public func findIn(haystack: String, span: Span): Option<Match> {
        return findInBytes(haystack.toArray(), span)
    }

    public func findInBytes(haystack: Array<Byte>, span: Span): Option<Match> {
        if (span.start > span.end || span.end > haystack.size) {
            throw IllegalArgumentException("packed 搜索区间 ${span.toString()} 超出输入长度 ${haystack.size}")
        }
        for (start in span.start..span.end) {
            var selectedPattern: Int64 = -1
            var selectedLength: Int64 = -1
            for (patternId in 0..patterns.size) {
                let pattern = patterns[patternId]
                if (start + pattern.size > span.end || !packedBytesEqualAt(haystack, pattern, start)) {
                    continue
                }
                if (selectedPattern < 0 || isBetterPackedPattern(
                    patternId,
                    pattern.size,
                    selectedPattern,
                    selectedLength,
                    configuredKind
                )) {
                    selectedPattern = patternId
                    selectedLength = pattern.size
                }
            }
            if (selectedPattern >= 0) {
                return Some(Match(selectedPattern, start, start + selectedLength))
            }
        }
        return None
    }

    public func findIter(haystack: String): PackedMatchIterator {
        return findIterBytes(haystack.toArray())
    }

    public func findIterBytes(haystack: Array<Byte>): PackedMatchIterator {
        return PackedMatchIterator(this, haystack)
    }

    public prop matchKind: PackedMatchKind {
        get() {
            configuredKind
        }
    }

    /** 纯仓颉实现没有 Teddy 的最短输入限制。 */
    public prop minimumHaystackLength: Int64 {
        get() {
            0
        }
    }

    public prop minimumPatternLength: Int64 {
        get() {
            var minimum = patterns[0].size
            for (pattern in patterns) {
                if (pattern.size < minimum) {
                    minimum = pattern.size
                }
            }
            return minimum
        }
    }

    public prop memoryUsage: Int64 {
        get() {
            var bytes: Int64 = 0
            for (pattern in patterns) {
                bytes += pattern.size
            }
            return bytes
        }
    }
}

public class PackedMatchIterator <: Iterator<Match> {
    private let searcher: PackedSearcher
    private let haystack: Array<Byte>
    private var cursor: Int64 = 0

    init(searcher: PackedSearcher, haystack: Array<Byte>) {
        this.searcher = searcher
        this.haystack = haystack
    }

    public func next(): Option<Match> {
        if (cursor > haystack.size) {
            return None
        }
        match (searcher.findInBytes(haystack, Span(cursor, haystack.size))) {
            case Some(matched) =>
                cursor = matched.end
                return Some(matched)
            case None =>
                cursor = haystack.size + 1
                return None
        }
    }
}

func isBetterPackedPattern(
    patternId: Int64,
    length: Int64,
    selectedPattern: Int64,
    selectedLength: Int64,
    kind: PackedMatchKind
): Bool {
    match (kind) {
        case PackedMatchKind.LeftmostFirst => patternId < selectedPattern
        case PackedMatchKind.LeftmostLongest => length > selectedLength || (length == selectedLength && patternId <
            selectedPattern)
    }
}

func packedBytesEqualAt(haystack: Array<Byte>, pattern: Array<Byte>, start: Int64): Bool {
    for (index in 0..pattern.size) {
        if (haystack[start + index] != pattern[index]) {
            return false
        }
    }
    return true
}

func copyPackedBytes(bytes: Array<Byte>): Array<Byte> {
    return Array<Byte>(bytes.size, {index => bytes[index]})
}
