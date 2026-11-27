"""t33: сводка переписи из census_*.json в markdown-таблицы (без ручного переписывания).

Запуск: python -u diag-t33/census_table.py [подстрока_файла ...]
Без аргументов берёт все diag-t33/out/census_*.json.
"""
import glob
import io
import json
import os
import sys

D = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(D, "out")


def load(sub):
    files = sorted(glob.glob(os.path.join(OUT, "census_*.json")))
    if sub:
        files = [f for f in files if any(s in os.path.basename(f) for s in sub)]
    rows = []
    for f in files:
        with io.open(f, encoding="utf-8") as fh:
            r = json.load(fh)
        r["_tag"] = os.path.basename(f)[len("census_"):-len(".json")]
        r["_walk"] = sum(v["walk_px"] for v in r["zones"].values())
        rows.append(r)
    return rows


def f2(v):
    return "-" if v is None else ("%.2f" % float(v))


def main():
    rows = load(sys.argv[1:])
    if not rows:
        print("нет файлов")
        return
    print("### А. Главная таблица «скучно вот тут»\n")
    print("| прогон | мин | (а) чистой ходьбы без боя, мин | (а) largest сухой кусок, с "
          "| (б) контактов/мин | (б) контактов/1000 px | (в) доля угроз | (г) смерти "
          "| (д) вау-лут, с | (д) подземелий до него | (е) решений драться/бежать "
          "| из них со ставкой | окна, с |")
    print("|---|---|---|---|---|---|---|---|---|---|---|---|---|")
    for r in rows:
        wow = "-" if r["wow_sec"] < 0 else f2(r["wow_sec"])
        dbw = "-" if r["dungeons_before_wow"] < 0 else str(r["dungeons_before_wow"])
        c1k = f2(1000.0 * r["contact_events"] / r["_walk"]) if r["_walk"] > 50 else "-"
        print("| %s | %s | %s | %s | %s | %s | %.3f | %d | %s | %s | %d | %s | %s |" % (
            r["_tag"], f2(r["minutes"]), f2(r["walk_pure_min"]), f2(r["dry_max_sec"]),
            f2(r["contacts_per_min"]), c1k, r["threat_share"], r["deaths"],
            wow, dbw, r["decisions"], r.get("bets", "-"), f2(r["locked_sec"])))

    print("\n### Б. Побочно: драка, награда, движение\n")
    print("| прогон | стычек | врагов встречено | first strike | заставили лечиться "
          "| заставили отступить | урона получил | урона нанёс | убил | вещей | сундуков "
          "| золота | лучшее качество | пешком px | приказов ПКМ | кадров под приказом "
          "| плеч | bfs-отказ | застреваний, с |")
    print("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
    for r in rows:
        print("| %s | %d | %d | %d | %d | %d | %d | %d | %d | %d | %d | %d | %d | %d | %s | %s | %s | %s | %s |" % (
            r["_tag"], r["encounter_groups"], r["enemies_met"], r["first_strike"],
            r["forced_heal"], r["forced_flee"], r["dmg_taken"], r["dmg_dealt"], r["kills"],
            r["gear_items"], r["chests"], r["gold_total"], r["best_quality"],
            int(r["_walk"]), r.get("orders", "-"), r.get("cm_frames", "-"),
            r.get("leg_max", "-"), r.get("bfs_fail", "-"), f2(r["stuck_sec"])))

    print("\n### В. Поминутно: где именно мертво (зона × прогон)\n")
    print("| прогон | зона | мин | контактов/мин | контактов/1000 px | сухой кусок макс, с "
          "| сухих секунд всего | врагов | урона получил | урона нанёс | лута | трав "
          "| тычков E | пешком px |")
    print("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
    for r in rows:
        for z in sorted(r["zones"].keys()):
            v = r["zones"][z]
            zc1k = f2(1000.0 * v["contacts"] / v["walk_px"]) if v["walk_px"] > 50 else "-"
            print("| %s | %s | %s | %s | %s | %s | %s | %d | %d | %d | %d | %d | %d | %d |" % (
                r["_tag"], z, f2(v["sec"] / 60.0), f2(v["contacts_per_min"]), zc1k,
                f2(v["dry_max_sec"]), f2(v["dry_sec"]), v["enemies_met"],
                v["dmg_taken"], v["dmg_dealt"], v["loot_items"], v["heals"],
                v["interacts"], int(v["walk_px"])))

    print("\n### Г. Переходы (штатные или программные) и заметки\n")
    for r in rows:
        tr = "; ".join("%s→%s @%.0f с" % (a[1] or "старт", a[2], a[0] / 60.0)
                       for a in r["areas"]) or "нет переходов"
        back = ""
        seen = {}
        for a in r["areas"]:
            seen[a[2]] = seen.get(a[2], 0) + 1
        again = [z for z, n in seen.items() if n >= 2 and z != "village"]
        print("- **%s**: %s | возврат: %s" % (r["_tag"], tr, ", ".join(again) or "нет"))
        for n in r["notes"]:
            print("    - %.0f с: %s" % (n[0] / 60.0, n[1]))

    print("\n### Д. Воспроизводимость (одинаковый сид дважды)\n")
    by = {}
    for r in rows:
        cfg = r["cfg"]
        by.setdefault((str(cfg.get("mode")), str(cfg.get("seed"))), []).append(r)
    keys = [("minutes", 2), ("contact_events", 0), ("contacts_per_min", 2),
            ("dry_max_sec", 1), ("threat_share", 3), ("enemies_met", 0), ("deaths", 0),
            ("decisions", 0), ("bets", 0), ("gear_items", 0), ("kills", 0),
            ("dmg_taken", 0), ("walk_pure_min", 2), ("gold_total", 0)]
    print("| метрика | режим/сид | значения | разброс |")
    print("|---|---|---|---|")
    for k, dec in keys:
        for kk, rs in sorted(by.items()):
            vals = [x.get(k) for x in rs]
            if any(v is None for v in vals) or len(vals) < 2:
                continue
            fmt = ("%." + str(dec) + "f") if dec else "%d"
            print("| %s | %s/%s | %s | %s |" % (
                k, kk[0], kk[1], " ; ".join(fmt % v for v in vals),
                fmt % (max(vals) - min(vals))))


if __name__ == "__main__":
    main()
