"""t39: ворота волны «Интерес v1» — один вход для всех замеров.

Подкоманды:
  fingerprint          снять и сохранить слепок измеряемого состояния
  stage                собрать СВОЙ стейдж из git archive HEAD (игра) + стенды
  audit <метка>        прогнать независимый аудит (метка r1/r2 — для побайтового
                       сравнения детерминизма между процессами)
  battery              канонная батарея node tools/qa/run_all.js (она сама
                       распаковывает HEAD и держит общий runner.lock — это её лок)
  census <spec...>     перепись интереса (делегирует diag-t33/run_census.py)

Правила развода (26.11, после трёх взаимных инцидентов): свой каталог стейджа,
СВОЙ лок diag-t39/t39.lock, общий tools/appdata_qa/runner.lock только читаем;
перед стартом — проверка чужих раннеров. --allow-load для НЕперф-замеров
(аудит и перепись мерят события и логику, а не микросекунды).
"""
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GODOT = os.path.join(ROOT, "tools", "godot", "Godot_v4.7.2-stable_win64_console.exe")
D = os.path.join(ROOT, "diag-t39")
STAGE = os.path.join(D, "stage", "pixel-rpg")
HX = os.path.join(D, "_hx")
APP = os.path.join(D, "appdata")
MYLOCK = os.path.join(D, "t39.lock")
SHARED_LOCK = os.path.join(ROOT, "tools", "appdata_qa", "runner.lock")
OUT = os.path.join(D, "out")
PROBES = ("audit_t39.gd", "audit_t39.tscn")


def env_for(app):
    return dict(os.environ, APPDATA=app, LOCALAPPDATA=app, PYTHONIOENCODING="utf-8")


def sh(cmd, timeout=1800, log=None, cwd=ROOT, env=None):
    # Godot в песочнице DSH пишется в ФАЙЛ, а не в канал: канал
    # capture_output у long-running headless-процесса съедает наблюдаемость (нет
    # живого журнала) и ведёт себя хуже, чем перенаправление. Узловые прогоны
    # (node) остаются с каналом — их вывод парсится вызывающим кодом.
    if log and cmd and str(cmd[0]).endswith("console.exe"):
        with open(log, "w", encoding="utf-8") as fh:
            return subprocess.run(cmd, cwd=cwd, env=env or env_for(APP),
                                  stdout=fh, stderr=subprocess.STDOUT, timeout=timeout)
    p = subprocess.run(cmd, cwd=cwd, env=env or env_for(APP), capture_output=True,
                       text=True, encoding="utf-8", errors="replace", timeout=timeout)
    if log:
        with open(log, "w", encoding="utf-8") as fh:
            fh.write((p.stdout or "") + (p.stderr or ""))
    return p


def godot_n():
    n = 0
    for exe in ("Godot_v4.7.2-stable_win64.exe", "Godot_v4.7.2-stable_win64_console.exe"):
        out = subprocess.run(["tasklist", "/FI", "IMAGENAME eq " + exe, "/FO", "CSV", "/NH"],
                             capture_output=True, text=True).stdout
        n += sum(1 for ln in out.splitlines() if "Godot" in ln)
    return n


def own_lock_free():
    if not os.path.exists(MYLOCK):
        return True
    try:
        pid = int(open(MYLOCK, encoding="utf-8").read().split("\n")[0] or 0)
    except (ValueError, OSError):
        return True
    out = subprocess.run(["tasklist", "/FI", "PID eq %d" % pid, "/FO", "CSV", "/NH"],
                         capture_output=True, text=True).stdout
    return "INFO:" not in out


def take_lock():
    if not own_lock_free():
        return False
    os.makedirs(D, exist_ok=True)
    with open(MYLOCK, "w", encoding="utf-8") as fh:
        fh.write("%d\n%s\n" % (os.getpid(), time.strftime("%Y-%m-%d %H:%M:%S")))
    return True


