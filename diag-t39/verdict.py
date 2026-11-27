# -*- coding: utf-8 -*-
# t39 — свод «база / после» по девяти порогам boring_census.md §6.
#
# Читает census_<режим>_s<сид>_<метка>.json, собранные ОДНИМ зондом t33.
# Правила применения — те же, что в законе: два прогона на сид, в зачёт ХУДШИЙ;
# прогон со stuck > 60 с бракуется (встанка — геометрия, не интерес).
#
# Запуск:  python -u diag-t39/verdict.py f f2 -- g g2
#          (метки базы, разделитель --, метки пакета «после»)
import io
import json
import os
import sys

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), os.pardir, "diag-t33", "out")
MODES = ["roam", "march"]
SEEDS = [2801, 777]
BRAKE_SEC = 60.0  # порог браковки встанки — общий для базы и «после»
LOCK_BRAKE_SEC = 60.0  # t39 поправка к закону: браковка по «сидит в окне»
                       # (lock_other > 60 с при закрытых диалоге и модалке).
                       # На базе ничего не меняет: максимум lock_other в базе 4,5 с.


def load(mode, seed, label):
    p = os.path.join(OUT, "census_%s_s%d_%s.json" % (mode, seed, label))
    if not os.path.exists(p):
        return None
    return json.load(io.open(p, encoding="utf-8"))


def back_zones(r):
    """Зоны, посещённые >= 2 раза (по переходам), не считая деревни."""
    seen = {}
    for _frame, _frm, to in r.get("areas", []):
        seen[to] = seen.get(to, 0) + 1
    return sorted(z for z, n in seen.items() if n >= 2 and z != "village")


def windows_sec(r):
    return float(r.get("dialog_sec", 0.0)) + float(r.get("modal_sec", 0.0))


def criteria(r):
    """Девять пунктов §6 для ОДНОГО прогона. None = мере нечем мерить."""
    mode = str(r["cfg"].get("mode"))
    wow = float(r.get("wow_sec", -1.0))
    c = []
    if mode == "roam":
        c.append(("1 контакты/мин >= 1,0", float(r["contacts_per_min"]) >= 1.0,
                  "%.2f" % float(r["contacts_per_min"])))
    else:
        c.append(("1 контакты/мин (порог для roam)", None, "%.2f" % float(r["contacts_per_min"])))
    c.append(("2 крупнейший сухой <= 90 с", float(r["dry_max_sec"]) <= 90.0, "%.0f с" % float(r["dry_max_sec"])))
    c.append(("3 сухих всего <= 240 с", float(r["dry_sum_sec"]) <= 240.0, "%.0f с" % float(r["dry_sum_sec"])))
    need = 3 if mode == "roam" else 1
    c.append(("4 ставок >= %d (%s)" % (need, mode), int(r["bets"]) >= need, str(int(r["bets"]))))
    c.append(("5 доля угроз >= 0,5", float(r["threat_share"]) >= 0.5, "%.3f" % float(r["threat_share"])))
    ok6 = wow >= 0.0 and wow <= 420.0 and int(r.get("dungeons_before_wow", 99)) <= 2
    c.append(("6 вау-лут <= 420 с и <= 2 подземелий", ok6,
              ("нет" if wow < 0.0 else "%.0f с / %d подз." % (wow, int(r.get("dungeons_before_wow", -1))))))
    bz = back_zones(r)
    c.append(("7 возврат >= 1 зоны", len(bz) >= 1, ",".join(bz) or "нет"))
    c.append(("8 смерти <= 2", int(r["deaths"]) <= 2, str(int(r["deaths"]))))
    c.append(("9 окна <= 45 с", windows_sec(r) <= 45.0, "%.1f с" % windows_sec(r)))
    return c


def stuck_of(r):
    s = float(r.get("stuck_sec", 0.0))
    g = r.get("stuck_geom_sec")
    l = r.get("stuck_lock_sec")
    extra = "" if g is None else " (геометрия %.0f / залочено %.0f)" % (float(g), float(l))
    return s, extra


