package aho4cj

import std.collection.ArrayList
import std.io.{InputStream, OutputStream}
import std.sort.sort

/** 匹配选择语义。 */
public enum MatchKind {
    | Standard
    | LeftmostFirst
    | LeftmostLongest
}

/** 一次匹配的模式编号及 UTF-8 字节区间。 */
public class Match {
    public let pattern: Int64
    public let start: Int64
    public let end: Int64

    public init(pattern: Int64, start: Int64, end: Int64) {
        this.pattern = pattern
        this.start = start
        this.end = end
    }

    public prop length: Int64 {
        get() {
            end - start
        }
    }

    public func toString(): String {
        return "Match(pattern=${pattern}, start=${start}, end=${end})"
    }
}

/** 字符串替换回调的结果，并可指示是否继续处理后续匹配。 */
public class StringReplacement {
    public let value: String
    public let shouldContinue: Bool

    public init(value: String, shouldContinue!: Bool = true) {
        this.value = value
        this.shouldContinue = shouldContinue
    }
}

/** 字节替换回调的结果，并可指示是否继续处理后续匹配。 */
public class ByteReplacement {
    public let value: Array<Byte>
    public let shouldContinue: Bool

    public init(value: Array<Byte>, shouldContinue!: Bool = true) {
        this.value = value
        this.shouldContinue = shouldContinue
    }
}

class Node {
    let transitions: Array<Int64> = Array<Int64>(256, repeat: -1)
    var failure: Int64 = 0
    let outputs: ArrayList<Int64> = ArrayList<Int64>()
    let depth: Int64

    init(depth: Int64) {
        this.depth = depth
    }
}

class StandardIteratorState {
    let haystack: Array<Byte>
    let end: Int64
    let anchored: Bool
    var state: Int64 = 0
    var cursor: Int64
    var index: Int64
    var done: Bool = false

    init(haystack: Array<Byte>, start: Int64, end: Int64, anchored: Bool) {
        this.haystack = haystack
        this.cursor = start
        this.index = start
        this.end = end
        this.anchored = anchored
    }
}

class StreamIteratorState {
    let input: InputStream
    let buffer: Array<Byte>
    var bufferIndex: Int64 = 0
    var bufferLength: Int64 = 0
    var absoluteEnd: Int64 = 0
    var automatonState: Int64 = 0
    var emptyStarted: Bool = false
    var done: Bool = false

    init(input: InputStream, bufferSize: Int64) {
        this.input = input
        this.buffer = Array<Byte>(bufferSize, repeat: 0)
    }

    func nextByte(): Option<Byte> {
        if (done) {
            return None
        }
        if (bufferIndex >= bufferLength) {
            bufferLength = input.read(buffer)
            bufferIndex = 0
            if (bufferLength <= 0) {
                done = true
                return None
            }
        }
        let byte = buffer[bufferIndex]
        bufferIndex++
        absoluteEnd++
        return Some(byte)
    }
}

class OverlappingIteratorState {
    let haystack: Array<Byte>
    let searchStart: Int64
    let end: Int64
    let anchored: Bool
    var index: Int64
    var automatonState: Int64 = 0
    var outputIndex: Int64 = 0
    var emptyIndex: Int64 = 0
    var phase: Int64 = 0
    var done: Bool = false

    init(haystack: Array<Byte>, start: Int64, end: Int64, anchored: Bool) {
        this.haystack = haystack
        this.searchStart = start
        this.index = start
        this.end = end
        this.anchored = anchored
    }
}

class LeftmostIteratorState {
    let haystack: Array<Byte>
    let end: Int64
    let anchored: Bool
    var cursor: Int64
    var suppressEmptyAtCursor: Bool = false
    var done: Bool = false

    init(haystack: Array<Byte>, start: Int64, end: Int64, anchored: Bool) {
        this.haystack = haystack
        this.cursor = start
        this.end = end
        this.anchored = anchored
    }
}

/** Aho-Corasick 自动机。构建后可重复用于多个输入。 */
public class AhoCorasick {
    private let nodes: ArrayList<Node>
    private let patterns: Array<Array<Byte>>
    private let emptyPatternIds: Array<Int64>
    private let matchKind: MatchKind
    private let asciiCaseInsensitive: Bool
    private let startKind: StartKind
    private let prefilterEnabled: Bool
    private let byteClassesEnabled: Bool
    private let denseDepth: Int64
    private var startBytes: Array<Byte> = []
    private var byteClassMap: Array<Int64> = []
    private var byteClassRepresentatives: Array<Int64> = []
    private var alphabetSize: Int64 = 256
    private var actualKind: AhoCorasickKind = AhoCorasickKind.ContiguousNFA
    private var noncontiguousTransitions: Array<Array<Int64>> = []
    private var dfaTransitions: Array<Int64> = []
    private var denseStateOffsets: Array<Int64> = []
    private var denseTransitions: Array<Int64> = []
    private var rootTransitions: Array<Int64> = []
    private var stateOffsets: Array<Int64> = []
    private var transitionSymbols: Array<Int64> = []
    private var transitionTargets: Array<Int64> = []
    private var directStateOffsets: Array<Int64> = []
    private var directTransitionSymbols: Array<Int64> = []
    private var directTransitionTargets: Array<Int64> = []
    private var failures: Array<Int64> = []
    private var stateOutputs: Array<Array<Int64>> = []
    private var stateDepths: Array<Int64> = []
    private var states: Int64 = 0

    public static func new(patterns: Array<String>): AhoCorasick {
        return AhoCorasickBuilder().build(patterns)
    }

    /** 使用字节模式和默认配置构建自动机。 */
    public static func newBytes(patterns: Array<Array<Byte>>): AhoCorasick {
        return AhoCorasickBuilder().buildBytes(patterns)
    }

