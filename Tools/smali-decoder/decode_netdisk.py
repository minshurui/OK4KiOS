#!/usr/bin/env python3
"""Decode all URL/field/header strings from a netdisk core smali class (short-array XOR).

Usage: python3 decode_netdisk.py <smali-dir> <smali-class-path> [--minlen 8]
"""
from __future__ import annotations
import re
import sys
from pathlib import Path

ANCHORS = "/ha vutcbrspmlgodxw".replace(" ", "")
PREFIXES = (
    "https", "http", "/v1", "/api", "account", "api.", "user", "file", "v1/",
    "Bearer", "application", "www.", "pan.", "drive", "open", "login", "oauth",
    "token", "refresh", "share", "restore", "task", "search", "mobile", "passport",
    "get_", "create_", "biz", "nd.", "pc-", "interface", "authorize", "auth",
    "x-", "X-", "uc", "UA", "User-Agent", "Referer", "Origin", "Content-",
    "Accept", "Cookie", "sign", "expire", "status", "success", "code", "msg",
    "data", "list", "size", "page", "parent", "dir", "fid", "pdir", "download",
    "preview", "thumbnail", "captcha", "sms", "verify", "logout", "grant",
    "scope", "client", "secret", "callback", "redirect", "app_id", "appid",
)


def extract_short_arrays(path: Path) -> dict[str, list[int]]:
    src = path.read_text(encoding="utf-8", errors="replace")
    lines = src.splitlines()
    arrays: dict[str, list[int]] = {}
    for m in re.finditer(r"fill-array-data\s+v\d+,\s*:(\w+)", src):
        label = m.group(1)
        if label in arrays:
            continue
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
                    arrays[label] = vals
                break
    return arrays


def main() -> None:
    smali = Path(sys.argv[1])
    cls = sys.argv[2]
    minlen = int(sys.argv[4]) if len(sys.argv) > 4 and sys.argv[3] == "--minlen" else 8
    path = smali / cls
    if not path.exists():
        print(f"not found: {path}")
        sys.exit(1)
    arrays = extract_short_arrays(path)
    print(f"# {cls}: {[(k, len(v)) for k, v in arrays.items()]}")
    seen: set[tuple[int, str]] = set()
    out: list[tuple[int, int, str]] = []
    for label, vals in arrays.items():
        n = len(vals)
        for off in range(n):
            for exp in ANCHORS:
                key = (vals[off] & 0xFFFF) ^ ord(exp)
                s = ""
                i = 0
                while off + i < n:
                    c = (vals[off + i] & 0xFFFF) ^ (key & 0xFFFF)
                    if not (32 <= c < 127):
                        break
                    s += chr(c)
                    i += 1
                low = s.lower()
                if (
                    len(s) >= minlen
                    and s.isprintable()
                    and any(low.startswith(p) or low.startswith(p.lower()) for p in PREFIXES)
                    and (off, s) not in seen
                ):
                    seen.add((off, s))
                    out.append((off, key, s))
                    break
    for off, key, s in sorted(out):
        print(f"  off={off:5d} key=0x{key:04x} {s!r}")


if __name__ == "__main__":
    main()
