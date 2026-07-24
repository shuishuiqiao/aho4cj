package aho4cj

/** 自动机状态编号。编号只对创建它的自动机有效。 */
public class StateID {
    public let value: Int64

    public init(value: Int64) {
        if (value < 0) {
            throw IllegalArgumentException("状态编号不能为负数")
        }
        this.value = value
    }

    public func toString(): String {
        return "StateID(${value})"
    }
}

/**
 * 可逐字节驱动的低层自动机视图。
 *
 * 状态编号属于当前视图。锚定转移只沿 Trie 直连边推进，缺边即进入 dead 状态；
 * 非锚定转移使用所选 NFA/DFA 后端的失败转移。
 */
public class AutomatonView {
    private let searcher: AhoCorasick

    init(searcher: AhoCorasick) {
        this.searcher = searcher
    }

    public func startState(mode: Anchored): StateID {
        return searcher.rawStartState(mode)
    }

    public func nextState(mode: Anchored, state: StateID, byte: Byte): StateID {
        return searcher.rawNextState(mode, state, byte)
    }

    public func isSpecial(state: StateID): Bool {
        return searcher.rawIsSpecial(state)
    }

    public func isDead(state: StateID): Bool {
        return searcher.rawIsDead(state)
    }

    public func isMatch(state: StateID): Bool {
        return searcher.rawIsMatch(state)
    }

    public func isStart(state: StateID): Bool {
        return searcher.rawIsStart(state)
    }

    public func matchCount(state: StateID): Int64 {
        return searcher.rawMatchCount(state)
    }

    public func matchPattern(state: StateID, index: Int64): Int64 {
        return searcher.rawMatchPattern(state, index)
    }

    public func patternLength(patternId: Int64): Int64 {
        return searcher.rawPatternLength(patternId)
    }

    public prop stateCount: Int64 {
        get() {
            searcher.rawStateCount
        }
    }

    public prop patternCount: Int64 {
        get() {
            searcher.patternCount
        }
    }

    public prop matchKind: MatchKind {
        get() {
            searcher.configuredMatchKind
        }
    }

    public prop minimumPatternLength: Int64 {
        get() {
            searcher.minPatternLength
        }
    }

    public prop maximumPatternLength: Int64 {
        get() {
            searcher.maxPatternLength
        }
    }

    public prop memoryUsage: Int64 {
        get() {
            searcher.memoryUsage
        }
    }

    public prop hasPrefilter: Bool {
        get() {
            searcher.hasPrefilter
        }
    }
}
