package aho4cj

import std.collection.ArrayList
import std.io.{InputStream, OutputStream}
import std.sort.sort
import std.unittest.testmacro.{Test, TestCase}

class ChunkedInputStream <: InputStream {
    private let data: Array<Byte>
    private let chunkSize: Int64
    private var position: Int64 = 0

    init(data: Array<Byte>, chunkSize: Int64) {
        this.data = data
        this.chunkSize = chunkSize
    }

    public func read(buffer: Array<Byte>): Int64 {
        if (position >= data.size) {
            return 0
        }
        var count = data.size - position
        if (count > chunkSize) {
            count = chunkSize
        }
        if (count > buffer.size) {
            count = buffer.size
        }
        for (index in 0..count) {
            buffer[index] = data[position + index]
        }
        position = position + count
        return count
    }
}

class CollectingOutputStream <: OutputStream {
    private let bytes = ArrayList<Byte>()

    public func write(buffer: Array<Byte>): Unit {
        for (byte in buffer) {
            bytes.add(byte)
        }
    }

    func toArray(): Array<Byte> {
        return bytes.toArray()
    }
}

@Test
public class AhoCorasickTests {
    @TestCase
    public func basicSearchReturnsPatternAndByteOffsets(): Unit {
        let ac = AhoCorasick.new(["apple", "maple", "Snapple"])
        let matches = ac.findAll("Nobody likes maple in their apple flavored Snapple.")

        @Assert(matches.size, 3)
        assertMatch(matches[0], 1, 13, 18)
        assertMatch(matches[1], 0, 28, 33)
        assertMatch(matches[2], 2, 43, 50)
    }

    @TestCase
    public func failureLinksFindSuffixPatterns(): Unit {
        let ac = AhoCorasick.new(["he", "she", "hers", "his"])
        let matches = ac.findOverlappingAll("ushers")

        @Assert(matches.size, 3)
        assertMatch(matches[0], 1, 1, 4)
        assertMatch(matches[1], 0, 2, 4)
        assertMatch(matches[2], 2, 2, 6)
    }

    @TestCase
    public func standardChoosesEarliestEndingMatch(): Unit {
        let ac = AhoCorasick.new(["Samwise", "Sam"])
        assertSomeMatch(ac.find("Samwise"), 1, 0, 3)
    }

    @TestCase
    public func leftmostFirstUsesPatternOrder(): Unit {
        let ac = AhoCorasickBuilder().matchKind(MatchKind.LeftmostFirst).build(["Samwise", "Sam"])
        assertSomeMatch(ac.find("Samwise"), 0, 0, 7)
    }

    @TestCase
    public func leftmostLongestUsesLongestPattern(): Unit {
        let ac = AhoCorasickBuilder().matchKind(MatchKind.LeftmostLongest).build(["Sam", "Samwise"])
        assertSomeMatch(ac.find("Samwise"), 1, 0, 7)
    }

    @TestCase
    public func supportsOverlappingMatches(): Unit {
        let matches = AhoCorasick.new(["a", "aa"]).findOverlappingAll("aaa")

        @Assert(matches.size, 5)
        assertMatch(matches[0], 0, 0, 1)
        assertMatch(matches[1], 1, 0, 2)
        assertMatch(matches[2], 0, 1, 2)
        assertMatch(matches[3], 1, 1, 3)
        assertMatch(matches[4], 0, 2, 3)
    }

    @TestCase
    public func asciiCaseInsensitiveOnlyFoldsAscii(): Unit {
        let ac = AhoCorasickBuilder().asciiCaseInsensitive(true).build(["apple", "snapple"])
        let matches = ac.findAll("APPLE Snapple")

        @Assert(matches.size, 2)
        assertMatch(matches[0], 0, 0, 5)
        assertMatch(matches[1], 1, 6, 13)
    }

    @TestCase
    public func reportsUtf8ByteOffsets(): Unit {
        let matches = AhoCorasick.new(["仓颉", "语言"]).findAll("我爱仓颉语言")

        @Assert(matches.size, 2)
        assertMatch(matches[0], 0, 6, 12)
        assertMatch(matches[1], 1, 12, 18)
    }

    @TestCase
    public func replacesMatchesByPatternId(): Unit {
        let ac = AhoCorasick.new(["fox", "brown", "quick"])
        @Assert(ac.replaceAll("The quick brown fox.", ["sloth", "grey", "slow"]),
            "The slow grey sloth.")
    }

    @TestCase
    public func emptyPatternMatchesEveryBytePosition(): Unit {
        let matches = AhoCorasick.new([""]).findAll("ab")

        @Assert(matches.size, 3)
        assertMatch(matches[0], 0, 0, 0)
        assertMatch(matches[1], 0, 1, 1)
        assertMatch(matches[2], 0, 2, 2)
    }

    @TestCase
    public func validatesOperationConfiguration(): Unit {
        let leftmost = AhoCorasickBuilder().matchKind(MatchKind.LeftmostFirst).build(["a"])
        try {
            leftmost.findOverlappingAll("a")
            @Fail("左最语义的重叠搜索应抛出 MatchException")
        } catch (error: MatchException) {
            @Assert(isUnsupportedOverlapping(error.kind))
        }

        let ac = AhoCorasick.new(["a", "b"])
        @AssertThrows[IllegalArgumentException](ac.replaceAll("ab", ["x"]))
    }

    @TestCase
    public func exposesAutomatonMetrics(): Unit {
        let ac = AhoCorasick.new(["he", "she", "hers", "his"])
        @Assert(ac.patternCount, 4)
        @Assert(ac.stateCount > 1)
    }

