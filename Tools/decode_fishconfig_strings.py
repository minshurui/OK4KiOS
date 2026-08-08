#!/usr/bin/env python3
"""Decode Java short-array XOR strings without loading Android/JAR."""
from __future__ import annotations
import argparse
import re
from pathlib import Path

ARRAY_RE = re.compile(r"(f\d+short)\s*=\s*(?:new short\[\])?\s*\{([^}]*)\}", re.S)
CALL_RE = re.compile(
    r"C\d+\.(m(?:30|33|39|47|51|55|56))\((f\d+short),\s*(\d+),\s*(\d+),\s*(\d+)\)"
)


def decode(source: str) -> list[tuple[int, str, str, str]]:
    arrays = {
        name: [int(value) for value in re.findall(r"-?\d+", body)]
        for name, body in ARRAY_RE.findall(source)
    }
    if not arrays:
        raise ValueError("no f<id>short array found")
    output = []
    for line_number, line in enumerate(source.splitlines(), 1):
        for call in CALL_RE.finditer(line):
            method, array_name, offset, length, key = call.groups()
            values = arrays.get(array_name)
            if values is None:
                continue
            start, size, xor_key = int(offset), int(length), int(key)
            if start + size > len(values):
                raise ValueError(f"{array_name}[{start}:{start + size}] exceeds {len(values)} values")
            text = "".join(chr((value & 0xFFFF) ^ xor_key) for value in values[start:start + size])
            output.append((line_number, method, array_name, text))
    return output


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("--from-line", type=int, default=1)
    parser.add_argument("--to-line", type=int, default=10**9)
    args = parser.parse_args()
    for line, method, array_name, text in decode(args.source.read_text(encoding="utf-8")):
        if args.from_line <= line <= args.to_line:
            print(f"{line}\t{method}\t{array_name}\t{text}")


if __name__ == "__main__":
    main()
