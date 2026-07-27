package aho_cangjie_benchmark

import aho4cj.{AhoCorasick, Match}
import std.collection.ArrayList
import std.sort.sort
import std.time.MonoTime

const SAMPLES: Int64 = 5

func measure(name: String, iterations: Int64, body: () -> Int64): Unit {
    for (_ in 0..3) {
        body()
    }
    let samples = ArrayList<Int64>()
    var checksum: Int64 = 0
    for (_ in 0..SAMPLES) {
        let start = MonoTime.now()
        for (_ in 0..iterations) {
            checksum = checksum + body()
        }
        samples.add((MonoTime.now() - start).toNanoseconds() / iterations)
    }
    sort(samples)
    print("${name},${samples[SAMPLES / 2]},${checksum}\n", flush: true)
}

func matchChecksum(matches: Array<Match>): Int64 {
    var checksum: Int64 = 0
    for (matched in matches) {
        checksum = checksum + matched.pattern + matched.start + matched.end
    }
    return checksum
}

main(): Int64 {
    let patternList = ArrayList<String>()
    for (index in 0..1000) {
        patternList.add("needle-${index}")
    }
    let patterns = patternList.toArray()

    let sparseParts = ArrayList<String>()
    for (index in 0..5000) {
        if (index % 100 == 0) {
            sparseParts.add("needle-${index % 1000};")
        } else {
            sparseParts.add("unrelated-payload-${index};")
        }
    }
    let sparse = String.join(sparseParts.toArray())

    let highPatternList = ArrayList<String>()
    var current = ""
    for (_ in 0..8) {
        current = current + "a"
        highPatternList.add(current)
    }
    let highParts = ArrayList<String>()
    for (_ in 0..1024) {
        highParts.add("a")
    }
    let high = String.join(highParts.toArray())

    let sparseAc = AhoCorasick.new(patterns)
    let highAc = AhoCorasick.new(highPatternList.toArray())
    let sparseBytes = sparse.toArray()
    let sparseMatches = sparseAc.findAll(sparse)
    let highMatches = highAc.findOverlappingAll(high)
    print(
        "meta,sparse_bytes=${sparse.size},sparse_matches=${sparseMatches.size}," +
            "high_bytes=${high.size},high_matches=${highMatches.size}," +
            "sparse_checksum=${matchChecksum(sparseMatches)},high_checksum=${matchChecksum(highMatches)}\n",
        flush: true
    )

    measure(
        "build_1000",
        5,
        {
            =>
                let ac = AhoCorasick.new(patterns)
                ac.stateCount
        }
    )
    measure("sparse_find", 20, {=> matchChecksum(sparseAc.findAll(sparse))})
    measure("sparse_find_bytes", 20, {=> matchChecksum(sparseAc.findAllBytes(sparseBytes))})
    measure(
        "byte_scan",
        100,
        {
            =>
                var sum: Int64 = 0
                for (byte in sparseBytes) {
                    sum = sum + Int64(byte)
                }
                sum
        }
    )
    measure("overlap_find", 20, {=> matchChecksum(highAc.findOverlappingAll(high))})
    return 0
}
