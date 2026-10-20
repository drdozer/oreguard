#!/usr/bin/env python3
"""OreGuard behavior-matrix runner (see testing/PLAN.md).

Sets up a hermetic scratch instance, launches the full client binary as a
HEADLESS dedicated server on the matrix scenario, waits for
script-output/oreguard-matrix.json, quits via RCON, and exits non-zero on
any unpassed case.

  python3 testing/run-matrix.py a            # full matrix, windowed (game.player exists)
  python3 testing/run-matrix.py b a-style    # rail toggle ON subset
  python3 testing/run-matrix.py a --headless # robot-only; player cases auto-skip

Standalone by design: parses devctl.conf only; no devctl verbs, no venv —
safe to run while other agents hold lib/ in flight.
"""

import json
import os
import re

import pathlib
import shutil
import socket
import struct
import subprocess
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parents[3]   # superproject (testing -> oreguard -> mods -> root)
MOD = ROOT / "mods" / "oreguard"
CARRIER = MOD / "testmods" / "oreguard-matrix"
SCRATCH = MOD / "testing" / "scratch"
RESULTS = "oreguard-matrix.json"
RCON_PORT = 27016
RCON_PASSWORD = "oreguard-matrix"
TIMEOUT_SECONDS = 600

SERVER_SETTINGS = {
    "name": "oreguard-matrix",
    "description": "",
    "tags": [],
    "max_players": 0,
    "visibility": {"public": False, "lan": False},
    "auto_pause": False,
    "only_admins_can_pause_the_game": False,
    "game_password": "",
    "require_user_verification": False,
}

MOD_LIST = {
    "mods": [
        {"name": "base", "enabled": True},
        {"name": "oreguard", "enabled": True},
        {"name": "oreguard-matrix", "enabled": True},
    ]
}


def game_root() -> pathlib.Path:
    conf = ROOT / "devctl.conf"
    if conf.is_file():
        for line in conf.read_text().splitlines():
            line = line.strip()
            if line.startswith("FACTORIO_DLC_PATH="):
                return pathlib.Path(line.split("=", 1)[1].strip().strip('"'))
    env = os.environ.get("FACTORIO_DLC_PATH")
    if env:
        return pathlib.Path(env)
    sys.exit("no FACTORIO_DLC_PATH — set it in devctl.conf or the environment")


def game_bin(root: pathlib.Path) -> pathlib.Path:
    for sub in ("bin/x64/factorio", "bin/x64/factorio.exe"):
        candidate = root / sub
        if candidate.is_file():
            return candidate
    sys.exit(f"factorio binary not found under {root}")


def setup_instance(name: str, root: pathlib.Path):
    inst = SCRATCH / f"instance-{name}"
    (inst / "script-output").mkdir(parents=True, exist_ok=True)
    (inst / "config").mkdir(parents=True, exist_ok=True)
    (inst / "mods").mkdir(parents=True, exist_ok=True)

    cfg = inst / "config" / "config.ini"
    # Derive from the MAIN signed-in client config when available: kills the
    # update/login modals that otherwise block windowed runs (they can only
    # be dismissed by a human). [path] lines are patched to the instance.
    main_cfg = root.parent / "config" / "config.ini"   # <install>/config/…
    # careful: root IS the install dir; config lives at <install>/config
    main_cfg = root / "config" / "config.ini"
    if main_cfg.is_file():
        text = main_cfg.read_text()
        if "[path]" in text:
            text = re.sub(r"(?m)^read-data=.*$", f"read-data={root / 'data'}", text)
            if re.search(r"(?m)^write-data=", text):
                text = re.sub(r"(?m)^write-data=.*$", f"write-data={inst}", text)
            else:
                text += f"\nwrite-data={inst}\n"
        else:
            text += f"\n[path]\nread-data={root / 'data'}\nwrite-data={inst}\n"
        # no update/login prompts in a testing loop
        text = re.sub(r"(?m)^check-updates=.*$", "", text)
        if "[other]" in text:
            text = re.sub(r"(?m)^(\[other\]\n)", r"\1check-updates=false\n", text, count=1)
        else:
            text += "\n[other]\ncheck-updates=false\n"
        cfg.write_text(text)
    else:
        if not cfg.is_file():
            cfg.write_text(
                "[path]\n"
                f"read-data={root / 'data'}\n"
                f"write-data={inst}\n"
            )
    (inst / "server-settings.json").write_text(json.dumps(SERVER_SETTINGS))
    (inst / "mods" / "mod-list.json").write_text(json.dumps(MOD_LIST))

    for link, target in (("oreguard", MOD / "mod"), ("oreguard-matrix", CARRIER)):
        dest = inst / "mods" / link
        if dest.is_symlink() or dest.exists():
            dest.unlink()
        dest.symlink_to(target.resolve())

    # startup settings persist in mod-settings.dat (session-2 lesson). The
    # engine writes the file carrying the mod's DEFAULTS on first run — for
    # instance B we patch the known boolean after instance a has run. For
    # BOTH instances a stale file must not survive from a previous round.
    dat = inst / "mods" / "mod-settings.dat"
    if name == "a":
        if dat.exists():
            dat.unlink()
    else:
        src = SCRATCH / "instance-a" / "mods" / "mod-settings.dat"
        if not src.is_file():
            sys.exit("instance b needs instance a's written mod-settings.dat — run instance a first")
        shutil.copyfile(src, dat)
        flip_rail_toggle(dat)
    return inst