def report(title, labels):
    print("\n## %s — прогоны\n" % title)
    print("| сид/режим | метка | stuck, с | конт/мин | сух.макс | сух.сум | ставки | угрозы | вау | возврат | смерт. | окна | вердикт |")
    print("|---|---|---|---|---|---|---|---|---|---|---|---|---|")
    best = {}
    for seed in SEEDS:
        for mode in MODES:
            for lab in labels:
                r = load(mode, seed, lab)
                if r is None:
                    continue
                s, extra = stuck_of(r)
                lo = float(r.get("lock_other_sec", 0.0))
                braked = s > BRAKE_SEC
                brake_why = "БРАК (встанка)" if braked else ""
                if not braked and lo > LOCK_BRAKE_SEC:
                    braked, brake_why = True, "БРАК (сидит в окне: %.0f с)" % lo
                cr = criteria(r)
                fails = [n for n, ok, _v in cr if ok is False]
                verdict = brake_why if braked else ("PASS" if not fails else "провал: " + "; ".join(fails))
                wow = float(r.get("wow_sec", -1.0))
                print("| %d/%s | %s | %.0f%s | %.2f | %.0f | %.0f | %d | %.3f | %s | %s | %d | %.1f | %s |" % (
                    seed, mode, lab, s, extra, float(r["contacts_per_min"]), float(r["dry_max_sec"]),
                    float(r["dry_sum_sec"]), int(r["bets"]), float(r["threat_share"]),
                    "нет" if wow < 0.0 else "%.0f с" % wow, ",".join(back_zones(r)) or "нет",
                    int(r["deaths"]), windows_sec(r), verdict))
                if braked:
                    continue
                # ХУДШИЙ из чистых: для каждой метрики берём наихудшее значение.
                key = (seed, mode)
                cand = best.setdefault(key, [])
                cand.append(r)
    print("\n## %s — ХУДШИЙ из чистых и вердикт по девяти порогам\n" % title)
    print("| сид/режим | критерий | худшее значение | зачёт |")
    print("|---|---|---|---|")
    tally = {}
    for seed in SEEDS:
        for mode in MODES:
            rs = best.get((seed, mode)) or []
            if not rs:
                print("| %d/%s | нет ни одного чистого прогона | — | провал |" % (seed, mode))
                continue
            # По каждому пункту выбираем прогон с наихудшим значением метрики.
            for idx in range(len(criteria(rs[0]))):
                name = criteria(rs[0])[idx][0]
                worst = None
                for r in rs:
                    cr = criteria(r)[idx]
                    if cr[1] is None:
                        worst = ("н/п", cr[2])
                        break
                    if cr[1] is False:
                        worst = (False, cr[2])
                        break
                    if worst is None or worst[0] is True:
                        worst = (True, cr[2])
                ok = worst[0]
                if ok is not None:
                    part = tally.setdefault(mode, {})
                    part[name] = part.get(name, True) and bool(ok)
                print("| %d/%s | %s | %s | %s |" % (
                    seed, mode, name, worst[1],
                    "н/п" if ok is None else ("PASS" if ok else "провал")))
    print("\n### Итог по девяти порогам (%s)\n" % title)
    for mode in MODES:
        part = tally.get(mode) or {}
        if not part:
            print("- режим %s: нет ни одного чистого прогона, мерить нечем" % mode)
            continue
        bad = sorted(n for n, v in part.items() if not v)
        print("- режим %s: пройдено %d из %d; провалено: %s" % (
            mode, len(part) - len(bad), len(part), "; ".join(bad) or "нет"))


def main():
    a = sys.argv[1:]
    if "--" not in a:
        print("нужны две группы меток через --")
        return 2
    i = a.index("--")
    report("БАЗА", a[:i])
    report("ПОСЛЕ ВОЛНЫ", a[i + 1:])
    return 0


if __name__ == "__main__":
    sys.exit(main())
