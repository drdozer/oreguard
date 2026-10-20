#!/usr/bin/env python3
"""Regenerate the canonical lab save without a hand editing pass.

The level script (scenarios/oreguard-matrix) curates the full lab world on
fresh --load-scenario generation (LAB-WORLD.md: carves, purges resources
until empty, stamps fixtures + power island). This rig launches a windowed
session, waits for the curation to settle, RCON-saves `lab`, quits, and
adopts the save into the canonical testing/scratch/saves/lab.zip.

Sanity-checks the world state via a few quick greps of the log; the matrix
run afterwards (python3 testing/run-matrix.py a --lab) is the real gate.
"""
import importlib.util
import pathlib
import shutil
import socket
import struct
import subprocess
import time

HERE = pathlib.Path(__file__).resolve().parent
SCRATCH = HERE / "scratch"
CANONICAL = SCRATCH / "saves" / "lab.zip"
RCON_PORT = 27016
RCON_PASSWORD = "oreguard-matrix"


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
    _rid, rtype = struct.unpack("<ii", buf[:8])
    return rtype, buf[8:-2].decode(errors="replace")


def rcon(cmd, settle):
    for _ in range(30):
        try:
            s = socket.create_connection(("127.0.0.1", RCON_PORT), timeout=5)
            s.sendall(pkt(1, 3, RCON_PASSWORD))
            if read_pkt(s)[0] != 2:
                s.close(); time.sleep(1); continue
            s.sendall(pkt(2, 2, cmd))
            _, out = read_pkt(s)
            s.close()
            time.sleep(settle)
            return out or "(no output)"
        except OSError:
            time.sleep(1)
    return None


def load_run_matrix():
    spec = importlib.util.spec_from_file_location("runmatrix", HERE / "run-matrix.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def main():
    rm = load_run_matrix()
    root = rm.game_root()
    bin_path = rm.game_bin(root)
    inst = rm.setup_instance("a", root)
    (inst / "saves").mkdir(exist_ok=True)

    cur_log = inst / "factorio-current.log"
    if cur_log.is_file():
        cur_log.rename(inst / "factorio-previous.log")

    # headless server: the RCON path the runner itself relies on (windowed
    # single-player RCON is unproven; the first regen attempt silently kept
    # the stale save because no /save ever ran)
    cmd = [str(bin_path), "-c", str(inst / "config" / "config.ini"),
           "--start-server-load-scenario", "oreguard-matrix/oreguard-matrix",
           "--server-settings", str(inst / "server-settings.json"),
           "--rcon-port", str(RCON_PORT), "--rcon-password", RCON_PASSWORD]
    print("launching headless curated-fresh-generation session")
    proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    # wait for curation (fires at on_init), then give the machinery some slack
    settled = False
    deadline = time.time() + 180
    while time.time() < deadline:
        if cur_log.is_file() and "MATRIX-LAB-CURATED" in cur_log.read_text(errors="replace"):
            settled = True
            break
        if proc.poll() is not None:
            break
        time.sleep(0.5)
    if not settled:
        print("curation line never appeared; proceeding anyway")
    time.sleep(3)

    print("RCON /save lab:", rcon("/save lab", settle=4))

    new_save = inst / "saves" / "lab.zip"
    deadline = time.time() + 60
    while time.time() < deadline and not new_save.is_file():
        time.sleep(1)
    if not new_save.is_file():
        print("lab.zip not written; aborting (world session left open)")
        rcon("/quit", settle=2)
        proc.kill()
        return 1
    print(f"save written: {new_save} ({new_save.stat().st_size} bytes)")

    rcon("/quit", settle=2)
    for _ in range(30):
        if proc.poll() is not None:
            break
        time.sleep(1)
    if proc.poll() is None:
        proc.kill()

    CANONICAL.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(new_save, CANONICAL)
    print(f"canonical updated: {CANONICAL}")
    return 0


if __name__ == "__main__":
    import sys
    sys.exit(main())