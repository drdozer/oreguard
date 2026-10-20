#!/usr/bin/env python3
"""check-families.py — assert the family source of truth stays in sync.

OreGuard's allowances live once, in mod/families.lua (families, tier
compositions, tier values). Everything else mirrors it and can drift:

  * mod/locale/en/locale.cfg  [oreguard-family] display names per family
  * mod/settings.lua          oreguard-tier allowed_values == tier values

This checker fails loudly (exit 1) on drift. Zero dependencies; run from
anywhere:

    python3 tools/check-families.py            # paths relative to repo root
    devctl python run tools/check-families.py  # on the shared venv
"""

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
FAMILIES = ROOT / "mod" / "families.lua"
LOCALE = ROOT / "mod" / "locale" / "en" / "locale.cfg"
SETTINGS = ROOT / "mod" / "settings.lua"

errors: list[str] = []


def fail(msg: str) -> None:
    errors.append(msg)


fam_src = FAMILIES.read_text()

families: dict[str, set[str]] = {}
for m in re.finditer(r'\{\s*id\s*=\s*"([^"]+)"\s*,\s*types\s*=\s*\{([^}]*)\}\s*\}', fam_src):
    fid = m.group(1)
    types = set(re.findall(r'"([a-z0-9_\-]+)"', m.group(2)))
    families[fid] = types
if not families:
    fail("families.lua: no family definitions parsed")

tiers: dict[str, list[str]] = {}
tier_block = re.search(r"Families\.tiers\s*=\s*\{(.*?)\n\}", fam_src, re.S)
if tier_block:
    for m in re.finditer(r'\["([^"]+)"\]\s*=\s*\{([^}]*)\}', tier_block.group(1)):
        tiers[m.group(1)] = [x.strip().strip('"') for x in m.group(2).split(",") if x.strip()]
else:
    fail("families.lua: Families.tiers table not found")

tier_values: list[str] = re.findall(r'"([^"]+)"', re.search(r"Families\.tier_values\s*=\s*\{([^}]*)\}", fam_src).group(1))

# 1. every tier references a known family, and tier keys match tier_values
for tier, fids in tiers.items():
    for fid in fids:
        if fid not in families:
            fail(f"families.lua: tier '{tier}' references unknown family '{fid}'")
if not tier_values:
    fail("families.lua: Families.tier_values missing or unparseable")
if set(tiers) != set(tier_values):
    fail(f"families.lua: tier keys {sorted(tiers)} != Families.tier_values {sorted(tier_values)}")

# 2. settings.lua allowed_values == Families.tier_values (ordered)
sset = SETTINGS.read_text()
allowed = re.search(r'name\s*=\s*"oreguard-tier".*?allowed_values\s*=\s*\{(.*?)\}', sset, re.S)
if not allowed:
    fail("settings.lua: oreguard-tier allowed_values not found")
else:
    values = re.findall(r'"([^"]+)"', allowed.group(1))
    if values != tier_values:
        fail(f"settings.lua: allowed_values {values} != Families.tier_values {tier_values}")

# 3. locale [oreguard-family] covers every family
loc = LOCALE.read_text()
section = re.search(r"\[oreguard-family\]\n(.*?)(?:\n\[|\Z)", loc, re.S)
if not section:
    fail("locale.cfg: [oreguard-family] section missing")
else:
    keys = set(re.findall(r"^([a-z0-9_\-]+)\s*=", section.group(1), re.M))
    for fid in families:
        if fid not in keys:
            fail(f"locale.cfg: [oreguard-family] missing entry for family '{fid}'")
    extra = keys - set(families)
    if extra:
        fail(f"locale.cfg: [oreguard-family] has entries with no family: {sorted(extra)}")

if errors:
    print("check-families: FAIL")
    for e in errors:
        print(f"  - {e}")
    sys.exit(1)
print(f"check-families: OK ({len(families)} families, {len(tiers)} tiers)")