    @TestCase
    public func searchesAndReplacesArbitraryBytes(): Unit {
        let patterns: Array<Array<Byte>> = [[255], [0, 255]]
        let ac = AhoCorasick.newBytes(patterns)

        assertSomeMatch(ac.findBytes([0, 255, 1]), 1, 0, 2)
        let expected: Array<Byte> = [8, 1]
        @Assert(ac.replaceAllBytes([0, 255, 1], [[9], [8]]), expected)
    }

    @TestCase
    public func automatonOwnsPatternBytesAfterBuild(): Unit {
        let pattern: Array<Byte> = [97, 98]
        let ac = AhoCorasick.newBytes([pattern])
        pattern[0] = 120

        assertSomeMatch(ac.findBytes([97, 98]), 0, 0, 2)
        @Assert(ac.findBytes([120, 98]).isNone())
    }

    @TestCase
    public func inputRestrictsSearchSpan(): Unit {
        let ac = AhoCorasick.new(["abc"])
        assertSomeMatch(ac.find(Input("zzabczz").span(2, 5)), 0, 2, 5)
        @Assert(ac.find(Input("zzabczz").span(0, 4)).isNone())
    }

    @TestCase
    public func spanAndInputSupportUpstreamTerminationSemantics(): Unit {
        let reversed = Span(4, 3)
        @Assert(reversed.isEmpty)
        @Assert(reversed.length, 0)
        @Assert(!reversed.contains(4))
        @Assert(reversed.offset(2).toString(), "6..5")

        let span = Span(2, 4)
        @Assert(span.contains(2))
        @Assert(span.contains(4))
        @Assert(!span.contains(5))

        let input = Input("abc")
        input.setStart(3)
        @Assert(!input.isDone)
        input.setStart(4)
        @Assert(input.isDone)
        input.setEnd(3)
        input.setAnchored(Anchored.Yes)
        input.setEarliest(true)
        @Assert(input.start, 4)
        @Assert(input.end, 3)
        @Assert(input.isEarliest)

        let ac = AhoCorasickBuilder().startKind(StartKind.Both).build([""])
        @Assert(ac.find(input).isNone())
        input.setAnchored(Anchored.No)
        @Assert(ac.findOverlappingAll(input).size, 0)
        @Assert(ac.findOverlappingIter(input).next().isNone())
    }

    @TestCase
    public func anchoredSearchHonorsStartKindAndSpan(): Unit {
        let defaultAc = AhoCorasick.new(["bcd"])
        @AssertThrows[MatchException](defaultAc.find(Input("abcd").anchored(Anchored.Yes)))

        let ac = AhoCorasickBuilder().startKind(StartKind.Both).build(["bcd"])
        assertSomeMatch(ac.find(Input("abcd")), 0, 1, 4)
        @Assert(ac.find(Input("abcd").anchored(Anchored.Yes)).isNone())
        assertSomeMatch(ac.find(Input("abcd").span(1, 4).anchored(Anchored.Yes)), 0, 1, 4)
    }

    @TestCase
    public func anchoredOnlyRejectsUnanchoredInput(): Unit {
        let ac = AhoCorasickBuilder().startKind(StartKind.AnchoredOnly).build(["a"])
        @AssertThrows[MatchException](ac.find(Input("a")))
        assertSomeMatch(ac.find(Input("a").anchored(Anchored.Yes)), 0, 0, 1)
    }

    @TestCase
    public func earliestOverridesLeftmostSelection(): Unit {
        let ac = AhoCorasickBuilder().matchKind(MatchKind.LeftmostFirst).build(["abc", "b"])
        assertSomeMatch(ac.find(Input("abc")), 0, 0, 3)
        assertSomeMatch(ac.find(Input("abc").earliest(true)), 1, 1, 2)
    }

    @TestCase
    public func overlappingOrdersLongerMatchBeforeSuffix(): Unit {
        let matches = AhoCorasick.new(["he", "she"]).findOverlappingAll("she")
        @Assert(matches.size, 2)
        assertMatch(matches[0], 1, 0, 3)
        assertMatch(matches[1], 0, 1, 3)
    }

    @TestCase
    public func emptyPatternParticipatesInStandardOrdering(): Unit {
        let ac = AhoCorasick.new(["a", ""])
        let matches = ac.findAll("a")
        @Assert(matches.size, 2)
        assertMatch(matches[0], 1, 0, 0)
        assertMatch(matches[1], 1, 1, 1)

        let overlapping = ac.findOverlappingAll("a")
        @Assert(overlapping.size, 3)
        assertMatch(overlapping[0], 1, 0, 0)
        assertMatch(overlapping[1], 0, 0, 1)
        assertMatch(overlapping[2], 1, 1, 1)
    }

    @TestCase
    public func allAutomatonKindsProduceTheSameMatches(): Unit {
        let kinds = [
            AhoCorasickKind.NoncontiguousNFA,
            AhoCorasickKind.ContiguousNFA,
            AhoCorasickKind.DFA
        ]
        for (kind in kinds) {
            let ac = AhoCorasickBuilder().kind(kind).build(["he", "she", "hers", "his"])
            let matches = ac.findOverlappingAll("ushers")
            @Assert(matches.size, 3)
            assertMatch(matches[0], 1, 1, 4)
            assertMatch(matches[1], 0, 2, 4)
            assertMatch(matches[2], 2, 2, 6)
            @Assert(ac.memoryUsage > 0)
        }
    }

