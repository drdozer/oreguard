#!/usr/bin/env python3
"""Crude Lua block-balance checker (openers vs end/until) for driver files.

Handles -- line comments, --[[ ]] block comments, quoted strings, and
suppresses the `do` that belongs to for/while. Not a full parser; catches
the missing-`end` class of errors before burning a Factorio run.
"""
import re
import sys


def check(path):
    src = open(path).read()
    # remove block comments first
    src = re.sub(r"--\[(=*)\[.*?\]\1\]", "", src, flags=re.S)
    opens, ends = 0, 0
    pending_for_do = 0  # suppress N leading `do` on this line
    for line in src.splitlines():
        code = line.split("--", 1)[0]
        toks = re.findall(r"[A-Za-z_]+|\"", code)
        i = 0
        in_str = False
        for tok in toks:
            if tok == '"':
                in_str = not in_str
                continue
            if in_str:
                continue
            if tok in ("function", "if", "for", "while", "repeat", "do"):
                if tok == "do":
                    if pending_for_do > 0:
                        pending_for_do -= 1
                        continue
                    opens += 1
                else:
                    opens += 1
                if tok in ("for", "while"):
                    pending_for_do += 1
        pending_for_do = 0  # only same-line associations
        ends += len(re.findall(r"\b(end|until)\b", line.split("--", 1)[0]))
    return opens, ends


if __name__ == "__main__":
    for p in sys.argv[1:]:
        o, e = check(p)
        delta = o - e
        verdict = "OK" if delta == 0 else f"MISMATCH ({'+' if delta > 0 else ''}{delta})"
        print(f"{p}: opens={o} ends={e} -> {verdict}")