    init(
        patterns: Array<Array<Byte>>,
        kind: MatchKind,
        caseInsensitive: Bool,
        startKind: StartKind,
        prefilterEnabled: Bool,
        byteClassesEnabled: Bool,
        denseDepth: Int64,
        requestedKind: Option<AhoCorasickKind>
    ) {
        this.matchKind = kind
        this.asciiCaseInsensitive = caseInsensitive
        this.startKind = startKind
        this.prefilterEnabled = prefilterEnabled
        this.byteClassesEnabled = byteClassesEnabled
        this.denseDepth = denseDepth
        this.nodes = ArrayList<Node>()
        this.nodes.add(Node(0))

        let encoded = ArrayList<Array<Byte>>()
        for (pattern in patterns) {
            if (caseInsensitive) {
                encoded.add(normalize(pattern, true))
            } else {
                encoded.add(sliceBytes(pattern, 0, pattern.size))
            }
        }
        this.patterns = encoded.toArray()
        let emptyIds = ArrayList<Int64>()
        for (patternId in 0..this.patterns.size) {
            if (this.patterns[patternId].size == 0) {
                emptyIds.add(patternId)
            }
        }
        this.emptyPatternIds = emptyIds.toArray()
        buildByteClasses()
        buildStartBytes()
        buildTrie()
        buildFailureLinks()
        actualKind = chooseKind(requestedKind)
        freezeAutomaton()
    }

    /** 返回第一个非重叠匹配。 */
    public func find(haystack: String): Option<Match> {
        return find(Input(haystack))
    }

    /** 在任意字节数组中返回第一个非重叠匹配。 */
    public func findBytes(haystack: Array<Byte>): Option<Match> {
        return find(Input(haystack))
    }

    /** 按 Input 配置返回第一个匹配。 */
    public func find(input: Input): Option<Match> {
        return findIter(input).next()
    }

    /** 输入范围内是否存在匹配。 */
    public func isMatch(haystack: String): Bool {
        return find(haystack).isSome()
    }

    public func isMatchBytes(haystack: Array<Byte>): Bool {
        return findBytes(haystack).isSome()
    }

    public func isMatch(input: Input): Bool {
        return find(input).isSome()
    }

    /** 返回采用当前 MatchKind 语义的全部非重叠匹配。 */
    public func findIter(haystack: String): MatchIterator {
        return findIter(Input(haystack))
    }

    public func findIterBytes(haystack: Array<Byte>): MatchIterator {
        return findIter(Input(haystack))
    }

    public func findIter(input: Input): MatchIterator {
        validateInput(input)
        if (isStandard(matchKind) || input.isEarliest) {
            return newStandardIterator(input)
        }
        let iteratorState = LeftmostIteratorState(
            normalize(input.haystack, asciiCaseInsensitive),
            input.start,
            input.end,
            isAnchored(input.anchor)
        )
        return MatchIterator({=> nextLeftmostMatch(iteratorState)})
    }

    /** 一次性返回全部非重叠匹配。 */
    public func findAll(haystack: String): Array<Match> {
        return findAll(Input(haystack))
    }

    public func findAllBytes(haystack: Array<Byte>): Array<Match> {
        return findAll(Input(haystack))
    }

    /** 按 Input 配置一次性返回全部非重叠匹配。 */
    public func findAll(input: Input): Array<Match> {
        let result = ArrayList<Match>()
        for (matched in findIter(input)) {
            result.add(matched)
        }
        return result.toArray()
    }

    /** 返回全部重叠匹配；仅支持 Standard 且非锚定的输入。 */
    public func findOverlappingIter(haystack: String): MatchIterator {
        return findOverlappingIter(Input(haystack))
    }

    /** 在任意字节数组中返回全部重叠匹配；配置冲突时抛出 MatchException。 */
    public func findOverlappingIterBytes(haystack: Array<Byte>): MatchIterator {
        return findOverlappingIter(Input(haystack))
    }

    public func findOverlappingIter(input: Input): MatchIterator {
        validateOverlappingInput(input, false)
        return newOverlappingIterator(input)
    }

    /** OverlappingState 使用的底层入口；与上游逐次驱动接口一样允许锚定输入。 */
    func findOverlappingStateIter(input: Input): MatchIterator {
        validateOverlappingInput(input, true)
        return newOverlappingIterator(input)
    }

    private func validateOverlappingInput(input: Input, allowAnchored: Bool): Unit {
        if (!isStandard(matchKind)) {
            throw MatchException(
                MatchErrorKind.UnsupportedOverlapping,
                "重叠搜索仅支持 Standard 匹配语义"
            )
        }
        validateInput(input)
        if (!allowAnchored && isAnchored(input.anchor)) {
            throw MatchException(
                MatchErrorKind.InvalidInputAnchored,
                "重叠迭代器不支持锚定输入；请改用 OverlappingState 逐次驱动"
            )
        }
    }

    private func newOverlappingIterator(input: Input): MatchIterator {
        if (input.isDone) {
            return MatchIterator({=> None})
        }
        let iteratorState = OverlappingIteratorState(
            normalize(input.haystack, asciiCaseInsensitive),
            input.start,
            input.end,
            isAnchored(input.anchor)
        )
        return MatchIterator({=> nextOverlappingMatch(iteratorState)})
    }

    /** 使用 OverlappingState 返回下一个重叠匹配。 */
    public func findOverlapping(input: Input, state: OverlappingState): Option<Match> {
        return state.advance(this, input)
    }

    public func findOverlapping(haystack: String, state: OverlappingState): Option<Match> {
        return findOverlapping(Input(haystack), state)
    }

    public func findOverlappingBytes(
        haystack: Array<Byte>,
        state: OverlappingState
    ): Option<Match> {
        return findOverlapping(Input(haystack), state)
    }

    public func findOverlappingAll(haystack: String): Array<Match> {
        return findOverlappingAll(Input(haystack))
    }

    public func findOverlappingAllBytes(haystack: Array<Byte>): Array<Match> {
        return findOverlappingAll(Input(haystack))
    }

    /** 按 Input 配置一次性返回全部重叠匹配。 */
    public func findOverlappingAll(input: Input): Array<Match> {
        validateOverlappingInput(input, false)
        if (input.isDone) {
            return []
        }
        let bytes = normalize(input.haystack, asciiCaseInsensitive)
        let result = ArrayList<Match>()
        addEmptyMatchesToResult(result, input.start)
        var state: Int64 = 0
        for (index in input.start..input.end) {
            state = nextState(state, Int64(bytes[index]))
            for (patternId in stateOutputs[state]) {
                let length = patterns[patternId].size
                let start = index + 1 - length
                if (length > 0 && (!isAnchored(input.anchor) || start == input.start)) {
                    result.add(Match(patternId, start, index + 1))
                }
            }
            if (!isAnchored(input.anchor)) {
                addEmptyMatchesToResult(result, index + 1)
            }
            if (isAnchored(input.anchor) && state == 0) {
                break
            }
        }
        return result.toArray()
    }