    @TestCase
    public func lowLevelViewExposesTransitionsAndMatchOutputs(): Unit {
        for (kind in automatonKinds()) {
            let ac = AhoCorasickBuilder().kind(kind).startKind(StartKind.Both).build(["he", "she"])
            let view = ac.lowLevel()
            var state = view.startState(Anchored.No)
            @Assert(view.isStart(state))
            @Assert(view.isSpecial(state))
            for (byte in "she".toArray()) {
                state = view.nextState(Anchored.No, state, byte)
            }
            @Assert(view.isMatch(state))
            @Assert(view.matchCount(state), 2)
            @Assert(view.matchPattern(state, 0), 1)
            @Assert(view.matchPattern(state, 1), 0)
            @Assert(view.patternLength(1), 3)
            @Assert(view.patternCount, 2)
            @Assert(view.stateCount, ac.stateCount + 1)
            @Assert(view.minimumPatternLength, 2)
            @Assert(view.maximumPatternLength, 3)
            @Assert(view.memoryUsage, ac.memoryUsage)
            @Assert(view.hasPrefilter)
            @Assert(!isLeftmostLongestKind(view.matchKind))

            let anchoredStart = view.startState(Anchored.Yes)
            let dead = view.nextState(Anchored.Yes, anchoredStart, 120)
            @Assert(view.isDead(dead))
            @Assert(view.isSpecial(dead))
            @Assert(!view.isStart(dead))
            @Assert(!view.isMatch(dead))
            @Assert(view.matchCount(dead), 0)
            @Assert(view.isDead(view.nextState(Anchored.Yes, dead, 115)))
            @AssertThrows[IllegalArgumentException](view.matchPattern(dead, 0))
            @AssertThrows[IllegalArgumentException](view.patternLength(2))
        }

        let unanchoredOnly = AhoCorasick.new(["a"]).lowLevel()
        @AssertThrows[MatchException](unanchoredOnly.startState(Anchored.Yes))
        @AssertThrows[IllegalArgumentException](unanchoredOnly.isMatch(StateID(999)))
        @Assert(StateID(3).toString(), "StateID(3)")
        @AssertThrows[IllegalArgumentException](StateID(-1))
    }

    @TestCase
    public func automaticallySelectsDfaOnlyForSmallPatternSets(): Unit {
        let small = AhoCorasick.new(["a", "b"])
        @Assert(isDfaKind(small.kind))

        let patterns = Array<String>(101, {index => "pattern-${index}"})
        let large = AhoCorasick.new(patterns)
        @Assert(isContiguousKind(large.kind))

        let both = AhoCorasickBuilder().startKind(StartKind.Both).build(["a"])
        @Assert(isContiguousKind(both.kind))
    }

    @TestCase
    public func exposesPatternAndSearchMetadata(): Unit {
        let ac = AhoCorasickBuilder()
            .matchKind(MatchKind.LeftmostLongest)
            .startKind(StartKind.Both)
            .build(["a", "alphabet", "abc"])
        @Assert(ac.minPatternLength, 1)
        @Assert(ac.maxPatternLength, 8)
        @Assert(ac.isMatch("xxabc"))
        @Assert(!ac.isMatch("xyz"))
        @Assert(isLeftmostLongestKind(ac.configuredMatchKind))
        @Assert(isBothStartKind(ac.configuredStartKind))
    }

    @TestCase
    public func callbackReplacementReceivesMatchAndBytes(): Unit {
        let ac = AhoCorasick.new(["fox", "dog"])
        let text = ac.replaceAllWith("fox and dog", {
            matched, value => "${matched.pattern}:${value}"
        })
        @Assert(text, "0:fox and 1:dog")

        let bytes: Array<Byte> = [0, 255, 0]
        let byteAc = AhoCorasick.newBytes([[255]])
        let replaced = byteAc.replaceAllWithBytes(bytes, {
            _, value => [value[0], value[0]]
        })
        let expected: Array<Byte> = [0, 255, 255, 0]
        @Assert(replaced, expected)
    }

    @TestCase
    public func stringReplacementSkipsMatchesInsideUtf8CodePoints(): Unit {
        let continuationByte = AhoCorasick.newBytes([[169]])
        @Assert(continuationByte.replaceAll("é", ["x"]), "é")
        @Assert(continuationByte.replaceAllWith("é", {_, _ => "x"}), "é")

        let completeCodePoint = AhoCorasick.newBytes([[195, 169]])
        @Assert(completeCodePoint.replaceAll("é", ["e"]), "e")
    }

    @TestCase
    public func controlledReplacementCanStopAfterCurrentMatch(): Unit {
        let ac = AhoCorasick.new(["a"])
        let text = ac.replaceAllWithControlled("a-a-a", {
            matched, _ => StringReplacement("${matched.start}", shouldContinue: false)
        })
        @Assert(text, "0-a-a")

        let bytes = ac.replaceAllWithBytesControlled("a-a-a".toArray(), {
            _, _ => ByteReplacement([120], shouldContinue: false)
        })
        @Assert(String.fromUtf8(bytes), "x-a-a")
    }

    @TestCase
    public func matchIteratorsImplementCangjieIterator(): Unit {
        let iterator = AhoCorasick.new(["a"]).findIter("aba")
        match (iterator.next()) {
            case Some(matched) => assertMatch(matched, 0, 0, 1)
            case None => @Fail("迭代器缺少第一个匹配")
        }
        match (iterator.next()) {
            case Some(matched) => assertMatch(matched, 0, 2, 3)
            case None => @Fail("迭代器缺少第二个匹配")
        }
        @Assert(iterator.next().isNone())
    }

