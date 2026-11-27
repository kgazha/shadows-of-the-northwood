"""R8.1 негативный контроль (рецепт diag-t40/OTCHET.md §5 п.2, снят капитаном 27.11).

Суть: усиленный знаменатель v5.2 обязан ловить НАСТОЯЩУЮ деградацию, а не только
отсеивать помеху. Проверка — временно удорожить одну зону и убедиться, что R8.1
краснеет.

ВАЖНО (договорённость с капитаном, чтобы не отравить чужой слот): удорожание
живёт ТОЛЬКО в копии моего стейджа diag-t40/stage/pixel-rpg. Рабочее дерево
pixel-rpg/ не меняется ни на байт — robocopy идёт дерево -> стейдж, правка
накладывается на стейдж, `--revert` пересобирает стейдж начисто.

Замеры (окно = тихий бокс, иначе классифицировать как нагруженное):
  python -u diag-t40/negctl.py --inject --run      чистое окно, удорожённая зона
  python -u diag-t40/negctl.py --run --load        нагруженное окно (свой world-sim рядом)
  python -u diag-t40/negctl.py --revert --run      снятие: снова зелёное 49/49
"""
import io
import os
import shutil
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
D = os.path.join(ROOT, "diag-t40")
STAGE = os.path.join(D, "stage", "pixel-rpg")
APP = os.path.join(D, "appdata")
GODOT = os.path.join(ROOT, "tools", "godot", "Godot_v4.7.2-stable_win64_console.exe")
TARGET = os.path.join(STAGE, "scripts", "biome_zone.gd")
ENV = dict(os.environ, APPDATA=APP, LOCALAPPDATA=APP)

# Метка правки — по ней же и снимается. ~40 мс/кадр busy-цикла в одной зоне
# (loc_castle): база у R8.1 ~30 мс, значит отношение ~2,3 при пороге 1,3.
MARK = "# NEGCTL R8.1 (diag-t40, 27.11): временное удорожание зоны для негативного контроля"
SABOTAGE = (
    "\n" + MARK + "\n"
    "func _process(_delta: float) -> void:\n"
    "\tif biome != \"castle\":\n"
    "\t\treturn\n"
    "\tvar _t := Time.get_ticks_usec()\n"
    "\twhile Time.get_ticks_usec() - _t < 40000:\n"
    "\t\tpass\n"
)


def sh(cmd, timeout=1800, log=None, cwd=ROOT):
    p = subprocess.run(cmd, cwd=cwd, env=ENV, capture_output=True, text=True,
                       encoding="utf-8", errors="replace", timeout=timeout)
    if log:
        io.open(log, "w", encoding="utf-8").write((p.stdout or "") + (p.stderr or ""))
    return p


def build_stage():
    """Стейдж начисто из рабочего дерева (playload стендов — как в run_wreg.py)."""
    if os.path.isdir(STAGE):
        shutil.rmtree(STAGE, ignore_errors=True)
    os.makedirs(os.path.dirname(STAGE), exist_ok=True)
    os.makedirs(APP, exist_ok=True)
    sh(["robocopy", os.path.join(ROOT, "pixel-rpg"), STAGE, "/E", "/NFL", "/NDL",
        "/NJH", "/NJS", "/MT:8", "/XD", ".godot", "appdata", "appdata_qa"], 900)
    if not os.path.isdir(os.path.join(STAGE, "scenes")):
        print("FATAL: стейдж не собрался")
        return False
    for f in sorted(os.listdir(os.path.join(ROOT, "tools", "qa", "stand"))):
        shutil.copyfile(os.path.join(ROOT, "tools", "qa", "stand", f),
                        os.path.join(STAGE, f))
    for i in (1, 2):
        r = sh([GODOT, "--headless", "--path", STAGE, "--import"], timeout=1200,
               log=os.path.join(D, "nc_import_%d.log" % i))
        print("  import %d: exit=%d" % (i, r.returncode))
    return True


def inject():
    s = io.open(TARGET, encoding="utf-8").read()
    if MARK in s:
        print("удорожание уже в стейдже")
        return True
    io.open(TARGET, "w", encoding="utf-8").write(s + SABOTAGE)
    print("удорожание внесено ТОЛЬКО в стейдж: %s (+busy 40 мс/кадр в biome==castle)"
          % os.path.relpath(TARGET, ROOT).replace("\\", "/"))
    return True


def sabotage_loaders(n=2, seconds=420):
    """Создать помеху так же, как в t40 §2: живые world-sim рядом (по 2 Godot)."""
    procs = []
    for i in range(n):
        log = io.open(os.path.join(D, "nc_load_%d.log" % i), "w", encoding="utf-8")
        procs.append(subprocess.Popen(
            [sys.executable, "-u", os.path.join(ROOT, "diag-t33", "run_census.py"),
             "--quiet", "-p", "1", "roam:%d:300:nc%d" % (2801 + 1234 * i, i)],
            cwd=ROOT, env=ENV, stdout=log, stderr=subprocess.STDOUT))
        time.sleep(6)
    return procs


def run_stand(tag):
    for f in sorted(os.listdir(os.path.join(ROOT, "tools", "qa", "stand"))):
        shutil.copyfile(os.path.join(ROOT, "tools", "qa", "stand", f),
                        os.path.join(STAGE, f))
    log = os.path.join(D, "nc_%s.log" % tag)
    p = sh([GODOT, "--headless", "--path", STAGE, "--fixed-fps", "60",
            "res://qa_wreg.tscn"], timeout=1800, cwd=STAGE)
    out = (p.stdout or "") + (p.stderr or "")
    io.open(log, "w", encoding="utf-8").write(out)
    r8 = [ln.strip() for ln in out.splitlines() if "R8" in ln or "r8" in ln]
    totals = [ln.strip() for ln in out.splitlines() if ln.startswith("QA_WREG")]
    print("  прогон «%s»: exit=%d, лог %s" % (tag, p.returncode, os.path.basename(log)))
    for ln in r8[-8:]:
        print("    R8: " + ln[:200])
    for ln in totals[-3:]:
        print("    итог: " + ln[:200])
    return p.returncode


def main():
    a = sys.argv[1:]
    if "--rebuild" in a or not os.path.isdir(os.path.join(STAGE, ".godot")):
        if not build_stage():
            return 2
    else:
        print("стейдж переиспользуется")
    if "--revert" in a:
        s = io.open(TARGET, encoding="utf-8").read()
        if MARK in s:
            io.open(TARGET, "w", encoding="utf-8").write(s.split(MARK)[0].rstrip() + "\n")
            print("удорожание снято со стейджа")
        else:
            print("в стейдже удорожания нет (чисто)")
    if "--inject" in a and not inject():
        return 2
    procs = []
    if "--load" in a:
        procs = sabotage_loaders()
        print("  помеха запущена (%d загрузчика world-sim)" % len(procs))
    rc = 0
    if "--run" in a:
        tag = "loaded" if "--load" in a else ("revert" if "--revert" in a else "sabotaged")
        rc = run_stand(tag)
    for p in procs:
        try:
            p.wait(timeout=900)
        except Exception:
            p.kill()
    return rc


if __name__ == "__main__":
    sys.exit(main())