    /** 使用默认 8 KiB 缓冲区流式查找 Standard 非重叠匹配。 */
    public func streamFindIter(input: InputStream): StreamMatchIterator {
        return streamFindIter(input, 8192)
    }

    /** 使用指定缓冲区大小流式查找 Standard 非重叠匹配。 */
    public func streamFindIter(input: InputStream, bufferSize: Int64): StreamMatchIterator {
        validateStreamConfiguration(bufferSize)
        let iteratorState = StreamIteratorState(input, bufferSize)
        return StreamMatchIterator({=> nextStreamMatch(iteratorState)})
    }

    /** 使用默认 8 KiB 缓冲区执行流式字节替换。 */
    public func streamReplaceAll(
        input: InputStream,
        output: OutputStream,
        replacements: Array<Array<Byte>>
    ): Unit {
        streamReplaceAll(input, output, replacements, 8192)
    }

    /** 使用指定缓冲区大小执行流式字节替换。 */
    public func streamReplaceAll(
        input: InputStream,
        output: OutputStream,
        replacements: Array<Array<Byte>>,
        bufferSize: Int64
    ): Unit {
        if (replacements.size != patterns.size) {
            throw IllegalArgumentException("替换内容数量必须与模式数量一致")
        }
        streamReplaceAllWithBytes(
            input,
            output,
            {matched, _ => replacements[matched.pattern]},
            bufferSize
        )
    }

    public func streamReplaceAllWithBytes(
        input: InputStream,
        output: OutputStream,
        replacer: (Match, Array<Byte>) -> Array<Byte>
    ): Unit {
        streamReplaceAllWithBytes(input, output, replacer, 8192)
    }

    /** 通过回调执行固定内存流式字节替换。 */
    public func streamReplaceAllWithBytes(
        input: InputStream,
        output: OutputStream,
        replacer: (Match, Array<Byte>) -> Array<Byte>,
        bufferSize: Int64
    ): Unit {
        streamReplaceAllWithBytesControlled(
            input,
            output,
            {matched, value => ByteReplacement(replacer(matched, value))},
            bufferSize
        )
    }

    public func streamReplaceAllWithBytesControlled(
        input: InputStream,
        output: OutputStream,
        replacer: (Match, Array<Byte>) -> ByteReplacement
    ): Unit {
        streamReplaceAllWithBytesControlled(input, output, replacer, 8192)
    }

    /** 通过回调流式替换，并允许回调在写入当前替换后停止。 */
    public func streamReplaceAllWithBytesControlled(
        input: InputStream,
        output: OutputStream,
        replacer: (Match, Array<Byte>) -> ByteReplacement,
        bufferSize: Int64
    ): Unit {
        validateStreamConfiguration(bufferSize)
        let buffer = Array<Byte>(bufferSize, repeat: 0)
        let ready = ArrayList<Byte>()

        let pending = ArrayList<Byte>()
        var state: Int64 = 0
        var absoluteEnd: Int64 = 0
        while (true) {
            let count = input.read(buffer)
            if (count <= 0) {
                break
            }
            for (index in 0..count) {
                let originalByte = buffer[index]
                pending.add(originalByte)
                absoluteEnd++
                state = nextState(state, Int64(normalizeByte(originalByte, asciiCaseInsensitive)))

                var selectedPattern: Int64 = -1
                var selectedStart: Int64 = 0
                for (patternId in stateOutputs[state]) {
                    let matchStart = absoluteEnd - patterns[patternId].size
                    if (selectedPattern < 0 || matchStart < selectedStart || (matchStart == selectedStart && patternId <
                        selectedPattern)) {
                        selectedPattern = patternId
                        selectedStart = matchStart
                    }
                }

                if (selectedPattern >= 0) {
                    let matched = Match(selectedPattern, selectedStart, absoluteEnd)
                    let matchedLength = patterns[selectedPattern].size
                    let prefixLength = pending.size - matchedLength
                    appendListBytes(ready, pending, 0, prefixLength)
                    let matchedBytes = sliceListBytes(pending, prefixLength, pending.size)
                    let replacement = replacer(matched, matchedBytes)
                    appendBytes(ready, replacement.value, 0, replacement.value.size)
                    pending.clear()
                    state = 0
                    if (!replacement.shouldContinue) {
                        appendBytes(ready, buffer, index + 1, count)
                        flushReady(output, ready)
                        copyStreamRemainder(input, output, buffer)
                        return
                    }
                } else {
                    let safeLength = pending.size - stateDepths[state]
                    if (safeLength > 0) {
                        appendListBytes(ready, pending, 0, safeLength)
                        retainListTail(pending, safeLength)
                    }
                }
                flushReadyIfNeeded(output, ready, bufferSize)
            }
        }
        appendListBytes(ready, pending, 0, pending.size)
        flushReady(output, ready)
    }

    private func copyStreamRemainder(
        input: InputStream,
        output: OutputStream,
        buffer: Array<Byte>
    ): Unit {
        while (true) {
            let count = input.read(buffer)
            if (count <= 0) {
                return
            }
            output.write(sliceBytes(buffer, 0, count))
        }
    }

    /** 按模式编号替换非重叠匹配；数量不一致时抛出 IllegalArgumentException。 */
    public func replaceAll(haystack: String, replacements: Array<String>): String {
        if (replacements.size != patterns.size) {
            throw IllegalArgumentException("替换字符串数量必须与模式数量一致")
        }
        return replaceAllWithControlled(haystack, {
            matched, _ => StringReplacement(replacements[matched.pattern])
        })
    }

    /** 替换字节输入中的非重叠匹配；数量不一致时抛出 IllegalArgumentException。 */
    public func replaceAllBytes(haystack: Array<Byte>, replacements: Array<Array<Byte>>): Array<Byte> {
        if (replacements.size != patterns.size) {
            throw IllegalArgumentException("替换字符串数量必须与模式数量一致")
        }
        let matches = findAllBytes(haystack)
        let output = ArrayList<Byte>()
        var cursor: Int64 = 0
        for (m in matches) {
            appendBytes(output, haystack, cursor, m.start)
            let replacement = replacements[m.pattern]
            appendBytes(output, replacement, 0, replacement.size)
            cursor = m.end
        }
        appendBytes(output, haystack, cursor, haystack.size)
        return output.toArray()
    }