    @TestCase
    public func streamIteratorFindsMatchesAcrossReadBoundaries(): Unit {
        let ac = AhoCorasick.new(["needle", "payload"])
        let input = ChunkedInputStream("xxneedle-payload-needle".toArray(), 2)
        let matches = collectIterator(ac.streamFindIter(input, 3))
        @Assert(matches.size, 3)
        assertMatch(matches[0], 0, 2, 8)
        assertMatch(matches[1], 1, 9, 16)
        assertMatch(matches[2], 0, 17, 23)
    }

    @TestCase
    public func streamIteratorSupportsAsciiCaseAndRejectsEmptyPatterns(): Unit {
        let folded = AhoCorasickBuilder().asciiCaseInsensitive(true).build(["abc"])
        let foldedMatches = collectIterator(folded.streamFindIter(ChunkedInputStream("xxABC".toArray(), 1), 2))
        @Assert(foldedMatches.size, 1)
        assertMatch(foldedMatches[0], 0, 2, 5)

        let empty = AhoCorasick.new([""])
        @AssertThrows[MatchException](
            empty.streamFindIter(ChunkedInputStream("ab".toArray(), 1), 1)
        )
    }

    @TestCase
    public func streamIteratorRejectsUnsupportedConfiguration(): Unit {
        let leftmost = AhoCorasickBuilder().matchKind(MatchKind.LeftmostFirst).build(["a"])
        @AssertThrows[MatchException](
            leftmost.streamFindIter(ChunkedInputStream("a".toArray(), 1))
        )
        let standard = AhoCorasick.new(["a"])
        @AssertThrows[IllegalArgumentException](
            standard.streamFindIter(ChunkedInputStream("a".toArray(), 1), 0)
        )
    }

    @TestCase
    public func streamReplacementMatchesInMemoryReplacement(): Unit {
        let ac = AhoCorasick.new(["fox", "brown", "quick"])
        let haystack = "The quick brown fox.".toArray()
        let replacements = ["sloth".toArray(), "grey".toArray(), "slow".toArray()]
        let output = CollectingOutputStream()
        ac.streamReplaceAll(ChunkedInputStream(haystack, 2), output, replacements, 3)
        @Assert(output.toArray(), ac.replaceAllBytes(haystack, replacements))
        @Assert(String.fromUtf8(output.toArray()), "The slow grey sloth.")
    }

    @TestCase
    public func streamReplacementCallbackReceivesOriginalBytes(): Unit {
        let ac = AhoCorasickBuilder().asciiCaseInsensitive(true).build(["abc"])
        let output = CollectingOutputStream()
        ac.streamReplaceAllWithBytes(
            ChunkedInputStream("xABCyabc".toArray(), 1),
            output,
            {matched, value => "${matched.start}:${String.fromUtf8(value)}".toArray()},
            2
        )
        @Assert(String.fromUtf8(output.toArray()), "x1:ABCy5:abc")
    }

    @TestCase
    public func controlledStreamReplacementCopiesUnreadRemainder(): Unit {
        let ac = AhoCorasick.new(["a"])
        let output = CollectingOutputStream()
        ac.streamReplaceAllWithBytesControlled(
            ChunkedInputStream("a-aaa-tail".toArray(), 6),
            output,
            {_, _ => ByteReplacement([120], shouldContinue: false)},
            8
        )
        @Assert(String.fromUtf8(output.toArray()), "x-aaa-tail")
    }

    @TestCase
    public func streamReplacementRejectsEmptyPattern(): Unit {
        let ac = AhoCorasick.new([""])
        let output = CollectingOutputStream()
        @AssertThrows[MatchException](
            ac.streamReplaceAll(
                ChunkedInputStream("ab".toArray(), 1),
                output,
                [[45]],
                1
            )
        )
    }

    @TestCase
    public func overlappingIteratorAndStateAreIncremental(): Unit {
        let ac = AhoCorasick.new(["a", "aa"])
        let iterated = collectIterator(ac.findOverlappingIter("aaa"))
        let batched = ac.findOverlappingAll("aaa")
        @Assert(iterated.size, batched.size)
        for (index in 0..batched.size) {
            assertMatch(
                iterated[index],
                batched[index].pattern,
                batched[index].start,
                batched[index].end
            )
        }

        let state = OverlappingState()
        assertSomeMatch(ac.findOverlapping("aa", state), 0, 0, 1)
        assertSomeMatch(ac.findOverlapping("aa", state), 1, 0, 2)
        assertSomeMatch(ac.findOverlapping("aa", state), 0, 1, 2)
        @Assert(ac.findOverlapping("aa", state).isNone())
        state.reset()
        assertSomeMatch(ac.findOverlapping("a", state), 0, 0, 1)
    }

    @TestCase
    public func anchoredOverlappingRequiresExplicitState(): Unit {
        let ac = AhoCorasickBuilder().startKind(StartKind.Both).build(["app", "append", "appendage"])
        let input = Input("appendage").anchored(Anchored.Yes)
        @AssertThrows[MatchException](ac.findOverlappingIter(input))
        @AssertThrows[MatchException](ac.findOverlappingAll(input))

        let state = OverlappingState()
        assertSomeMatch(ac.findOverlapping(input, state), 0, 0, 3)
        assertSomeMatch(ac.findOverlapping(input, state), 1, 0, 6)
        assertSomeMatch(ac.findOverlapping(input, state), 2, 0, 9)
        @Assert(ac.findOverlapping(input, state).isNone())
    }

