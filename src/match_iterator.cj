package aho4cj

/** 匹配结果迭代器。 */
public class MatchIterator <: Iterator<Match> {
    private let producer: () -> Option<Match>

    init(producer: () -> Option<Match>) {
        this.producer = producer
    }

    public func next(): Option<Match> {
        return producer()
    }
}

/** 从 InputStream 按需读取的匹配结果迭代器。 */
public class StreamMatchIterator <: Iterator<Match> {
    private let producer: () -> Option<Match>

    init(producer: () -> Option<Match>) {
        this.producer = producer
    }

    public func next(): Option<Match> {
        return producer()
    }
}

/** 保存重叠搜索进度，可逐次请求下一个匹配。 */
public class OverlappingState {
    private var matches: Option<MatchIterator> = None
    private var current: Option<Match> = None

    public init() {}

    public func reset(): Unit {
        matches = None
        current = None
    }

    public func advance(searcher: AhoCorasick, input: Input): Option<Match> {
        match (matches) {
            case Some(iterator) => current = iterator.next()
            case None =>
                let iterator = searcher.findOverlappingStateIter(input)
                matches = Some(iterator)
                current = iterator.next()
        }
        return current
    }

    public prop matched: Option<Match> {
        get() {
            current
        }
    }
}