    /** 通过回调为每个非重叠匹配生成字符串替换内容。 */
    public func replaceAllWith(haystack: String, replacer: (Match, String) -> String): String {
        return replaceAllWithControlled(haystack, {
            matched, value => StringReplacement(replacer(matched, value))
        })
    }

    /** 通过回调替换字符串，并允许回调在写入当前替换后停止。 */
    public func replaceAllWithControlled(
        haystack: String,
        replacer: (Match, String) -> StringReplacement
    ): String {
        let bytes = haystack.toArray()
        let matches = findAllBytes(bytes)
        let output = ArrayList<Byte>()
        var cursor: Int64 = 0
        for (matched in matches) {
            if (!isUtf8Boundary(bytes, matched.start) || !isUtf8Boundary(bytes, matched.end)) {
                continue
            }
            appendBytes(output, bytes, cursor, matched.start)
            let matchedString = String.fromUtf8(sliceBytes(bytes, matched.start, matched.end))
            let replacement = replacer(matched, matchedString)
            let replacementBytes = replacement.value.toArray()
            appendBytes(output, replacementBytes, 0, replacementBytes.size)
            cursor = matched.end
            if (!replacement.shouldContinue) {
                break
            }
        }
        appendBytes(output, bytes, cursor, bytes.size)
        return String.fromUtf8(output.toArray())
    }

    /** 通过回调为每个非重叠匹配生成任意字节替换内容。 */
    public func replaceAllWithBytes(
        haystack: Array<Byte>,
        replacer: (Match, Array<Byte>) -> Array<Byte>
    ): Array<Byte> {
        return replaceAllWithBytesControlled(haystack, {
            matched, value => ByteReplacement(replacer(matched, value))
        })
    }

    /** 通过回调替换字节，并允许回调在写入当前替换后停止。 */
    public func replaceAllWithBytesControlled(
        haystack: Array<Byte>,
        replacer: (Match, Array<Byte>) -> ByteReplacement
    ): Array<Byte> {
        let matches = findAllBytes(haystack)
        let output = ArrayList<Byte>()
        var cursor: Int64 = 0
        for (matched in matches) {
            appendBytes(output, haystack, cursor, matched.start)
            let matchedBytes = sliceBytes(haystack, matched.start, matched.end)
            let replacement = replacer(matched, matchedBytes)
            appendBytes(output, replacement.value, 0, replacement.value.size)
            cursor = matched.end
            if (!replacement.shouldContinue) {
                break
            }
        }
        appendBytes(output, haystack, cursor, haystack.size)
        return output.toArray()
    }

    /** 自动机节点数，可用于粗略观察内存规模。 */
    public prop stateCount: Int64 {
        get() {
            states
        }
    }

    /** 模式数量。 */
    public prop patternCount: Int64 {
        get() {
            patterns.size
        }
    }