    @TestCase
    public func leftmostIteratorWaitsForHigherPriorityMatch(): Unit {
        let first = AhoCorasickBuilder().matchKind(MatchKind.LeftmostFirst).build(["abcd", "b"])
        assertSomeMatch(first.findIter("abcd").next(), 0, 0, 4)

        let longest = AhoCorasickBuilder().matchKind(MatchKind.LeftmostLongest).build(["ab", "abcd", "b"])
        assertSomeMatch(longest.findIter("abcd").next(), 1, 0, 4)
    }

    @TestCase
    public func leftmostIteratorHandlesEmptyPatternPriority(): Unit {
        let nonEmptyFirst = AhoCorasickBuilder().matchKind(MatchKind.LeftmostFirst).build(["a", ""])
        let matches = collectIterator(nonEmptyFirst.findIter("a"))
        @Assert(matches.size, 1)
        assertMatch(matches[0], 0, 0, 1)

        let emptyFirst = AhoCorasickBuilder().matchKind(MatchKind.LeftmostFirst).build(["", "a"])
        assertSomeMatch(emptyFirst.findIter("a").next(), 0, 0, 0)
    }

    @TestCase
    public func byteClassesReduceDfaMemoryWithoutChangingMatches(): Unit {
        let compressed = AhoCorasickBuilder().kind(AhoCorasickKind.DFA).byteClasses(true).build(["abc", "abd"])
        let uncompressed = AhoCorasickBuilder().kind(AhoCorasickKind.DFA).byteClasses(false).build(["abc", "abd"])
        @Assert(compressed.memoryUsage < uncompressed.memoryUsage)

        let expected = uncompressed.findAll("xxabc-abd")
        let actual = compressed.findAll("xxabc-abd")
        @Assert(actual.size, expected.size)
        for (index in 0..expected.size) {
            assertMatch(actual[index], expected[index].pattern, expected[index].start, expected[index].end)
        }
    }

    @TestCase
    public func byteClassesHandleEveryPossibleByte(): Unit {
        let allBytes = Array<Byte>(256, {index => UInt8(index)})
        let ac = AhoCorasickBuilder().kind(AhoCorasickKind.DFA).buildBytes([allBytes])
        assertSomeMatch(ac.findBytes(allBytes), 0, 0, 256)
    }

    @TestCase
    public func denseDepthTradesMemoryForEquivalentSearch(): Unit {
        let sparse = AhoCorasickBuilder().kind(AhoCorasickKind.ContiguousNFA).denseDepth(0).build(["abcd", "abce", "bc"])
        let dense = AhoCorasickBuilder().kind(AhoCorasickKind.ContiguousNFA).denseDepth(4).build(["abcd", "abce", "bc"])
        @Assert(dense.memoryUsage > sparse.memoryUsage)
        let sparseMatches = sparse.findOverlappingAll("zabcdabcebc")
        let denseMatches = dense.findOverlappingAll("zabcdabcebc")
        @Assert(denseMatches.size, sparseMatches.size)
        for (index in 0..sparseMatches.size) {
            assertMatch(
                denseMatches[index],
                sparseMatches[index].pattern,
                sparseMatches[index].start,
                sparseMatches[index].end
            )
        }
        @AssertThrows[IllegalArgumentException](AhoCorasickBuilder().denseDepth(-1))
    }

    @TestCase
    public func matchesUpstreamStandardVectors(): Unit {
        assertUpstreamSearch(["ab", "abcd"], "abcd", MatchKind.Standard, [[0, 0, 2]])
        assertUpstreamSearch(["abcd", "bcd", "cd", "b"], "abcd", MatchKind.Standard, [[3, 1, 2], [2, 2, 4]])
        assertUpstreamSearch(["a", ""], "a", MatchKind.Standard, [[1, 0, 0], [1, 1, 1]])
        assertUpstreamSearch(["", "a", ""], "a", MatchKind.Standard, [[0, 0, 0], [0, 1, 1]])
        assertUpstreamSearch(["yabcdef", "abcdezghi"], "yabcdezghi", MatchKind.Standard, [[1, 1, 10]])
        assertUpstreamSearch(["inf", "ind"], "infind", MatchKind.Standard, [[0, 0, 3], [1, 3, 6]])
    }

    @TestCase
    public func matchesUpstreamLeftmostFirstVectors(): Unit {
        assertUpstreamSearch(["abcd", "ab"], "abcd", MatchKind.LeftmostFirst, [[0, 0, 4]])
        assertUpstreamSearch(["", "a"], "a", MatchKind.LeftmostFirst, [[0, 0, 0], [0, 1, 1]])
        assertUpstreamSearch(["a", ""], "ab", MatchKind.LeftmostFirst, [[0, 0, 1], [1, 2, 2]])
        assertUpstreamSearch(["abcdefg", "bcde", "bcdef"], "abcdef", MatchKind.LeftmostFirst, [[1, 1, 5]])
        assertUpstreamSearch(["abcd", "b", "bce", "ce"], "abce", MatchKind.LeftmostFirst, [[1, 1, 2], [3, 2, 4]])
        assertUpstreamSearch(["a", "abcdefghi", "hz", "abcdefgh"], "abcdefghz", MatchKind.LeftmostFirst,
            [[0, 0, 1], [2, 7, 9]])
    }