def flip_rail_toggle(dat: pathlib.Path):
    """Turn oreguard-allow-ground-rail's stored boolean true, in place.

    Layout (verified 2026-10-20 by hexdump): setting names are length-prefixed
    strings; each carries a 'value' key whose bool serializes as
    b"\\x01\\x00\\x00\\x00" (false) / b"\\x01\\x00\\x01\\x00" (true). The
    scenario re-asserts the seeded value at init, so a failed patch fails the
    run loudly instead of silently testing the wrong branch.
    """
    blob = bytearray(dat.read_bytes())
    needle = b"oreguard-allow-ground-rail"
    pos = blob.find(needle)
    if pos < 0:
        sys.exit("patch failed: setting name not found in mod-settings.dat")
    vpos = blob.find(b"value", pos)
    if vpos < 0:
        sys.exit("patch failed: 'value' key not found after the setting name")
    payload = vpos + len(b"value") + 2  # [01][00][payload][00]
    if blob[payload] not in (0, 1):
        sys.exit(f"patch failed: unexpected bool payload 0x{blob[payload]:02x}")
    blob[payload] = 1
    dat.write_bytes(bytes(blob))
    print(f"patched {dat}: oreguard-allow-ground-rail -> true")


# --- RCON client (docs/testing.md §7, dependency-free, verified pattern) ----

def pkt(pid, ptype, body):
    d = struct.pack("<ii", pid, ptype) + body.encode() + b"\x00\x00"
    return struct.pack("<i", len(d)) + d


def read_pkt(s):
    ln = struct.unpack("<i", s.recv(4))[0]
    buf = b""
    while len(buf) < ln:
        chunk = s.recv(ln - len(buf))
        if not chunk:
            break
        buf += chunk
    _rid, rtype = struct.unpack("<ii", buf[:8])
    return rtype, buf[8:-2].decode(errors="replace")


def rcon_quit(port, password):
    for _ in range(30):
        try:
            s = socket.create_connection(("127.0.0.1", port), timeout=5)
            s.sendall(pkt(1, 3, password))
            if read_pkt(s)[0] != 2:
                print("rcon: auth failed (server still warming up?)")
                s.close(); time.sleep(2); continue
            s.sendall(pkt(2, 2, "/quit"))
            read_pkt(s)
            s.close()
            return True
        except OSError:
            time.sleep(2)
    return False


