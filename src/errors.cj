package aho4cj

/** 搜索配置错误的稳定分类。 */
public enum MatchErrorKind {
    | InvalidInputAnchored
    | InvalidInputUnanchored
    | UnsupportedStream
    | UnsupportedOverlapping
    | UnsupportedEmpty
}

/** Aho-Corasick 搜索配置异常。 */
public open class MatchException <: Exception {
    public let kind: MatchErrorKind

    public init(kind: MatchErrorKind, message: String) {
        super(message)
        this.kind = kind
    }

    protected open override func getClassName(): String {
        return "MatchException"
    }
}