    @TestCase
    public func matchesUpstreamLeftmostLongestVectors(): Unit {
        assertUpstreamSearch(["ab", "abcd"], "abcd", MatchKind.LeftmostLongest, [[1, 0, 4]])
        assertUpstreamSearch(["", "a", ""], "a", MatchKind.LeftmostLongest, [[1, 0, 1]])
        assertUpstreamSearch(["", "a"], "ab", MatchKind.LeftmostLongest, [[1, 0, 1], [0, 2, 2]])
        assertUpstreamSearch(["abcdefg", "bcde", "bcdef"], "abcdef", MatchKind.LeftmostLongest, [[2, 1, 6]])
        assertUpstreamSearch(["abcd", "b", "ce"], "abce", MatchKind.LeftmostLongest, [[1, 1, 2], [2, 2, 4]])
        assertUpstreamSearch(["a", "ab"], "xayabbbz", MatchKind.LeftmostLongest, [[0, 1, 2], [1, 3, 5]])
    }

    @TestCase
    public func matchesUpstreamAnchoredIterationVectors(): Unit {
        assertUpstreamAnchored(["abcd", "bcd", "cd", "b"], "abcd", MatchKind.Standard, [[0, 0, 4]])
        assertUpstreamAnchored(["a", "b"], "ab", MatchKind.Standard, [[0, 0, 1], [1, 1, 2]])
        assertUpstreamAnchored(["foo"], "foofoo foo", MatchKind.Standard, [[0, 0, 3], [0, 3, 6]])
        assertUpstreamAnchored(["ab", "a"], "xayabbbz", MatchKind.LeftmostFirst, [])
        assertUpstreamAnchored(["a", "abcdefghi", "hz", "abcdefgh"], "abcdefghz", MatchKind.LeftmostFirst, [[0, 0, 1]])
        assertUpstreamAnchored(["a", "abcdefghi", "hz", "abcdefgh"], "abcdefghz", MatchKind.LeftmostLongest, [[3, 0, 8]])
    }

    @TestCase
    public func matchesUpstreamOverlappingOrderVectors(): Unit {
        assertUpstreamOverlapping(["abcd", "bcd", "cd", "b"], "abcd", [[3, 1, 2], [0, 0, 4], [1, 1, 4], [2, 2, 4]])
        assertUpstreamOverlapping(["foo", "foo"], "foobarfoo", [[0, 0, 3], [1, 0, 3], [0, 6, 9], [1, 6, 9]])
        assertUpstreamOverlapping(["", "a", ""], "a", [[0, 0, 0], [2, 0, 0], [1, 0, 1], [0, 1, 1], [2, 1, 1]])
        assertUpstreamOverlapping(["a", "", ""], "a", [[1, 0, 0], [2, 0, 0], [0, 0, 1], [1, 1, 1], [2, 1, 1]])
        assertUpstreamOverlapping(["foo", "foofoo"], "foofoo", [[0, 0, 3], [1, 0, 6], [0, 3, 6]])
    }

    @TestCase
    public func exhaustiveSmallInputsMatchIndependentOracle(): Unit {
        let patternSets: Array<Array<String>> = [
            [],
            [""],
            ["a"],
            ["a", ""],
            ["", "a"],
            ["a", "a"],
            ["a", "aa"],
            ["aa", "a"],
            ["ab", "b"],
            ["a", "ab", "ba"],
            ["ab", "a", ""],
            ["", "b", "bb"],
            ["aba", "ba", "a"],
            ["aaa", "aa", "a"],
            ["bb", "ab", "ba", ""]
        ]
        let haystacks = ArrayList<String>()
        for (length in 0..7) {
            generateBinaryHaystacks("", length, haystacks)
        }

        let matchKinds = [MatchKind.Standard, MatchKind.LeftmostFirst, MatchKind.LeftmostLongest]
        for (patterns in patternSets) {
            for (matchKind in matchKinds) {
                for (kind in automatonKinds()) {
                    let ac = AhoCorasickBuilder().kind(kind).matchKind(matchKind).build(patterns)
                    for (haystack in haystacks) {
                        let expected = bruteNonOverlapping(patterns, haystack, matchKind)
                        assertSameMatches(ac.findAll(haystack), expected)
                    }

                    let anchoredAc = AhoCorasickBuilder()
                        .kind(kind)
                        .matchKind(matchKind)
                        .startKind(StartKind.Both)
                        .build(patterns)
                    for (haystack in haystacks) {
                        let expected = bruteAnchored(patterns, haystack, matchKind)
                        assertSameMatches(
                            anchoredAc.findAll(Input(haystack).anchored(Anchored.Yes)),
                            expected
                        )
                    }
                }
            }

            let overlappingExpected = ArrayList<Array<Match>>()
            for (haystack in haystacks) {
                overlappingExpected.add(bruteOverlapping(patterns, haystack))
            }
            for (kind in automatonKinds()) {
                let ac = AhoCorasickBuilder().kind(kind).build(patterns)
                for (index in 0..haystacks.size) {
                    let expected = overlappingExpected[index]
                    assertSameMatches(
                        ac.findOverlappingAll(haystacks[index]),
                        expected
                    )
                    assertSameMatches(collectIterator(ac.findOverlappingIter(haystacks[index])), expected)
                }
            }
        }
    }

