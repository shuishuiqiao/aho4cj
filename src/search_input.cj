package aho4cj

/** 搜索是否必须从 Input.start 开始匹配。 */
public enum Anchored {
    | No
    | Yes
}

/** 自动机允许的搜索起始模式。 */
public enum StartKind {
    | Both
    | Unanchored
    | AnchoredOnly
}

/** 自动机的运行时存储类型。 */
public enum AhoCorasickKind {
    | NoncontiguousNFA
    | ContiguousNFA
    | DFA
}

/** 半开字节区间。 */
public class Span {
    public let start: Int64
    public let end: Int64

    public init(start: Int64, end: Int64) {
        if (start < 0 || end < 0) {
            throw IllegalArgumentException("无效区间 [${start}, ${end})")
        }
        this.start = start
        this.end = end
    }

    public prop length: Int64 {
        get() {
            if (end > start) {
                end - start
            } else {
                0
            }
        }
    }

    public prop isEmpty: Bool {
        get() {
            start >= end
        }
    }

    public func contains(offset: Int64): Bool {
        return !isEmpty && start <= offset && offset <= end
    }

    /** 返回起止位置同时增加 offset 的新区间。 */
    public func offset(offset: Int64): Span {
        if (offset < 0) {
            throw IllegalArgumentException("区间偏移不能为负数")
        }
        return Span(start + offset, end + offset)
    }

    public func toString(): String {
        return "${start}..${end}"
    }
}

/** 一次搜索的输入、范围、锚定模式和最早匹配配置。 */
public class Input {
    public let haystack: Array<Byte>
    private var searchStart: Int64
    private var searchEnd: Int64
    private var anchorMode: Anchored = Anchored.No
    private var earliestMode: Bool = false

    public init(haystack: String) {
        this.haystack = haystack.toArray()
        this.searchStart = 0
        this.searchEnd = this.haystack.size
    }

    public init(haystack: Array<Byte>) {
        this.haystack = haystack
        this.searchStart = 0
        this.searchEnd = haystack.size
    }

    public func span(start: Int64, end: Int64): Input {
        setSpan(start, end)
        return this
    }

    public func anchored(mode: Anchored): Input {
        anchorMode = mode
        return this
    }

    public func earliest(enabled: Bool): Input {
        earliestMode = enabled
        return this
    }

    public func setSpan(start: Int64, end: Int64): Unit {
        if (start < 0 || end < 0 || end > haystack.size || start > end + 1) {
            throw IllegalArgumentException("搜索区间 [${start}, ${end}) 超出输入长度 ${haystack.size}")
        }
        searchStart = start
        searchEnd = end
    }

    public func setStart(start: Int64): Unit {
        setSpan(start, searchEnd)
    }

    public func setEnd(end: Int64): Unit {
        setSpan(searchStart, end)
    }

    public func setAnchored(mode: Anchored): Unit {
        anchorMode = mode
    }

    public func setEarliest(enabled: Bool): Unit {
        earliestMode = enabled
    }

    public prop start: Int64 {
        get() {
            searchStart
        }
    }

    public prop end: Int64 {
        get() {
            searchEnd
        }
    }

    public prop spanValue: Span {
        get() {
            Span(searchStart, searchEnd)
        }
    }

    public prop anchor: Anchored {
        get() {
            anchorMode
        }
    }

    public prop isEarliest: Bool {
        get() {
            earliestMode
        }
    }

    /** 搜索起点越过终点时，输入已耗尽。 */
    public prop isDone: Bool {
        get() {
            searchStart > searchEnd
        }
    }
}
