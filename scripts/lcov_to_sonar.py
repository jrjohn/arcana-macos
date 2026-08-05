#!/usr/bin/env python3
"""Convert an lcov report into the SonarQube generic test-coverage XML format.

Usage: lcov_to_sonar.py <coverage.lcov> <coverage-report.xml>

Paths are normalized to be repo-relative (from `Sources/…`) so they match the
sources SonarQube analyzes, regardless of the absolute path llvm-cov recorded.
"""
import sys


def normalize(path: str) -> str:
    marker = "/Sources/"
    if marker in path:
        return "Sources/" + path.split(marker, 1)[1]
    return path


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: lcov_to_sonar.py <in.lcov> <out.xml>", file=sys.stderr)
        return 2
    lcov_path, out_path = sys.argv[1], sys.argv[2]

    files: dict[str, dict[int, bool]] = {}
    current = None
    with open(lcov_path, encoding="utf-8", errors="replace") as handle:
        for raw in handle:
            line = raw.strip()
            if line.startswith("SF:"):
                current = normalize(line[3:])
                files.setdefault(current, {})
            elif line.startswith("DA:") and current is not None:
                parts = line[3:].split(",")
                lineno = int(parts[0])
                hits = int(parts[1]) if len(parts) > 1 else 0
                files[current][lineno] = files[current].get(lineno, False) or hits > 0
            elif line == "end_of_record":
                current = None

    with open(out_path, "w", encoding="utf-8") as out:
        out.write('<coverage version="1">\n')
        for path in sorted(files):
            # Only report source files (Tests / build output are excluded upstream).
            if not path.startswith("Sources/"):
                continue
            out.write(f'  <file path="{path}">\n')
            for lineno in sorted(files[path]):
                covered = "true" if files[path][lineno] else "false"
                out.write(f'    <lineToCover lineNumber="{lineno}" covered="{covered}"/>\n')
            out.write("  </file>\n")
        out.write("</coverage>\n")

    print(f"lcov_to_sonar: wrote {out_path} ({len(files)} files)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