    @TestCase
    public func packedSearcherImplementsUpstreamLeftmostSemantics(): Unit {
        let first = requirePacked(PackedSearcher.new(["foobar", "foo"]))
        assertSomeMatch(first.find("foobar"), 0, 0, 6)
        @Assert(isPackedLeftmostFirst(first.matchKind))
        @Assert(first.minimumHaystackLength, 0)
        @Assert(first.minimumPatternLength, 3)
        @Assert(first.memoryUsage > 0)

        let longest = requirePacked(
            PackedSearcher
                .config()
                .matchKind(PackedMatchKind.LeftmostLongest)
                .builder()
                .add("foo")
                .add("foobar")
                .build())
        assertSomeMatch(longest.find("foobar"), 1, 0, 6)

        let matches = collectIterator(first.findIter("foobar fooba foofoo"))
        assertExpectedMatches(matches, [[0, 0, 6], [1, 7, 10], [1, 13, 16], [1, 16, 19]])
        assertSomeMatch(first.findIn("xxxfoobar", Span(3, 9)), 0, 3, 9)
    }

    @TestCase
    public func packedBuilderEnforcesLimitsAndOwnsPatterns(): Unit {
        @Assert(PackedSearcher.new([]).isNone())
        @Assert(PackedSearcher.new([""]).isNone())

        let tooMany = PackedBuilder()
        for (index in 0..129) {
            tooMany.add("p${index}")
        }
        @Assert(tooMany.length, 0)
        @Assert(tooMany.build().isNone())

        let bytes: Array<Byte> = [0, 255]
        let searcher = requirePacked(PackedSearcher.newBytes([bytes]))
        bytes[0] = 1
        assertSomeMatch(searcher.findBytes([9, 0, 255]), 0, 1, 3)
        @Assert(searcher.findBytes([1, 255]).isNone())
        @AssertThrows[IllegalArgumentException](searcher.findInBytes([0, 255], Span(2, 1)))
    }

    @TestCase
    public func packedSearcherMatchesExhaustiveOracle(): Unit {
        let patternSets: Array<Array<String>> = [
            ["a"],
            ["a", "aa"],
            ["aa", "a"],
            ["ab", "b"],
            ["aba", "ba", "a"],
            ["a", "a", "ba"]
        ]
        let haystacks = ArrayList<String>()
        for (length in 0..7) {
            generateBinaryHaystacks("", length, haystacks)
        }
        for (patterns in patternSets) {
            let first = requirePacked(PackedSearcher.new(patterns))
            let longest = requirePacked(
                PackedSearcher.config().matchKind(PackedMatchKind.LeftmostLongest).builder().addAll(patterns).build())
            for (haystack in haystacks) {
                assertSameMatches(
                    collectIterator(first.findIter(haystack)),
                    bruteNonOverlapping(patterns, haystack, MatchKind.LeftmostFirst)
                )
                assertSameMatches(
                    collectIterator(longest.findIter(haystack)),
                    bruteNonOverlapping(patterns, haystack, MatchKind.LeftmostLongest)
                )
            }
        }
    }
}

func assertSomeMatch(actual: Option<Match>, pattern: Int64, start: Int64, end: Int64): Unit {
    match (actual) {
        case Some(value) => assertMatch(value, pattern, start, end)
        case None => @Fail("期望找到匹配，但结果为 None")
    }
}

func assertMatch(actual: Match, pattern: Int64, start: Int64, end: Int64): Unit {
    @Assert(actual.pattern, pattern)
    @Assert(actual.start, start)
    @Assert(actual.end, end)
}

func isDfaKind(kind: AhoCorasickKind): Bool {
    match (kind) {
        case AhoCorasickKind.DFA => true
        case _ => false
    }
}

func isContiguousKind(kind: AhoCorasickKind): Bool {
    match (kind) {
        case AhoCorasickKind.ContiguousNFA => true
        case _ => false
    }
}

func isLeftmostLongestKind(kind: MatchKind): Bool {
    match (kind) {
        case MatchKind.LeftmostLongest => true
        case _ => false
    }
}

func isBothStartKind(kind: StartKind): Bool {
    match (kind) {
        case StartKind.Both => true
        case _ => false
    }
}

func collectIterator(iterator: Iterator<Match>): Array<Match> {
    let matches = ArrayList<Match>()
    for (matched in iterator) {
        matches.add(matched)
    }
    return matches.toArray()
}

func requirePacked(searcher: Option<PackedSearcher>): PackedSearcher {
    match (searcher) {
        case Some(value) => value
        case None => throw IllegalStateException("期望成功构建 PackedSearcher")
    }
}

func isPackedLeftmostFirst(kind: PackedMatchKind): Bool {
    match (kind) {
        case PackedMatchKind.LeftmostFirst => true
        case _ => false
    }
}

func isUnsupportedOverlapping(kind: MatchErrorKind): Bool {
    match (kind) {
        case MatchErrorKind.UnsupportedOverlapping => true
        case _ => false
    }
}

func automatonKinds(): Array<AhoCorasickKind> {
    return [
        AhoCorasickKind.NoncontiguousNFA,
        AhoCorasickKind.ContiguousNFA,
        AhoCorasickKind.DFA
    ]
}

func assertUpstreamSearch(
    patterns: Array<String>,
    haystack: String,
    matchKind: MatchKind,
    expected: Array<Array<Int64>>
): Unit {
    for (kind in automatonKinds()) {
        let ac = AhoCorasickBuilder().kind(kind).matchKind(matchKind).build(patterns)
        assertExpectedMatches(ac.findAll(haystack), expected)
    }
}