    public prop minPatternLength: Int64 {
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

    public prop maxPatternLength: Int64 {
        get() {
            var maximum: Int64 = 0
            for (pattern in patterns) {
                if (pattern.size > maximum) {
                    maximum = pattern.size
                }
            }
            return maximum
        }
    }

    public prop configuredMatchKind: MatchKind {
        get() {
            matchKind
        }
    }

    public prop configuredStartKind: StartKind {
        get() {
            startKind
        }
    }

    /** 实际采用的自动机类型。 */
    public prop kind: AhoCorasickKind {
        get() {
            actualKind
        }
    }

    /** 自动机主要数组占用的近似字节数，不包含对象头。 */
    public prop memoryUsage: Int64 {
        get() {
            var bytes: Int64 = rootTransitions.size * 8 + stateOffsets.size * 8 + transitionSymbols.size * 8 +
                transitionTargets.size * 8 + failures.size * 8 + dfaTransitions.size * 8 + byteClassMap.size * 8 +
                byteClassRepresentatives.size * 8 + denseStateOffsets.size * 8 + denseTransitions.size * 8 +
                directStateOffsets.size * 8 + directTransitionSymbols.size * 8 + directTransitionTargets.size * 8
            for (transitions in noncontiguousTransitions) {
                bytes = bytes + transitions.size * 8
            }
            for (output in stateOutputs) {
                bytes = bytes + output.size * 8
            }
            for (pattern in patterns) {
                bytes = bytes + pattern.size
            }
            return bytes
        }
    }

    /** 返回可逐状态驱动的低层自动机视图。 */
    public func lowLevel(): AutomatonView {
        return AutomatonView(this)
    }

    func rawStartState(mode: Anchored): StateID {
        validateAnchorMode(mode)
        return StateID(0)
    }

    func rawNextState(mode: Anchored, state: StateID, byte: Byte): StateID {
        validateAnchorMode(mode)
        validateRawState(state)
        if (state.value == states) {
            return state
        }
        let symbol = Int64(normalizeByte(byte, asciiCaseInsensitive))
        if (isAnchored(mode)) {
            let target = directTransition(state.value, byteClassMap[symbol])
            return StateID(if (target >= 0) {
                target
            } else {
                states
            })
        }
        return StateID(nextState(state.value, symbol))
    }

    func rawIsDead(state: StateID): Bool {
        validateRawState(state)
        return state.value == states
    }

    func rawIsStart(state: StateID): Bool {
        validateRawState(state)
        return state.value == 0
    }

    func rawIsMatch(state: StateID): Bool {
        validateRawState(state)
        return state.value < states && stateOutputs[state.value].size > 0
    }

    func rawIsSpecial(state: StateID): Bool {
        return rawIsDead(state) || rawIsStart(state) || rawIsMatch(state)
    }

    func rawMatchCount(state: StateID): Int64 {
        validateRawState(state)
        return if (state.value < states) {
            stateOutputs[state.value].size
        } else {
            0
        }
    }

    func rawMatchPattern(state: StateID, index: Int64): Int64 {
        validateRawState(state)
        if (state.value >= states || index < 0 || index >= stateOutputs[state.value].size) {
            throw IllegalArgumentException("状态 ${state.value} 不包含编号为 ${index} 的匹配")
        }
        return stateOutputs[state.value][index]
    }

    func rawPatternLength(patternId: Int64): Int64 {
        if (patternId < 0 || patternId >= patterns.size) {
            throw IllegalArgumentException("无效模式编号 ${patternId}")
        }
        return patterns[patternId].size
    }

    prop rawStateCount: Int64 {
        get() {
            states + 1
        }
    }

    prop hasPrefilter: Bool {
        get() {
            startBytes.size > 0
        }
    }

    private func buildTrie(): Unit {
        for (patternId in 0..patterns.size) {
            var state: Int64 = 0
            let pattern = patterns[patternId]
            for (byte in pattern) {
                let symbol = Int64(byte)
                var next = nodes[state].transitions[symbol]
                if (next < 0) {
                    next = nodes.size
                    nodes.add(Node(nodes[state].depth + 1))
                    nodes[state].transitions[symbol] = next
                }
                state = next
            }
            nodes[state].outputs.add(patternId)
        }
    }

    private func buildFailureLinks(): Unit {
        let queue = ArrayList<Int64>()
        for (symbol in 0..256) {
            let child = nodes[0].transitions[symbol]
            if (child >= 0) {
                nodes[child].failure = 0
                queue.add(child)
            }
        }

        var head: Int64 = 0
        while (head < queue.size) {
            let state = queue[head]
            head++
            for (symbol in 0..256) {
                let child = nodes[state].transitions[symbol]
                if (child < 0) {
                    continue
                }
                queue.add(child)
                var failure = nodes[state].failure
                while (failure != 0 && nodes[failure].transitions[symbol] < 0) {
                    failure = nodes[failure].failure
                }
                let fallback = nodes[failure].transitions[symbol]
                if (fallback >= 0 && fallback != child) {
                    failure = fallback
                }
                nodes[child].failure = failure
                for (patternId in nodes[failure].outputs) {
                    nodes[child].outputs.add(patternId)
                }
            }
        }
        for (state in 0..nodes.size) {
            sortOutputIds(nodes[state].outputs)
        }
    }

    private func nextState(initialState: Int64, symbol: Int64): Int64 {
        match (actualKind) {
            case AhoCorasickKind.DFA =>
                let classIndex = byteClassMap[symbol]
                return dfaTransitions[initialState * alphabetSize + classIndex]
            case AhoCorasickKind.NoncontiguousNFA =>
                var state = initialState
                while (state != 0 && noncontiguousTransitions[state][symbol] < 0) {
                    state = failures[state]
                }
                let target = noncontiguousTransitions[state][symbol]
                return if (target >= 0) {
                    target
                } else {
                    state
                }
            case AhoCorasickKind.ContiguousNFA => ()
        }
        var state = initialState
        let symbolClass = byteClassMap[symbol]
        while (state != 0) {
            let denseOffset = denseStateOffsets[state]
            if (denseOffset >= 0) {
                let target = denseTransitions[denseOffset + symbolClass]
                if (target >= 0) {
                    return target
                }
                state = failures[state]
                continue
            }
            let start = stateOffsets[state]
            let end = stateOffsets[state + 1]
            for (edgeIndex in start..end) {
                if (transitionSymbols[edgeIndex] == symbolClass) {
                    return transitionTargets[edgeIndex]
                }
            }
            state = failures[state]
        }
        return rootTransitions[symbolClass]
    }

    private func newStandardIterator(input: Input): MatchIterator {
        let haystack = normalize(input.haystack, asciiCaseInsensitive)
        let iteratorState = StandardIteratorState(
            haystack,
            input.start,
            input.end,
            isAnchored(input.anchor)
        )
        return MatchIterator({=> nextStandardMatch(iteratorState)})
    }

    private func nextStandardMatch(iterator: StandardIteratorState): Option<Match> {
        if (iterator.done) {
            return None
        }
        if (emptyPatternIds.size > 0) {
            if (iterator.cursor <= iterator.end) {
                let matched = Match(emptyPatternIds[0], iterator.cursor, iterator.cursor)
                iterator.cursor++
                return Some(matched)
            }
            iterator.done = true
            return None
        }

        if (iterator.anchored) {
            iterator.state = 0
            iterator.index = iterator.cursor
            while (iterator.index < iterator.end) {
                iterator.state = nextState(
                    iterator.state,
                    Int64(iterator.haystack[iterator.index])
                )
                for (patternId in stateOutputs[iterator.state]) {
                    let matchStart = iterator.index + 1 - patterns[patternId].size
                    if (matchStart == iterator.cursor) {
                        let matched = Match(patternId, matchStart, iterator.index + 1)
                        iterator.cursor = matched.end
                        return Some(matched)
                    }
                }
                if (iterator.state == 0) {
                    iterator.done = true
                    return None
                }
                iterator.index++
            }
            iterator.done = true
            return None
        }

        while (iterator.index < iterator.end) {
            if (iterator.state == 0) {
                iterator.index = findNextStart(iterator.haystack, iterator.index, iterator.end)
                if (iterator.index >= iterator.end) {
                    iterator.done = true
                    return None
                }
            }
            iterator.state = nextState(
                iterator.state,
                Int64(iterator.haystack[iterator.index])
            )
            var selectedPattern: Int64 = -1
            var selectedStart: Int64 = 0
            for (patternId in stateOutputs[iterator.state]) {
                let matchStart = iterator.index + 1 - patterns[patternId].size
                if (matchStart < iterator.cursor) {
                    continue
                }
                if (selectedPattern < 0 || matchStart < selectedStart || (matchStart == selectedStart && patternId <
                    selectedPattern)) {
                    selectedPattern = patternId
                    selectedStart = matchStart
                }
            }
            iterator.index++
            if (selectedPattern >= 0) {
                let matched = Match(selectedPattern, selectedStart, iterator.index)
                iterator.cursor = matched.end
                iterator.state = 0
                return Some(matched)
            }
        }
        iterator.done = true
        return None
    }

    private func nextStreamMatch(iterator: StreamIteratorState): Option<Match> {
        if (emptyPatternIds.size > 0) {
            if (!iterator.emptyStarted) {
                iterator.emptyStarted = true
                return Some(Match(emptyPatternIds[0], 0, 0))
            }
            match (iterator.nextByte()) {
                case Some(_) => return Some(
                    Match(
                        emptyPatternIds[0],
                        iterator.absoluteEnd,
                        iterator.absoluteEnd
                    )
                )
                case None => return None
            }
        }

        while (let Some(originalByte) <- iterator.nextByte()) {
            let byte = normalizeByte(originalByte, asciiCaseInsensitive)
            iterator.automatonState = nextState(iterator.automatonState, Int64(byte))
            var selectedPattern: Int64 = -1
            var selectedStart: Int64 = 0
            for (patternId in stateOutputs[iterator.automatonState]) {
                let matchStart = iterator.absoluteEnd - patterns[patternId].size
                if (selectedPattern < 0 || matchStart < selectedStart || (matchStart == selectedStart && patternId <
                    selectedPattern)) {
                    selectedPattern = patternId
                    selectedStart = matchStart
                }
            }
            if (selectedPattern >= 0) {
                let matched = Match(selectedPattern, selectedStart, iterator.absoluteEnd)
                iterator.automatonState = 0
                return Some(matched)
            }
        }
        return None
    }

    private func nextOverlappingMatch(iterator: OverlappingIteratorState): Option<Match> {
        while (!iterator.done) {
            if (iterator.phase == 0) {
                if (iterator.emptyIndex < emptyPatternIds.size) {
                    let patternId = emptyPatternIds[iterator.emptyIndex]
                    iterator.emptyIndex++
                    return Some(Match(patternId, iterator.searchStart, iterator.searchStart))
                }
                iterator.emptyIndex = 0
                iterator.phase = 1
            }

            if (iterator.phase == 1) {
                if (iterator.index >= iterator.end) {
                    iterator.done = true
                    return None
                }
                iterator.automatonState = nextState(
                    iterator.automatonState,
                    Int64(iterator.haystack[iterator.index])
                )
                iterator.index++
                iterator.outputIndex = 0
                iterator.phase = 2
            }

            if (iterator.phase == 2) {
                let outputs = stateOutputs[iterator.automatonState]
                while (iterator.outputIndex < outputs.size) {
                    let patternId = outputs[iterator.outputIndex]
                    iterator.outputIndex++
                    let length = patterns[patternId].size
                    if (length == 0) {
                        continue
                    }
                    let matchStart = iterator.index - length
                    if (!iterator.anchored || matchStart == iterator.searchStart) {
                        return Some(Match(patternId, matchStart, iterator.index))
                    }
                }
                iterator.phase = 3
            }

            if (iterator.phase == 3) {
                if (!iterator.anchored && iterator.emptyIndex < emptyPatternIds.size) {
                    let patternId = emptyPatternIds[iterator.emptyIndex]
                    iterator.emptyIndex++
                    return Some(Match(patternId, iterator.index, iterator.index))
                }
                iterator.emptyIndex = 0
                iterator.phase = 1
                if (iterator.anchored && iterator.automatonState == 0) {
                    iterator.done = true
                }
            }
        }
        return None
    }

    private func nextLeftmostMatch(iterator: LeftmostIteratorState): Option<Match> {
        if (iterator.done || iterator.cursor > iterator.end) {
            return None
        }

        var bestPattern: Int64 = -1
        var bestStart = iterator.cursor
        var bestEnd = iterator.cursor
        if (emptyPatternIds.size > 0) {
            if (!iterator.suppressEmptyAtCursor) {
                bestPattern = emptyPatternIds[0]
            } else if (!iterator.anchored && iterator.cursor < iterator.end) {
                bestPattern = emptyPatternIds[0]
                bestStart = iterator.cursor + 1
                bestEnd = bestStart
            }
        }

        var state: Int64 = 0
        var index = iterator.cursor
        while (index < iterator.end) {
            state = nextState(state, Int64(iterator.haystack[index]))
            let matchEnd = index + 1
            for (patternId in stateOutputs[state]) {
                let length = patterns[patternId].size
                if (length == 0) {
                    continue
                }
                let matchStart = matchEnd - length
                if (matchStart < iterator.cursor || (iterator.anchored && matchStart != iterator.cursor)) {
                    continue
                }
                if (isBetterLeftmostCandidate(
                    patternId,
                    matchStart,
                    matchEnd,
                    bestPattern,
                    bestStart,
                    bestEnd
                )) {
                    bestPattern = patternId
                    bestStart = matchStart
                    bestEnd = matchEnd
                }
            }
            index++
            if (bestPattern >= 0 && index >= bestStart + maxPatternLength) {
                break
            }
            if (iterator.anchored && state == 0) {
                break
            }
        }

        if (bestPattern < 0) {
            iterator.done = true
            return None
        }
        let matched = Match(bestPattern, bestStart, bestEnd)
        if (matched.start == matched.end) {
            iterator.suppressEmptyAtCursor = false
            if (matched.end >= iterator.end) {
                iterator.done = true
            } else {
                iterator.cursor = matched.end + 1
            }
        } else {
            iterator.cursor = matched.end
            iterator.suppressEmptyAtCursor = true
        }
        return Some(matched)
    }

    private func isBetterLeftmostCandidate(
        patternId: Int64,
        start: Int64,
        end: Int64,
        bestPattern: Int64,
        bestStart: Int64,
        bestEnd: Int64
    ): Bool {
        if (bestPattern < 0 || start < bestStart) {
            return true
        }
        if (start > bestStart) {
            return false
        }
        if (isLeftmostLongest(matchKind)) {
            let length = end - start
            let bestLength = bestEnd - bestStart
            return length > bestLength || (length == bestLength && patternId < bestPattern)
        }
        return patternId < bestPattern
    }

    private func addEmptyMatchesToResult(result: ArrayList<Match>, position: Int64): Unit {
        for (patternId in emptyPatternIds) {
            result.add(Match(patternId, position, position))
        }
    }

    private func sortOutputIds(items: ArrayList<Int64>): Unit {
        sort(items, lessThan: {
            a, b => if (patterns[a].size != patterns[b].size) {
                patterns[a].size > patterns[b].size
            } else {
                a < b
            }
        }, stable: true)
    }

    private func freezeAutomaton(): Unit {
        states = nodes.size
        failures = Array<Int64>(states, {state => nodes[state].failure})
        stateOutputs = Array<Array<Int64>>(states, {state => nodes[state].outputs.toArray()})
        stateDepths = Array<Int64>(states, {state => nodes[state].depth})
        freezeDirectTransitions()
        match (actualKind) {
            case AhoCorasickKind.NoncontiguousNFA => noncontiguousTransitions = Array<Array<Int64>>(
                states,
                {state => nodes[state].transitions}
            )
            case AhoCorasickKind.DFA => dfaTransitions = Array<Int64>(
                states * alphabetSize,
                {
                    offset =>
                        let state = offset / alphabetSize
                        let classIndex = offset % alphabetSize
                        let symbol = byteClassRepresentatives[classIndex]
                        resolveTransition(state, symbol)
                }
            )
            case AhoCorasickKind.ContiguousNFA => freezeContiguousNfa()
        }
        nodes.clear()
    }

    private func freezeDirectTransitions(): Unit {
        let offsets = ArrayList<Int64>()
        let symbols = ArrayList<Int64>()
        let targets = ArrayList<Int64>()
        for (state in 0..states) {
            offsets.add(targets.size)
            for (symbol in 0..256) {
                let target = nodes[state].transitions[symbol]
                if (target >= 0) {
                    symbols.add(byteClassMap[symbol])
                    targets.add(target)
                }
            }
        }
        offsets.add(targets.size)
        directStateOffsets = offsets.toArray()
        directTransitionSymbols = symbols.toArray()
        directTransitionTargets = targets.toArray()
    }

    private func directTransition(state: Int64, symbolClass: Int64): Int64 {
        for (edgeIndex in directStateOffsets[state]..directStateOffsets[state + 1]) {
            if (directTransitionSymbols[edgeIndex] == symbolClass) {
                return directTransitionTargets[edgeIndex]
            }
        }
        return -1
    }

    private func validateAnchorMode(mode: Anchored): Unit {
        if (isAnchored(mode) && isStartUnanchored(startKind)) {
            throw MatchException(MatchErrorKind.InvalidInputAnchored, "自动机未启用锚定搜索")
        }
        if (!isAnchored(mode) && isStartAnchored(startKind)) {
            throw MatchException(MatchErrorKind.InvalidInputUnanchored, "自动机未启用非锚定搜索")
        }
    }

    private func validateRawState(state: StateID): Unit {
        if (state.value < 0 || state.value > states) {
            throw IllegalArgumentException("无效自动机状态 ${state.value}")
        }
    }

    private func freezeContiguousNfa(): Unit {
        rootTransitions = Array<Int64>(alphabetSize, {
            classIndex => resolveTransition(0, byteClassRepresentatives[classIndex])
        })
        let offsets = ArrayList<Int64>()
        let symbols = ArrayList<Int64>()
        let targets = ArrayList<Int64>()
        let denseOffsets = Array<Int64>(states, repeat: -1)
        let denseTargets = ArrayList<Int64>()
        for (state in 0..states) {
            offsets.add(targets.size)
            if (state != 0) {
                if (stateDepths[state] < denseDepth) {
                    denseOffsets[state] = denseTargets.size
                    for (classIndex in 0..alphabetSize) {
                        let symbol = byteClassRepresentatives[classIndex]
                        denseTargets.add(nodes[state].transitions[symbol])
                    }
                    continue
                }
                for (symbol in 0..256) {
                    let target = nodes[state].transitions[symbol]
                    if (target >= 0) {
                        symbols.add(byteClassMap[symbol])
                        targets.add(target)
                    }
                }
            }
        }
        offsets.add(targets.size)
        stateOffsets = offsets.toArray()
        transitionSymbols = symbols.toArray()
        transitionTargets = targets.toArray()
        denseStateOffsets = denseOffsets
        denseTransitions = denseTargets.toArray()
    }

    private func resolveTransition(initialState: Int64, symbol: Int64): Int64 {
        var state = initialState
        while (state != 0 && nodes[state].transitions[symbol] < 0) {
            state = nodes[state].failure
        }
        let target = nodes[state].transitions[symbol]
        return if (target >= 0) {
            target
        } else {
            0
        }
    }

    private func chooseKind(requested: Option<AhoCorasickKind>): AhoCorasickKind {
        match (requested) {
            case Some(kind) => return kind
            case None =>
                if (patterns.size <= 100 && !isStartBoth(startKind)) {
                    return AhoCorasickKind.DFA
                }
                return AhoCorasickKind.ContiguousNFA
        }
    }

    private func validateStreamConfiguration(bufferSize: Int64): Unit {
        if (!isStandard(matchKind)) {
            throw MatchException(MatchErrorKind.UnsupportedStream, "流式操作仅支持 Standard 匹配语义")
        }
        if (isStartAnchored(startKind)) {
            throw MatchException(
                MatchErrorKind.InvalidInputUnanchored,
                "流式操作需要自动机支持非锚定搜索"
            )
        }
        if (bufferSize <= 0) {
            throw IllegalArgumentException("流式缓冲区大小必须大于 0")
        }
        if (emptyPatternIds.size > 0) {
            throw MatchException(MatchErrorKind.UnsupportedEmpty, "流式操作不支持空模式")
        }
    }

    private func buildStartBytes(): Unit {
        if (!prefilterEnabled || emptyPatternIds.size > 0) {
            return
        }
        let bytes = ArrayList<Byte>()
        for (pattern in patterns) {
            if (pattern.size == 0) {
                continue
            }
            let first = pattern[0]
            var exists = false
            for (known in bytes) {
                if (known == first) {
                    exists = true
                    break
                }
            }
            if (!exists) {
                bytes.add(first)
                if (bytes.size > 3) {
                    return
                }
            }
        }
        startBytes = bytes.toArray()
    }

    private func buildByteClasses(): Unit {
        if (!byteClassesEnabled) {
            byteClassMap = Array<Int64>(256, {symbol => symbol})
            byteClassRepresentatives = Array<Int64>(256, {symbol => symbol})
            alphabetSize = 256
            return
        }

        let used = Array<Bool>(256, repeat: false)
        for (pattern in patterns) {
            for (byte in pattern) {
                used[Int64(byte)] = true
            }
        }
        var unusedRepresentative: Int64 = -1
        for (symbol in 0..256) {
            if (!used[symbol]) {
                unusedRepresentative = symbol
                break
            }
        }

        byteClassMap = Array<Int64>(256, repeat: 0)
        let representatives = ArrayList<Int64>()
        if (unusedRepresentative >= 0) {
            representatives.add(unusedRepresentative)
        }
        for (symbol in 0..256) {
            if (used[symbol]) {
                byteClassMap[symbol] = representatives.size
                representatives.add(symbol)
            }
        }
        byteClassRepresentatives = representatives.toArray()
        alphabetSize = byteClassRepresentatives.size
    }

    private func findNextStart(haystack: Array<Byte>, start: Int64, end: Int64): Int64 {
        if (startBytes.size == 0) {
            return start
        }
        var index = start
        if (startBytes.size == 1) {
            let needle = startBytes[0]
            while (index + 8 <= end) {
                if (haystack[index] == needle) {
                    return index
                }
                if (haystack[index + 1] == needle) {
                    return index + 1
                }
                if (haystack[index + 2] == needle) {
                    return index + 2
                }
                if (haystack[index + 3] == needle) {
                    return index + 3
                }
                if (haystack[index + 4] == needle) {
                    return index + 4
                }
                if (haystack[index + 5] == needle) {
                    return index + 5
                }
                if (haystack[index + 6] == needle) {
                    return index + 6
                }
                if (haystack[index + 7] == needle) {
                    return index + 7
                }
                index += 8
            }
            while (index < end) {
                if (haystack[index] == needle) {
                    return index
                }
                index++
            }
            return end
        }
        if (startBytes.size == 2) {
            let first = startBytes[0]
            let second = startBytes[1]
            while (index < end) {
                let byte = haystack[index]
                if (byte == first || byte == second) {
                    return index
                }
                index++
            }
            return end
        }
        let first = startBytes[0]
        let second = startBytes[1]
        let third = startBytes[2]
        while (index < end) {
            let byte = haystack[index]
            if (byte == first || byte == second || byte == third) {
                return index
            }
            index++
        }
        return end
    }

    private func validateInput(input: Input): Unit {
        validateAnchorMode(input.anchor)
    }
}

/** AhoCorasick 的链式配置构建器。 */
public class AhoCorasickBuilder {
    private var matchKindConfig: MatchKind = MatchKind.Standard
    private var caseInsensitive: Bool = false
    private var starts: StartKind = StartKind.Unanchored
    private var usePrefilter: Bool = true
    private var requestedKind: Option<AhoCorasickKind> = None
    private var useByteClasses: Bool = true
    private var configuredDenseDepth: Int64 = 2

