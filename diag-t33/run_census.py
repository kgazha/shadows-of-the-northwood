"""t33: базовая перепись скучности на ПОБИТОВОМ HEAD — свой канон-стейдж.

Метод перенесён с t27/t29 (урок F-5): измерять HEAD можно только самим
извлечённым HEAD (общий стейдж раннера после чужого robocopy содержит рабочее
дерево). Игра извлекается из `git archive HEAD`; зонд кладётся сверху; каждый
прогон — со свежего изолированного user:// (иначе чужой сейв исказит лут).

Спецификация прогона: режим:сид:секунды[:метка]  (метка нужна, чтобы гонять
один и тот же конфиг дважды на воспроизводимость).

Запуск:
  python -u diag-t33/run_census.py --stage
  python -u diag-t33/run_census.py march:2801:900 roam:2801:600
  python -u diag-t33/run_census.py -p 2 march:2801:900 march:2801:900:r2
"""
import json
import os
import shutil
import atexit
import subprocess
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                                "diag-t27"))
from quiet_perf import ROOT, godot_pids, wait_quiet  # noqa: E402

GODOT = os.path.join(ROOT, "tools", "godot", "Godot_v4.7.2-stable_win64_console.exe")
D = os.path.join(ROOT, "diag-t33")
HX = os.path.join(D, "_hx")
STAGE = os.path.join(D, "stage", "pixel-rpg")
OUT = os.path.join(D, "out")
PROBES = ("census_t33.gd", "census_t33.tscn")


def sh(cmd, timeout=1800, log=None, cwd=ROOT):
    p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True,
                       encoding="utf-8", errors="replace", timeout=timeout)
    if log:
        with open(log, "w", encoding="utf-8") as fh:
            fh.write((p.stdout or "") + (p.stderr or ""))
    return p


def build_stage():
    for p in (HX, STAGE):
        shutil.rmtree(p, ignore_errors=True)
    os.makedirs(HX, exist_ok=True)
    os.makedirs(os.path.dirname(STAGE), exist_ok=True)
    z = os.path.join(D, "head_game.zip")
    if os.path.exists(z):
        os.remove(z)
    r = sh(["git", "archive", "--format=zip", "-o", z, "HEAD", "--", "pixel-rpg"])
    if r.returncode != 0:
        print("FATAL git archive: %s" % (r.stderr or "")[:300])
        return False
    un = os.path.join(HX, "game")
    os.makedirs(un, exist_ok=True)
    r = sh(["tar", "-xf", z, "-C", un])
    if r.returncode != 0:
        print("FATAL tar: %s" % (r.stderr or "")[:300])
        return False
    shutil.copytree(os.path.join(un, "pixel-rpg"), STAGE)
    for f in PROBES:
        shutil.copy2(os.path.join(D, f), os.path.join(STAGE, f))
    if os.path.exists(z):
        os.remove(z)
    env = dict(os.environ, APPDATA=os.path.join(D, "appdata_stage"),
               LOCALAPPDATA=os.path.join(D, "appdata_stage"))
    for i in range(2):
        sh([GODOT, "--headless", "--path", STAGE, "--import"], 900,
           os.path.join(D, "import_%d.log" % i), )
    print("стейдж HEAD собран: %s" % STAGE)
    return True


def prepare(spec, idx):
    for f in PROBES:
        shutil.copy2(os.path.join(D, f), os.path.join(STAGE, f))
    parts = spec.split(":")
    mode, seed, seconds = parts[0], parts[1], int(parts[2])
    suffix = parts[3] if len(parts) > 3 else "r1"
    tag = "%s_s%s_%s" % (mode, seed, suffix)
    app = os.path.join(D, "appdata_%d" % idx)
    shutil.rmtree(app, ignore_errors=True)
    os.makedirs(app, exist_ok=True)
    cfg = {"mode": mode, "seed": int(seed), "seconds": seconds, "cls": "warrior", "trace": 1}
    with open(os.path.join(STAGE, "census_cfg_%s.json" % tag), "w", encoding="utf-8") as fh:
        json.dump(cfg, fh, ensure_ascii=False)
    o = os.path.join(STAGE, "census_out_%s.json" % tag)
    if os.path.exists(o):
        os.remove(o)
    env = dict(os.environ, APPDATA=app, LOCALAPPDATA=app, CENSUS_TAG=tag,
               PYTHONIOENCODING="utf-8")
    return tag, seconds, env


def launch(tag, seconds, env):
    log = open(os.path.join(D, "log_%s.log" % tag), "w", encoding="utf-8")
    cmd = [GODOT, "--headless", "--path", STAGE, "--fixed-fps", "60",
           "--quit-after", str(seconds * 60 * 4), "res://census_t33.tscn"]
    return subprocess.Popen(cmd, env=env, stdout=log, stderr=subprocess.STDOUT), log


MYDIR = os.path.dirname(os.path.abspath(__file__))
MYLOCK = os.path.join(MYDIR, "census.lock")


