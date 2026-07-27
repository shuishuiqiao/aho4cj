#!/usr/bin/env python3

import csv
import html
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path


OPERATIONS = [
    ("build_1000", "构建 1,000 个模式"),
    ("sparse_find", "稀疏字符串搜索"),
    ("sparse_find_bytes", "稀疏字节搜索"),
    ("byte_scan", "纯字节遍历"),
    ("overlap_find", "高重叠搜索并收集"),
]


def read_results(path: Path) -> tuple[dict[str, int], str]:
    values: dict[str, int] = {}
    metadata = ""
    with path.open(newline="", encoding="utf-8") as source:
        for row in csv.reader(source):
            if not row:
                continue
            if row[0] == "meta":
                metadata = ",".join(row[1:])
            elif len(row) == 3:
                values[row[0]] = int(row[1])
    return values, metadata


def main() -> None:
    if len(sys.argv) != 5:
        raise SystemExit("用法: report.py RUST_CSV CANGJIE_CSV OUTPUT_DIR COMMIT")
    rust_path = Path(sys.argv[1])
    cangjie_path = Path(sys.argv[2])
    output = Path(sys.argv[3])
    commit = sys.argv[4]
    rust, rust_meta = read_results(rust_path)
    cangjie, cangjie_meta = read_results(cangjie_path)
    missing = [key for key, _ in OPERATIONS if key not in rust or key not in cangjie]
    if missing:
        raise SystemExit(f"基准缺少结果: {', '.join(missing)}")
    if rust_meta != cangjie_meta:
        raise SystemExit("Rust 与仓颉基准输入或校验和不一致")

    output.mkdir(parents=True, exist_ok=True)
    shutil.copy2(rust_path, output / "rust.csv")
    shutil.copy2(cangjie_path, output / "cangjie.csv")
    rows = []
    for key, label in OPERATIONS:
        rust_ms = rust[key] / 1_000_000
        cangjie_ms = cangjie[key] / 1_000_000
        rows.append(
            "<tr>"
            f"<td>{html.escape(label)}</td>"
            f"<td>{rust_ms:.4f} ms</td>"
            f"<td>{cangjie_ms:.4f} ms</td>"
            f"<td>{cangjie_ms / rust_ms:.2f}x</td>"
            "</tr>"
        )

    generated = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    document = f"""<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>aho4cj 性能基准</title>
  <style>
    body {{ max-width: 960px; margin: 40px auto; padding: 0 20px; font: 16px/1.6 system-ui, sans-serif; color: #202124; }}
    table {{ width: 100%; border-collapse: collapse; margin: 24px 0; }}
    th, td {{ border: 1px solid #c8cdd3; padding: 8px 12px; text-align: right; }}
    th:first-child, td:first-child {{ text-align: left; }}
    code {{ background: #f1f3f4; padding: 2px 4px; }}
  </style>
</head>
<body>
  <nav><a href="../">报告首页</a> · <a href="../coverage/">覆盖率</a></nav>
  <h1>aho4cj 性能基准</h1>
  <p>由 GitHub Actions 在同一 runner 上依次运行 Rust 1.89 与 Cangjie 1.1.3 的固定镜像生成。</p>
  <table>
    <thead><tr><th>操作</th><th>Rust</th><th>aho4cj</th><th>仓颉/Rust</th></tr></thead>
    <tbody>{''.join(rows)}</tbody>
  </table>
  <p>输入：<code>{html.escape(rust_meta)}</code></p>
  <p>提交：<code>{html.escape(commit)}</code><br>生成时间：{generated}</p>
  <p><a href="rust.csv">Rust 原始 CSV</a> · <a href="cangjie.csv">仓颉原始 CSV</a></p>
  <p>共享 CI 主机存在计时抖动；结果适合发现数量级回归，不应替代固定硬件上的严格性能评测。</p>
</body>
</html>
"""
    (output / "index.html").write_text(document, encoding="utf-8")


if __name__ == "__main__":
    main()