    public init() {}

    public func matchKind(kind: MatchKind): AhoCorasickBuilder {
        this.matchKindConfig = kind
        return this
    }

    public func asciiCaseInsensitive(enabled: Bool): AhoCorasickBuilder {
        this.caseInsensitive = enabled
        return this
    }

    public func startKind(kind: StartKind): AhoCorasickBuilder {
        this.starts = kind
        return this
    }

    public func prefilter(enabled: Bool): AhoCorasickBuilder {
        this.usePrefilter = enabled
        return this
    }

    public func kind(kind: AhoCorasickKind): AhoCorasickBuilder {
        this.requestedKind = Some(kind)
        return this
    }

    public func automaticKind(): AhoCorasickBuilder {
        this.requestedKind = None
        return this
    }

    public func byteClasses(enabled: Bool): AhoCorasickBuilder {
        this.useByteClasses = enabled
        return this
    }

    public func denseDepth(depth: Int64): AhoCorasickBuilder {
        if (depth < 0) {
            throw IllegalArgumentException("稠密状态深度不能为负数")
        }
        this.configuredDenseDepth = depth
        return this
    }

    public func build(patterns: Array<String>): AhoCorasick {
        let encoded = ArrayList<Array<Byte>>()
        for (pattern in patterns) {
            encoded.add(bytesOf(pattern))
        }
        return buildBytes(encoded.toArray())
    }