func assertUpstreamAnchored(
    patterns: Array<String>,
    haystack: String,
    matchKind: MatchKind,
    expected: Array<Array<Int64>>
): Unit {
    for (kind in automatonKinds()) {
        let ac = AhoCorasickBuilder().kind(kind).matchKind(matchKind).startKind(StartKind.Both).build(patterns)
        assertExpectedMatches(ac.findAll(Input(haystack).anchored(Anchored.Yes)), expected)
    }
}

func assertUpstreamOverlapping(
    patterns: Array<String>,
    haystack: String,
    expected: Array<Array<Int64>>
): Unit {
    for (kind in automatonKinds()) {
        let ac = AhoCorasickBuilder().kind(kind).build(patterns)
        assertExpectedMatches(ac.findOverlappingAll(haystack), expected)
    }
}

func assertExpectedMatches(actual: Array<Match>, expected: Array<Array<Int64>>): Unit {
    @Assert(actual.size, expected.size)
    for (index in 0..expected.size) {
        assertMatch(actual[index], expected[index][0], expected[index][1], expected[index][2])
    }
}

func generateBinaryHaystacks(prefix: String, remaining: Int64, output: ArrayList<String>): Unit {
    if (remaining == 0) {
        output.add(prefix)
        return
    }
    generateBinaryHaystacks(prefix + "a", remaining - 1, output)
    generateBinaryHaystacks(prefix + "b", remaining - 1, output)
}

func bruteOverlapping(patterns: Array<String>, haystack: String): Array<Match> {
    let bytes = haystack.toArray()
    let candidates = ArrayList<Match>()
    for (patternId in 0..patterns.size) {
        let pattern = patterns[patternId].toArray()
        for (start in 0..(bytes.size + 1)) {
            if (start + pattern.size <= bytes.size && bytesEqualAt(bytes, pattern, start)) {
                candidates.add(Match(patternId, start, start + pattern.size))
            }
        }
    }
    sort(candidates, lessThan: {
        a, b => if (a.end != b.end) {
            a.end < b.end
        } else if (a.start != b.start) {
            a.start < b.start
        } else {
            a.pattern < b.pattern
        }
    }, stable: true)
    return candidates.toArray()
}

func bruteNonOverlapping(
    patterns: Array<String>,
    haystack: String,
    matchKind: MatchKind
): Array<Match> {
    let candidates = bruteOverlapping(patterns, haystack)
    let selected = ArrayList<Match>()
    var cursor: Int64 = 0
    var suppressEmptyAtCursor = false
    while (cursor <= haystack.size) {
        var best: Option<Match> = None
        for (candidate in candidates) {
            if (candidate.start < cursor || (suppressEmptyAtCursor && candidate.start == cursor && candidate.length == 0)) {
                continue
            }
            match (best) {
                case None => best = Some(candidate)
                case Some(current) =>
                    if (isBetterBruteCandidate(candidate, current, matchKind)) {
                        best = Some(candidate)
                    }
            }
        }
        match (best) {
            case None => break
            case Some(matched) =>
                selected.add(matched)
                if (matched.length == 0) {
                    cursor = matched.end + 1
                    suppressEmptyAtCursor = false
                } else {
                    cursor = matched.end
                    suppressEmptyAtCursor = true
                }
        }
    }
    return selected.toArray()
}

func bruteAnchored(
    patterns: Array<String>,
    haystack: String,
    matchKind: MatchKind
): Array<Match> {
    let candidates = bruteOverlapping(patterns, haystack)
    let selected = ArrayList<Match>()
    var cursor: Int64 = 0
    var suppressEmptyAtCursor = false
    while (cursor <= haystack.size) {
        var best: Option<Match> = None
        for (candidate in candidates) {
            if (candidate.start != cursor || (suppressEmptyAtCursor && candidate.length == 0)) {
                continue
            }
            match (best) {
                case None => best = Some(candidate)
                case Some(current) =>
                    if (isBetterBruteCandidate(candidate, current, matchKind)) {
                        best = Some(candidate)
                    }
            }
        }
        match (best) {
            case None => break
            case Some(matched) =>
                selected.add(matched)
                if (matched.length == 0) {
                    cursor++
                    suppressEmptyAtCursor = false
                } else {
                    cursor = matched.end
                    suppressEmptyAtCursor = true
                }
        }
    }
    return selected.toArray()
}

func isBetterBruteCandidate(candidate: Match, current: Match, matchKind: MatchKind): Bool {
    match (matchKind) {
        case MatchKind.Standard =>
            if (candidate.end != current.end) {
                return candidate.end < current.end
            }
            if (candidate.start != current.start) {
                return candidate.start < current.start
            }
            return candidate.pattern < current.pattern
        case MatchKind.LeftmostFirst =>
            if (candidate.start != current.start) {
                return candidate.start < current.start
            }
            return candidate.pattern < current.pattern
        case MatchKind.LeftmostLongest =>
            if (candidate.start != current.start) {
                return candidate.start < current.start
            }
            if (candidate.length != current.length) {
                return candidate.length > current.length
            }
            return candidate.pattern < current.pattern
    }
}

func bytesEqualAt(haystack: Array<Byte>, pattern: Array<Byte>, start: Int64): Bool {
    for (index in 0..pattern.size) {
        if (haystack[start + index] != pattern[index]) {
            return false
        }
    }
    return true
}

func assertSameMatches(actual: Array<Match>, expected: Array<Match>): Unit {
    @Assert(actual.size, expected.size)
    for (index in 0..expected.size) {
        assertMatch(actual[index], expected[index].pattern, expected[index].start, expected[index].end)
    }
}
