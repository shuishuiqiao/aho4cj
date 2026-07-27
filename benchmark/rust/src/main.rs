use std::hint::black_box;
use std::time::Instant;

use aho_corasick::{AhoCorasick, AhoCorasickKind};

const SAMPLES: usize = 5;

fn measure<F>(name: &str, iterations: usize, mut body: F)
where
    F: FnMut() -> u64,
{
    for _ in 0..3 {
        black_box(body());
    }
    let mut samples = Vec::with_capacity(SAMPLES);
    let mut checksum = 0u64;
    for _ in 0..SAMPLES {
        let start = Instant::now();
        for _ in 0..iterations {
            checksum = checksum.wrapping_add(black_box(body()));
        }
        samples.push(start.elapsed().as_nanos() as u64 / iterations as u64);
    }
    samples.sort_unstable();
    println!("{name},{},{checksum}", samples[SAMPLES / 2]);
}

fn checksum(matches: &[aho_corasick::Match]) -> u64 {
    matches.iter().fold(0u64, |sum, matched| {
        sum.wrapping_add(matched.pattern().as_usize() as u64)
            .wrapping_add(matched.start() as u64)
            .wrapping_add(matched.end() as u64)
    })
}

fn main() {
    let patterns: Vec<String> = (0..1000).map(|i| format!("needle-{i}")).collect();
    let mut sparse = String::new();
    for i in 0..5_000 {
        if i % 100 == 0 {
            sparse.push_str(&format!("needle-{};", i % 1000));
        } else {
            sparse.push_str(&format!("unrelated-payload-{i};"));
        }
    }
    let high_patterns: Vec<String> = (1..=8).map(|n| "a".repeat(n)).collect();
    let high = "a".repeat(1024);

    let sparse_ac = AhoCorasick::new(&patterns).unwrap();
    let sparse_contiguous_no_prefilter = AhoCorasick::builder()
        .kind(Some(AhoCorasickKind::ContiguousNFA))
        .prefilter(false)
        .build(&patterns)
        .unwrap();
    let high_ac = AhoCorasick::new(&high_patterns).unwrap();
    let sparse_matches: Vec<_> = sparse_ac.find_iter(&sparse).collect();
    let high_matches: Vec<_> = high_ac.find_overlapping_iter(&high).collect();
    println!(
        "meta,sparse_bytes={},sparse_matches={},high_bytes={},high_matches={},sparse_checksum={},high_checksum={}",
        sparse.len(),
        sparse_matches.len(),
        high.len(),
        high_matches.len(),
        checksum(&sparse_matches),
        checksum(&high_matches),
    );

    measure("build_1000", 5, || {
        let ac = AhoCorasick::new(black_box(&patterns)).unwrap();
        black_box(ac.memory_usage() as u64)
    });
    measure("sparse_find", 20, || {
        let matches: Vec<_> = sparse_ac.find_iter(black_box(&sparse)).collect();
        checksum(black_box(&matches))
    });
    measure("sparse_find_bytes", 20, || {
        let matches: Vec<_> = sparse_ac.find_iter(black_box(sparse.as_bytes())).collect();
        checksum(black_box(&matches))
    });
    measure("sparse_no_prefilter", 20, || {
        let matches: Vec<_> = sparse_contiguous_no_prefilter
            .find_iter(black_box(&sparse))
            .collect();
        checksum(black_box(&matches))
    });
    measure("byte_scan", 100, || {
        black_box(sparse.as_bytes())
            .iter()
            .fold(0u64, |sum, byte| sum.wrapping_add(*byte as u64))
    });
    measure("overlap_find", 20, || {
        let matches: Vec<_> = high_ac.find_overlapping_iter(black_box(&high)).collect();
        checksum(black_box(&matches))
    });
}