def _own_lock_free():
    """Жив ли мой прошлый прогон переписи (по PID из собственного лока)."""
    if not os.path.exists(MYLOCK):
        return True
    try:
        pid = int(open(MYLOCK, encoding="utf-8").read().split("\n")[0] or 0)
    except (ValueError, OSError):
        return True
    out = subprocess.run(["tasklist", "/FI", "PID eq %d" % pid, "/FO", "CSV", "/NH"],
                         capture_output=True, text=True).stdout
    return "INFO:" not in out


def _take_lock():
    with open(MYLOCK, "w", encoding="utf-8") as fh:
        fh.write("%d\n%s\n" % (os.getpid(), time.strftime("%Y-%m-%d %H:%M:%S")))


def _drop_lock():
    try:
        os.remove(MYLOCK)
    except OSError:
        pass


def collect(tag, t0, rc):
    os.makedirs(OUT, exist_ok=True)
    src = os.path.join(STAGE, "census_out_%s.json" % tag)
    dst = os.path.join(OUT, "census_%s.json" % tag)
    wall = time.time() - t0
    if not os.path.exists(src):
        print("  !!! %-22s wall=%.0f с exit=%s: census_out нет — см. log_%s.log"
              % (tag, wall, rc, tag))
        return False
    shutil.copy2(src, dst)
    with open(dst, encoding="utf-8") as fh:
        r = json.load(fh)
    wow = r["wow_item"] or "нет"
    wtime = ("%.0f с" % r["wow_sec"]) if r["wow_sec"] >= 0 else "-"
    zwalk = sum(v["walk_px"] for v in r["zones"].values())
    print("  готов %-22s wall=%.0f с exit=%s: %.0f с | конт. %d (%.2f/мин) | сух.макс %.0f с "
          "| угроз %.3f | смерт. %d | вау %s (%s) | вещей %d | E %d" % (
              tag, wall, rc, r["sec_total"], r["contact_events"], r["contacts_per_min"],
              r["dry_max_sec"], r["threat_share"], r["deaths"], wow, wtime,
              r["gear_items"], r["interacts"]))
    print("        ходьбы %.0f px (%.2f мин чистой) | зон %d | плеч %s | bfs-отказ %d | "
          "локи %s | застреваний %.0f с" % (
              zwalk, r["walk_pure_min"], len(r["zones"]), r.get("leg_max"),
              r.get("bfs_fail"), len(r["areas"]), r["stuck_sec"]))
    print("        из них геометрия %.0f с / залочено окнами %.0f с (t42: разделённый stuck)" % (
        float(r.get("stuck_geom_sec", -1)), float(r.get("stuck_lock_sec", -1))))
    return True


def main():
    args = sys.argv[1:]
    par = 1
    if "-p" in args:
        i = args.index("-p")
        par = int(args[i + 1])
        del args[i:i + 2]
    quiet = "--quiet" in args
    if quiet:
        args.remove("--quiet")
    if not args:
        args = ["roam:2801:60"]
    if args[0] == "--stage":
        sys.exit(0 if build_stage() else 1)
    # СВОЙ лок переписи (26.11, после инцидента с потерянными прогонами): общий
    # tools/appdata_qa/runner.lock — только читаемый признак чужой батареи.
    if not _own_lock_free():
        print("diag-t33/census.lock держит живой прогон переписи — выхожу, не мешая")
        sys.exit(4)
    _take_lock()
    atexit.register(_drop_lock)
    if quiet:
        print("жду тихого окна (лок раннера снят и ни одного Godot)…")
        print("  тихое окно: ok=%s waited=%.0f с" % wait_quiet())
    if not os.path.isdir(os.path.join(STAGE, "scenes")):
        wait_quiet()
        if not build_stage():
            sys.exit(1)
    running = []
    queue = list(enumerate(args))
    results = {}
    while queue or running:
        while queue and len(running) < par:
            idx, spec = queue.pop(0)
            tag, seconds, env = prepare(spec, idx)
            p, log = launch(tag, seconds, env)
            running.append([tag, p, log, time.time()])
            print("  старт %-22s (%d с симуляции, %d параллельно)" % (tag, seconds, len(running)))
        time.sleep(5.0)
        still = []
        for item in running:
            tag, p, log, t0 = item
            rc = p.poll()
            if rc is None:
                if time.time() - t0 > 60 * 60 * 3:
                    print("  ~~ %-22s дольше 3 ч — снимаю" % tag)
                    p.kill()
                    rc = p.wait()
                else:
                    still.append(item)
                continue
            log.close()
            results[tag] = collect(tag, t0, rc)
        running = still
    ok = sum(1 for v in results.values() if v)
    print("прогонов завершено: %d/%d" % (ok, len(results)))
    sys.exit(0 if ok == len(results) and ok > 0 else 1)


if __name__ == "__main__":
    main()