    /** 使用任意字节模式构建自动机。 */
    public func buildBytes(patterns: Array<Array<Byte>>): AhoCorasick {
        return AhoCorasick(
            patterns,
            matchKindConfig,
            caseInsensitive,
            starts,
            usePrefilter,
            useByteClasses,
            configuredDenseDepth,
            requestedKind
        )
    }
}

func isStandard(kind: MatchKind): Bool {
    match (kind) {
        case MatchKind.Standard => true
        case _ => false
    }
}

func isLeftmostLongest(kind: MatchKind): Bool {
    match (kind) {
        case MatchKind.LeftmostLongest => true
        case _ => false
    }
}

func isAnchored(mode: Anchored): Bool {
    match (mode) {
        case Anchored.Yes => true
        case _ => false
    }
}

func isStartUnanchored(kind: StartKind): Bool {
    match (kind) {
        case StartKind.Unanchored => true
        case _ => false
    }
}

func isStartAnchored(kind: StartKind): Bool {
    match (kind) {
        case StartKind.Anchored => true
        case _ => false
    }
}

func isStartBoth(kind: StartKind): Bool {
    match (kind) {
        case StartKind.Both => true
        case _ => false
    }
}

func bytesOf(value: String): Array<Byte> {
    return value.toArray()
}

func normalize(input: Array<Byte>, caseInsensitive: Bool): Array<Byte> {
    if (!caseInsensitive) {
        return input
    }
    return Array<Byte>(
        input.size,
        {
            index =>
                let byte = input[index]
                if (byte >= 65 && byte <= 90) {
                    byte + 32
                } else {
                    byte
                }
        }
    )
}

func normalizeByte(byte: Byte, caseInsensitive: Bool): Byte {
    if (caseInsensitive && byte >= 65 && byte <= 90) {
        return byte + 32
    }
    return byte
}

func appendBytes(target: ArrayList<Byte>, source: Array<Byte>, start: Int64, end: Int64): Unit {
    for (index in start..end) {
        target.add(source[index])
    }
}

func sliceBytes(source: Array<Byte>, start: Int64, end: Int64): Array<Byte> {
    return Array<Byte>(end - start, {index => source[start + index]})
}

func isUtf8Boundary(bytes: Array<Byte>, offset: Int64): Bool {
    if (offset <= 0 || offset >= bytes.size) {
        return true
    }
    let byte = bytes[offset]
    return byte < 128 || byte > 191
}

func appendListBytes(
    target: ArrayList<Byte>,
    source: ArrayList<Byte>,
    start: Int64,
    end: Int64
): Unit {
    for (index in start..end) {
        target.add(source[index])
    }
}

func sliceListBytes(source: ArrayList<Byte>, start: Int64, end: Int64): Array<Byte> {
    return Array<Byte>(end - start, {index => source[start + index]})
}

func retainListTail(items: ArrayList<Byte>, start: Int64): Unit {
    let tail = sliceListBytes(items, start, items.size)
    items.clear()
    appendBytes(items, tail, 0, tail.size)
}

func flushReadyIfNeeded(output: OutputStream, ready: ArrayList<Byte>, threshold: Int64): Unit {
    if (ready.size >= threshold) {
        flushReady(output, ready)
    }
}

func flushReady(output: OutputStream, ready: ArrayList<Byte>): Unit {
    if (ready.size == 0) {
        return
    }
    output.write(ready.toArray())
    ready.clear()
}
