#!/usr/bin/env python3
"""Decode moyu.fucking string-pool classes (C0040/C0043/C0044/C0050/C0053/C0070/C0075/C0086...)
without loading Android/JAR.

Each pool class has three n() variants:
  n(int)             -> static value (short[], String, int, ...) via switch (K1 ^ var0)
  n(int, Object)     -> field reference   via switch (K2 ^ var0), invoked by m130
  n(int, Object, Obj)-> method reference  via switch (K3 ^ var0), invoked by m131

The byte[]-literal strings are UTF-8 (negative bytes are & 0xFF).
"""
from __future__ import annotations
import re
import sys
from pathlib import Path

POOL_DIR = Path("/root/OK4K-debug-assets/fish-spider/sources/moyu/fucking")

BYTES_RE = re.compile(r"new byte\[\]\{(.*?)\}", re.S)


def decode_bytes_literal(body: str) -> str:
    values = [int(v) for v in re.findall(r"-?\d+", body)]
    return bytes(v & 0xFF for v in values).decode("utf-8", errors="replace")


def parse_pool(path: Path) -> dict:
    """Return {variant: {var0: (kind, payload)}} where payload for method refs is
    (class_name, method_name, ret_type, [param_types]) and for fields is
    (class_name, field_name, field_type)."""
    src = path.read_text(encoding="utf-8")
    result = {}
    switch_headers = list(re.finditer(r"switch\s*\(\s*(\d+)\s*\^\s*var0\s*\)", src))
    variants = ["3", "2", "1"]
    for idx, m in enumerate(switch_headers):
        variant = variants[idx] if idx < len(variants) else str(idx)
        xor = int(m.group(1))
        # find the switch block
        start = m.end()
        # balance braces
        depth = 0
        end = start
        for i in range(start, len(src)):
            if src[i] == "{":
                depth += 1
            elif src[i] == "}":
                depth -= 1
                if depth == 0:
                    end = i
                    break
        block = src[start:end]
        cases = {}
        for cm in re.finditer(r"case\s+(\d+):(.*?)(?=case\s+\d+:|$)", block, re.S):
            case_val = int(cm.group(1))
            body = cm.group(2)
            var0 = case_val ^ xor
            cases[var0] = body
        result[variant] = cases
    return result


def resolve_byte_strings(cases: dict) -> dict:
    """For each var0, extract the object construction (m133/m132/new String/new int)."""
    out = {}
    for var0, body in cases.items():
        m133 = re.search(r"C0030\.m133\((.*?)\);", body, re.S)
        if m133:
            args = [a.strip() for a in split_top_level(m133.group(1))]
            if len(args) >= 2:
                cls = decode_bytes_literal(args[0])
                name = decode_bytes_literal(args[1])
                ret = decode_bytes_literal(args[2]) if len(args) > 2 else ""
                params = [decode_bytes_literal(a) for a in args[3:]]
                out[var0] = ("method", cls, name, ret, params)
                continue
        m132 = re.search(r"C0030\.m132\((.*?)\);", body, re.S)
        if m132:
            args = [a.strip() for a in split_top_level(m132.group(1))]
            if len(args) >= 2:
                cls = decode_bytes_literal(args[0])
                name = decode_bytes_literal(args[1])
                ftype = decode_bytes_literal(args[2]) if len(args) > 2 else ""
                out[var0] = ("field", cls, name, ftype)
                continue
        mnew = re.search(r"object = new String\(new byte\[\]\{(.*?)\}\)", body, re.S)
        if mnew:
            out[var0] = ("value", decode_bytes_literal(mnew.group(1)))
            continue
        mstr = re.search(r"object = new String\(new byte\[0\]\)", body)
        if mstr:
            out[var0] = ("value", "")
            continue
        out[var0] = ("unknown", body.strip()[:120])
    return out


def split_top_level(s: str) -> list[str]:
    parts = []
    depth = 0
    cur = []
    for ch in s:
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        if ch == "," and depth == 0:
            parts.append("".join(cur))
            cur = []
        else:
            cur.append(ch)
    if cur:
        parts.append("".join(cur))
    return parts


def main() -> None:
    pools = {}
    for path in sorted(POOL_DIR.glob("C*.java")):
        try:
            parsed = parse_pool(path)
        except Exception as exc:  # noqa: BLE001
            print(f"# {path.name}: parse error {exc}", file=sys.stderr)
            continue
        if not parsed:
            continue
        resolved = {variant: resolve_byte_strings(cases) for variant, cases in parsed.items()}
        pools[path.stem] = resolved
        n3 = len(resolved.get("3", {}))
        n2 = len(resolved.get("2", {}))
        n1 = len(resolved.get("1", {}))
        print(f"# {path.name}: n3={n3} n2={n2} n1={n1}")

    import json

    out = {
        name: {
            "3": {str(k): v for k, v in variants.get("3", {}).items()},
            "2": {str(k): v for k, v in variants.get("2", {}).items()},
            "1": {str(k): v for k, v in variants.get("1", {}).items()},
        }
        for name, variants in pools.items()
    }
    dump_path = Path(__file__).with_name("moyu_pools.json")
    dump_path.write_text(json.dumps(out, ensure_ascii=False, indent=1))
    print(f"# wrote {dump_path}")


if __name__ == "__main__":
    main()