def run_instance(name, root, bin_path, windowed=True, lab=None, leave_open=False):
    inst = setup_instance(name, root)
    out = inst / "script-output" / RESULTS
    if out.exists():
        out.unlink()
    cur_log = inst / "factorio-current.log"
    # rotate stale logs — the poll must only ever see THIS run's results
    if cur_log.is_file():
        cur_log.rename(inst / "factorio-previous.log")
    print(f"--- instance {name}: {inst}")

    if lab:
        # canonical fixture location: testing/scratch/saves/<name>.zip
        # (tracked); instance saves self-migrate into it on first use.
        save = SCRATCH / "saves" / f"{lab}.zip"
        local_save = inst / "saves" / f"{lab}.zip"
        if not save.is_file() and local_save.is_file():
            save.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(local_save, save)
            print(f"migrated {local_save} -> {save} (tracked fixture)")
        if not save.is_file():
            sys.exit(f"curated save not found: {save} — run prep + editor first (LAB-WORLD.md)")
        if local_save.is_file() and save.stat().st_mtime > local_save.stat().st_mtime:
            shutil.copyfile(save, local_save)  # instance copy refreshed from canonical
        print(f"mode: windowed, curated save {save.name}")
        cmd = [str(bin_path), "-c", str(inst / "config" / "config.ini"),
               "--load-game", str(save)]
    else:
        cmd = [str(bin_path), "-c", str(inst / "config" / "config.ini"),
               "--load-scenario", "oreguard-matrix/oreguard-matrix"]
    if windowed:
        # windowed singleplayer: the local player EXISTS, so the real player
        # path (on_built_entity / tiles / cursor builds) is exercisable. The
        # runner polls script-output and terminates the process when done.
        print("mode: windowed singleplayer (a game window will open briefly)")
        cmd += ["--rcon-port", str(RCON_PORT), "--rcon-password", RCON_PASSWORD]
    else:
        cmd += ["--start-server-load-scenario", "oreguard-matrix/oreguard-matrix",
                "--server-settings", str(inst / "server-settings.json")]

    proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    deadline = time.time() + TIMEOUT_SECONDS
    def poll_log():
        if not cur_log.is_file():
            return None
        body = cur_log.read_text(errors="replace")
        if "MATRIX-RESULTS" not in body:
            return None
        recs = []
        for c in body.splitlines():
            if "MATRIX-CASE " in c:
                try: recs.append(json.loads(c.split("MATRIX-CASE ", 1)[1]))
                except Exception: pass
        summary = [c for c in body.splitlines() if "MATRIX-RESULTS" in c][-1]
        data = {"done": True, "records": recs, "summary": summary}
        for k in ("passed", "failed", "skipped"):
            data[k] = int(summary.split(k + "=")[1].split()[0]) if (k + "=") in summary else 0
        return data
    try:
        while time.time() < deadline:
            data = poll_log()
            if data is not None:
                if windowed:
                    try:
                        proc.terminate(); proc.wait(timeout=10)
                    except Exception:
                        proc.kill()
                else:
                    rcon_quit(RCON_PORT, RCON_PASSWORD)
                return data
            if proc.poll() is not None:
                print(f"server exited early (rc={proc.returncode}) — check "
                      f"{inst}/logs/")
                return None
            if out.is_file():
                try:
                    data = json.loads(out.read_text())
                except json.JSONDecodeError:
                    time.sleep(1); continue   # partial write — retry
                if data.get("done"):
                    if windowed:
                        # local session: no server to /quit — stop the process
                        try:
                            proc.terminate()
                            proc.wait(timeout=10)
                        except Exception:
                            proc.kill()
                    else:
                        rcon_quit(RCON_PORT, RCON_PASSWORD)
                    return data
                # partial (phase) write — keep waiting
            time.sleep(2)
        print(f"TIMEOUT after {TIMEOUT_SECONDS}s waiting for {out}")
        return None
    finally:
        if lab:
            canonical = SCRATCH / "saves" / f"{lab}.zip"
            local_save = inst / "saves" / f"{lab}.zip"
            if local_save.is_file():
                canonical.parent.mkdir(parents=True, exist_ok=True)
                if not canonical.is_file() or canonical.stat().st_mtime != local_save.stat().st_mtime:
                    shutil.copyfile(local_save, canonical)
                    print(f"canonical save updated: {canonical} (commit it)")
        try:
            if proc.poll() is None:
                subprocess.run(["pkill", "-f", str(bin_path)], check=False)
        except Exception:
            pass


def report(data: dict, expect_rail_on: bool):
    seed = next((r for r in data.get("records", []) if r["id"] == "seed-rail-toggle"), None)
    if seed and (seed.get("got") == "on") != expect_rail_on:
        print(f"seed mismatch: instance expected rail toggle "
              f"{expect_rail_on and 'on' or 'off'}, got {seed.get('got')!r} — "
              f"the mod-settings.dat seeding did not take; not a mod bug")
        return 1
    failed = data.get("failed", 0)
    skipped = data.get("skipped", 0)
    print(f"MATRIX passed={data.get('passed', 0)} failed={failed} skipped={skipped}")
    for line in data.get("failures", []):
        print("  FAIL", line)
    for rec in data.get("records", []):
        if rec.get("got") == "skip":
            print("  SKIP", rec["id"], "-", rec.get("detail", ""))
    return 0 if failed == 0 else 1


def main():
    argv = sys.argv[1:]
    if "prep" in argv:
        # windowed session for the map-editor pass; runner returns at once
        root = game_root(); bin_path = game_bin(root)
        inst = setup_instance("a", root)
        subprocess.Popen([str(bin_path), "-c", str(inst / "config" / "config.ini"),
                          "--load-scenario", "oreguard-matrix/oreguard-matrix"],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        print("instance session launched for editing. Adjust to LAB-WORLD.md, "
              "save as 'lab', quit. Then: python3 run-matrix.py a --lab")
        return
    windowed = "--headless" not in argv
    lab = None
    if "--lab" in argv:
        argv = [a for a in argv if a != "--lab"]
        lab = "lab"
    args = [a for a in argv if not a.startswith("--")] or ["a"]
    root = game_root(); bin_path = game_bin(root)
    print(f"factorio: {bin_path}")
    rc = 0
    for name in args:
        expect = name == "b"
        data = run_instance(name, root, bin_path, windowed=windowed, lab=lab)
        if data is None:
            rc = 1
            continue
        rc = max(rc, report(data, expect))
    sys.exit(rc or 0)


if __name__ == "__main__":
    main()