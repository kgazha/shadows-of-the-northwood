"""t40: прогон qa_wreg на РАБОЧЕМ дереве в изолированном стейдже.

Урок F-5/t33: не трогать общий стейдж раннера (tools/appdata_qa/stage) — там чужие
прогоны. Стейдж свой: diag-t40/stage/pixel-rpg, APPDATA свой, Godot по одному.

Отличие от feel_gate.py: источник — РАБОЧЕЕ дерево (правка qa_wreg.gd ещё не
закоммичена), а не git archive HEAD.

Запуск: python -u diag-t40/run_wreg.py [--rebuild]
"""
import os
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GODOT = os.path.join(ROOT, "tools", "godot", "Godot_v4.7.2-stable_win64_console.exe")
D = os.path.join(ROOT, "diag-t40")
STAGE = os.path.join(D, "stage", "pixel-rpg")
APP = os.path.join(D, "appdata")
STAND = "qa_wreg"
ENV = dict(os.environ, APPDATA=APP, LOCALAPPDATA=APP)


def sh(cmd, timeout=1200, log=None, cwd=ROOT):
    p = subprocess.run(cmd, cwd=cwd, env=ENV, capture_output=True, text=True,
                       encoding="utf-8", errors="replace", timeout=timeout)
    if log:
        with open(log, "w", encoding="utf-8") as fh:
            fh.write((p.stdout or "") + (p.stderr or ""))
    return p


def build_stage():
    if os.path.isdir(STAGE):
        shutil.rmtree(STAGE, ignore_errors=True)
    os.makedirs(os.path.dirname(STAGE), exist_ok=True)
    os.makedirs(APP, exist_ok=True)
    src = os.path.join(ROOT, "pixel-rpg")
    # /XD .godot — кэш чужого дерева не переносим, импорт будет свой
    sh(["robocopy", src, STAGE, "/E", "/NFL", "/NDL", "/NJH", "/NJS", "/MT:8",
        "/XD", ".godot", "appdata", "appdata_qa"], 900)
    if not os.path.isdir(os.path.join(STAGE, "scenes")):
        print("FATAL: стейдж не собрался")
        return False
    n = 0
    sdir = os.path.join(ROOT, "tools", "qa", "stand")
    for f in sorted(os.listdir(sdir)):
        shutil.copyfile(os.path.join(sdir, f), os.path.join(STAGE, f))
        n += 1
    print("стейдж рабочего дерева: игра + %d файлов стендов" % n)
    for i in (1, 2):
        r = sh([GODOT, "--headless", "--path", STAGE, "--import"], timeout=1200,
               log=os.path.join(D, "import_%d.log" % i))
        print("  import %d: exit=%d" % (i, r.returncode))
    return True


def main():
    args = sys.argv[1:]
    need = "--rebuild" in args or not os.path.isdir(os.path.join(STAGE, ".godot"))
    if need:
        if not build_stage():
            return 2
    else:
        for f in os.listdir(os.path.join(ROOT, "tools", "qa", "stand")):
            shutil.copyfile(os.path.join(ROOT, "tools", "qa", "stand", f),
                            os.path.join(STAGE, f))
        print("стейдж переиспользуется, файлы стендов обновлены")
    log = os.path.join(D, "%s.log" % STAND)
    p = sh([GODOT, "--headless", "--path", STAGE, "--fixed-fps", "60",
            "res://%s.tscn" % STAND], timeout=1500, cwd=STAGE)
    out = (p.stdout or "") + (p.stderr or "")
    with open(log, "w", encoding="utf-8") as fh:
        fh.write(out)
    fails = [ln.strip() for ln in out.splitlines()
             if "FAIL" in ln or "SCRIPT ERROR" in ln or "Parse Error" in ln]
    totals = [ln.strip() for ln in out.splitlines() if ln.startswith("QA_WREG")]
    v51 = [ln.strip() for ln in out.splitlines() if "v5.1" in ln]
    print("  %s: exit=%d | красных/ошибок %d | лог %s" % (STAND, p.returncode, len(fails),
                                                          os.path.basename(log)))
    for ln in v51:
        print("    " + ln[:220])
    for ln in totals[-3:]:
        print("    " + ln[:200])
    for ln in fails[:12]:
        print("    КРАСНЫЙ: " + ln[:200])
    return p.returncode


if __name__ == "__main__":
    sys.exit(main())
