#!/usr/bin/env python3
"""OreGuard rail-probe runner (throwaway diagnostic rig).

Launches a windowed client on the railprobe USER scenario (instance-B
semantics: oreguard enabled, rail toggle flipped ON via the instance-b
mod-settings.dat seeding), polls factorio-current.log for PROBE-DONE,
terminates the client, and prints every PROBE-* line.
"""
import importlib.util
import json
import pathlib
import shutil
import subprocess
import time

HERE = pathlib.Path(__file__).resolve().parent
SCRATCH = HERE / "scratch"


def load_run_matrix():
    spec = importlib.util.spec_from_file_location(
        "runmatrix", HERE / "run-matrix.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def main():
    rm = load_run_matrix()
    root = rm.game_root()
    bin_path = rm.game_bin(root)
    inst = rm.setup_instance("b", root)          # copy+flip of instance-a state
    # drop the carrier matrix mod — its driver would fight the probe
    (inst / "mods" / "mod-list.json").write_text(json.dumps({
        "mods": [{"name": "base", "enabled": True},
                 {"name": "oreguard", "enabled": True}]}))
    # lay the probe scenario into the instance write-data
    sc = inst / "scenarios" / "railprobe"
    sc.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(HERE / "railprobe" / "control.lua", sc / "control.lua")
    (sc / "info.json").write_text("{}")

    cur_log = inst / "factorio-current.log"
    if cur_log.is_file():
        cur_log.rename(inst / "factorio-previous.log")

    cmd = [str(bin_path), "-c", str(inst / "config" / "config.ini"),
           "--load-scenario", "railprobe"]
    print(f"launching probe: {' '.join(cmd)}")
    proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL)
    deadline = time.time() + 300
    done = False
    while time.time() < deadline:
        if cur_log.is_file() and "PROBE-DONE" in cur_log.read_text(errors="replace"):
            done = True
            break
        if proc.poll() is not None:
            print(f"client exited early rc={proc.returncode}")
            break
        time.sleep(1)
    try:
        proc.terminate()
        proc.wait(timeout=10)
    except Exception:
        proc.kill()
    print(f"probe {'complete' if done else 'TIMED OUT'}")
    if cur_log.is_file():
        for line in cur_log.read_text(errors="replace").splitlines():
            if "PROBE-" in line or "ScriptError" in line or "Error " in line:
                print(line)


if __name__ == "__main__":
    main()