def drop_lock():
    try:
        os.remove(MYLOCK)
    except OSError:
        pass


def wait_room(limit=3600, allow_load=False, wait_min=0.0):
    t0 = time.time()
    while time.time() - t0 < limit:
        why = []
        if time.time() < t0 + wait_min * 60.0:
            why.append("выдержка %d мин" % int(wait_min))
        if not allow_load:
            if godot_n():
                why.append("Godot=%d" % godot_n())
            if os.path.exists(SHARED_LOCK):
                why.append("идёт канонная батарея (runner.lock существует)")
        if not own_lock_free():
            why.append("мой прошлый прогон жив")
        if not why:
            return True, time.time() - t0
        print("    жду: %s" % ", ".join(why), flush=True)
        time.sleep(20)
    return False, time.time() - t0


def fingerprint():
    h = sh(["git", "rev-parse", "HEAD"])
    head = (h.stdout or "").strip()
    st = sh(["git", "status", "--porcelain", "--", "pixel-rpg", "tools/qa"])
    lines = ["HEAD=" + head]
    g = hashlib.md5()
    for base, dirs, files in os.walk(os.path.join(ROOT, "pixel-rpg")):
        dirs[:] = [x for x in dirs if x not in (".godot", "appdata", "appdata_qa")]
        for f in sorted(files):
            p = os.path.join(base, f)
            g.update(os.path.relpath(p, ROOT).encode("utf-8"))
            g.update(open(p, "rb").read())
    lines.append("pixel-rpg md5=" + g.hexdigest())
    s = hashlib.md5()
    sdir = os.path.join(ROOT, "tools", "qa", "stand")
    for f in sorted(os.listdir(sdir)):
        s.update(f.encode("utf-8"))
        s.update(open(os.path.join(sdir, f), "rb").read())
    lines.append("tools/qa/stand md5=" + s.hexdigest())
    dirty = [ln for ln in (st.stdout or "").splitlines() if ln.strip()]
    lines.append("грязных путей (pixel-rpg + tools/qa): %d" % len(dirty))
    for ln in dirty:
        lines.append("  " + ln)
    os.makedirs(D, exist_ok=True)
    txt = "\n".join(lines) + "\n"
    with open(os.path.join(D, "fingerprint.txt"), "w", encoding="utf-8") as fh:
        fh.write(txt)
    print(txt)
    return head


def build_stage():
    fingerprint()
    for p in (HX, STAGE):
        shutil.rmtree(p, ignore_errors=True)
    os.makedirs(HX, exist_ok=True)
    os.makedirs(os.path.dirname(STAGE), exist_ok=True)
    os.makedirs(APP, exist_ok=True)
    os.makedirs(OUT, exist_ok=True)
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
    for f in os.listdir(os.path.join(ROOT, "tools", "qa", "stand")):
        shutil.copy2(os.path.join(ROOT, "tools", "qa", "stand", f), os.path.join(STAGE, f))
    for f in PROBES:
        shutil.copy2(os.path.join(D, f), os.path.join(STAGE, f))
    os.remove(z)
    for i in range(2):
        rr = sh([GODOT, "--headless", "--path", STAGE, "--import"], 1200,
                os.path.join(D, "import_%d.log" % i))
        print("  import %d: exit=%d" % (i, rr.returncode))
    print("стейдж HEAD собран: %s" % STAGE)
    return True


