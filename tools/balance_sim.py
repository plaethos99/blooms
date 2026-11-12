"""Plays many headless LAST LIGHT rounds in parallel and summarises escape rates.

Usage: python tools/balance_sim.py [rounds] [--gentle] [--noshove] [--jobs N]
Every pilgrim is AI (the player on autopilot), so this measures the game's
pressure, not a human's skill.
"""
import re, statistics, subprocess, sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

GODOT = r"C:/Users/Admin/Downloads/godot/Godot_v4.7.2-stable_win64_console.exe"
PROJECT = Path(__file__).resolve().parent.parent

def one(_):
    args = [GODOT, "--headless", "--path", str(PROJECT), "--fixed-fps", "60",
            "--quit-after", "18700", "--", "--autostart", "--autopilot", "--log"]
    for flag in ("--gentle", "--noshove"):
        if flag in sys.argv:
            args.append(flag)
    out = subprocess.run(args, capture_output=True, text=True, timeout=900).stdout
    m = re.search(r"RESULT (.*)", out)
    if not m:
        return None
    return {k: (v if k == "player" else float(v)) for k, v in re.findall(r"(\w+)=(\w+)", m.group(1))}

def main():
    n = int(next((a for a in sys.argv[1:] if a.isdigit()), "8"))
    jobs = int(sys.argv[sys.argv.index("--jobs") + 1]) if "--jobs" in sys.argv else 4
    with ThreadPoolExecutor(jobs) as ex:
        rows = [r for r in ex.map(one, range(n)) if r]
    esc = [r["esc"] for r in rows]
    print("rounds=%d  escapes per round: %s" % (len(rows), " ".join(str(int(e)) for e in esc)))
    print("mean escapes=%.1f  stdev=%.1f  player escaped %d/%d" % (
        statistics.mean(esc), statistics.pstdev(esc), sum(r["player"] == "esc" for r in rows), len(rows)))
    for k in ["bloom", "shard", "damage", "flare", "kills", "blooms", "hollows", "fell", "shoves", "pushed_off", "wyrm", "drops"]:
        print("  avg %-7s %.0f" % (k, statistics.mean(r[k] for r in rows)))

if __name__ == "__main__":
    main()
