#!/usr/bin/env python3
"""Decode all string-pool call sites in a jadx netdisk core (method + offset -> string)."""
from __future__ import annotations
import re
import sys
from pathlib import Path

N_CALL_RE = re.compile(r"n\((\d+)\)")


def extract_short_arrays(smali: Path) -> list[list[int]]:
    src = smali.read_text(encoding="utf-8", errors="replace")
    lines = src.splitlines()
    arrays: list[list[int]] = []
    for m in re.finditer(r"fill-array-data\s+v\d+,\s*:(\w+)", src):
        label = m.group(1)
        for i, l in enumerate(lines):
            if l.strip() == f":{label}":
                j = i + 1
                buf = []
                while j < len(lines):
                    buf.append(lines[j])
                    if ".end array-data" in lines[j]:
                        break
                    j += 1
                am = re.search(
                    r"\.array-data\s+(\d+)\s*\n(.*?)\n\s*\.end array-data",
                    "\n".join(buf), re.S,
                )
                if not am:
                    break
                vals = []
                for ln in am.group(2).splitlines():
                    mm = re.match(r"\s*(-?0x[0-9a-fA-F]+|-?\d+)[tTs]?", ln)
                    if mm:
                        vals.append(int(mm.group(1), 0))
                if len(vals) > 50:
                    arrays.append(vals)
                break
    return arrays


ANCHORS = "h/avuctbsprlmdoqxw"
def brute(vals, off, length):
    n = len(vals)
    for exp in ANCHORS:
        key = (vals[off] & 0xFFFF) ^ ord(exp)
        s = "".join(chr((vals[off + i] & 0xFFFF) ^ key) for i in range(min(length, 50)) if off + i < n)
        if s and all(32 <= ord(c) < 127 for c in s):
            full = "".join(chr((vals[off + i] & 0xFFFF) ^ key) for i in range(length) if off + i < n)
            printable = sum(1 for c in full[:120] if 32 <= ord(c) < 127)
            if printable < len(full[:120]) * 0.7:
                continue
            return key, full
    return None


FULL_RE = re.compile(
    r"\(short\[\]\)\s*[A-Za-z0-9_.]*\.?n\((\d+)\)\s*,\s*(\d+)\s*,(.*?),\s*(\d+)\}\)"

)


def parse_calls(src: str):
    """Yield (line_no, method, arr_id, offset, length)."""
    lines = src.splitlines()
    method = ""
    for ln, line in enumerate(lines, 1):
        mm = re.search(r"public\s+(?:final\s+|static\s+)*[\w<>\[\].]+\s+(\w+)\s*\(", line)
        if mm:
            method = mm.group(1)
        for m in FULL_RE.finditer(line):
            arr_id, offset, _expr, length = m.groups()
            yield ln, method, arr_id, int(offset), int(length)


def main() -> None:
    jadx = Path(sys.argv[1])
    smali_dir = Path(sys.argv[2])
    src = jadx.read_text(encoding="utf-8", errors="replace")
    # load all short arrays from the matching smali class (same basename)
    base = jadx.stem
    # find smali file by rename map: search all merge/a smali for matching method refs
    candidates = sorted((smali_dir / "com/github/catvod/spider/merge/a").glob("*.smali"))
    all_arrays: list[list[int]] = []
    for f in candidates:
        try:
            arrs = extract_short_arrays(f)
        except Exception:  # noqa: BLE001
            continue
        all_arrays.extend(arrs)

    calls = list(parse_calls(src))
    print(f"# {jadx.name}: {len(calls)} call sites")
    seen = set()
    for ln, method, arr_id, off, length in calls:
        if (off, length) in seen:
            continue
        for vals in all_arrays:
            if off + length > len(vals):
                continue
            r = brute(vals, off, length)
            if r:
                key, s = r
                seen.add((off, length))
                print(f"L{ln:5d} {method:30s} off={off:5d} len={length:4d} key=0x{key:04x} {s!r}")
                break


if __name__ == "__main__":
    main()