def run_audit(tag):
    app = os.path.join(D, "appdata_%s" % tag)
    shutil.rmtree(app, ignore_errors=True)
    os.makedirs(app, exist_ok=True)
    for f in PROBES:
        shutil.copy2(os.path.join(D, f), os.path.join(STAGE, f))
    for cand in ("t39_audit.json",):
        p = os.path.join(STAGE, cand)
        if os.path.exists(p):
            os.remove(p)
    t0 = time.time()
    r = sh([GODOT, "--headless", "--path", STAGE, "--fixed-fps", "60",
            "res://audit_t39.tscn"], timeout=1500,
           log=os.path.join(D, "audit_%s.log" % tag), env=env_for(app))
    wall = time.time() - t0
    src = os.path.join(STAGE, "t39_audit.json")
    if not os.path.exists(src):
        # Godot кладёт относительный путь в cwd процесса; пробуем и appdata
        alt = os.path.join(app, "Godot", "app_userdata")
        print("  дамп не в стейдже, ищем глубже: %s" % alt)
        for base, _d, files in os.walk(alt):
            for f in files:
                if f == "t39_audit.json":
                    src = os.path.join(base, f)
    if os.path.exists(src):
        shutil.copy2(src, os.path.join(OUT, "audit_%s.json" % tag))
        print("  дамп: out/audit_%s.json" % tag)
    txt = open(os.path.join(D, "audit_%s.log" % tag), encoding="utf-8").read()
    npass = txt.count("PASS:")
    nfail = txt.count("FAIL:")
    print("  аудит %s: wall=%.0f с exit=%s PASS=%d FAIL=%d" % (tag, wall, r.returncode, npass, nfail))
    for ln in txt.splitlines():
        if ln.startswith("FAIL:") or ln.startswith("T39 ЗАМЕТКА") or "SCRIPT ERROR" in ln \
                or "Parse Error" in ln:
            print("    " + ln[:220])
    return nfail == 0 and npass > 0


def battery():
    print("канонная батарея (сама распакует HEAD и возьмёт свой runner.lock)…")
    t0 = time.time()
    r = sh(["node", os.path.join(ROOT, "tools", "qa", "run_all.js"), "--timeout=300"],
           timeout=5400, log=os.path.join(D, "battery.log"), env=dict(os.environ))
    print("  батарея: wall=%.0f с exit=%d" % (time.time() - t0, r.returncode))
    tail = (r.stdout or "").splitlines()[-30:]
    for ln in tail:
        print("    " + ln[:200])
    return r.returncode == 0


def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        return 2
    cmd = args[0]
    if cmd == "fingerprint":
        fingerprint()
        return 0
    if cmd == "battery":
        # канонный раннер сам охраняется общим локом; наша выдержка — не стартовать
        # поверх чужого Godot
        if not take_lock():
            print("мой прошлый прогон держит t39.lock")
            return 4
        try:
            ok, w = wait_room(limit=3600)
            if not ok:
                print("окно не наступило за %.0f с" % w)
                return 3
            return 0 if battery() else 1
        finally:
            drop_lock()
    if cmd == "stage":
        if not take_lock():
            return 4
        try:
            ok, _w = wait_room(limit=3600, allow_load="--allow-load" in args)
            return 0 if build_stage() else 1
        finally:
            drop_lock()
    if cmd == "audit":
        tag = args[1] if len(args) > 1 else "r1"
        if not os.path.isdir(os.path.join(STAGE, "scenes")):
            print("стейдж не собран — собираю")
            if not build_stage():
                return 2
        if not take_lock():
            return 4
        try:
            ok, _w = wait_room(limit=2400, allow_load="--allow-load" in args)
            return 0 if run_audit(tag) else 1
        finally:
            drop_lock()
    if cmd == "census":
        specs = [a for a in args[1:] if not a.startswith("--")]
        if not specs:
            print("нужны спецификации режима:сид:секунды[:метка]")
            return 2
        if not take_lock():
            return 4
        try:
            ok, _w = wait_room(limit=3600, allow_load="--allow-load" in args)
            if not ok:
                return 3
            r = sh([sys.executable, "-u", os.path.join(ROOT, "diag-t33", "run_census.py")]
                   + specs, timeout=14400, log=os.path.join(D, "census_%s.log" % time.strftime("%H%M")),
                   env=dict(os.environ))
            print(r.stdout[-4000:])
            return r.returncode
        finally:
            drop_lock()
    print("неизвестная подкоманда: %s" % cmd)
    return 2


if __name__ == "__main__":
    sys.exit(main())
