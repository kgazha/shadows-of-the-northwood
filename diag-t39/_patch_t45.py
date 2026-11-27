# -*- coding: utf-8 -*-
# t45-аддендум: три правки МЕРКИ в зонд переписи (предложил разбор t45, исполняет qa-gate).
import io
p = r"diag-t33/census_t33.gd"
s = io.open(p, encoding="utf-8").read()
n = 0

def rep(a, b, tag):
    global s, n
    assert s.count(a) == 1, "якорь не найден: " + tag
    s = s.replace(a, b); n += 1

rep("var cm_frames := 0\n",
    "var cm_frames := 0\n"
    "# t45-аддендум (27.11, qa-gate): собственные счётчики плана ClickMove. Прежний\n"
    "# trace печатал только НАШ план (path_cells), который легально пуст, когда приказ\n"
    "# делегирован игре, и «путь=0/0 следующая=нет» читалось как «в игре нет пути».\n"
    "# Разбор t45 показал обратное: из той же точки игра строит путь в 5 точек.\n"
    "var cm_path_n := 0\nvar cm_path_idx := 0\nvar cm_stall_rp_max := 0\n", "cm_frames")

rep("func _cm_driving() -> bool:\n",
    "func _cm_stats() -> void:\n"
    "\t# t45-аддендум: снимаем внутренности плана игры в свои счётчики каждый кадр.\n"
    "\tcm_path_n = 0\n\tcm_path_idx = 0\n\tvar cm := _cm()\n"
    "\tif cm == null:\n\t\treturn\n"
    "\tvar p: Array = cm.get(\"_path\") as Array\n"
    "\tcm_path_n = p.size()\n\tcm_path_idx = int(cm.get(\"_idx\"))\n"
    "\tcm_stall_rp_max = maxi(cm_stall_rp_max, int(cm.get(\"_stall_rp\")))\n\n\n"
    "func _cm_driving() -> bool:\n", "_cm_driving")

rep("\t_order_pump()\n\t_policy()\n\t_walk_clock()\n",
    "\t_order_pump()\n\t_policy()\n\t_cm_stats()\n\t_walk_clock()\n", "тик")

rep('путь=%d/%d подсказок=%d', 'путь=%d/%d план_игры=%d/%d подсказок=%d', "строка бота")
rep("path_idx, path_cells.size(), nr.size(), int(GameState.get(\"hp\")),",
    "path_idx, path_cells.size(), cm_path_idx, cm_path_n, nr.size(), int(GameState.get(\"hp\")),",
    "аргументы строки бота")

rep('путь=%d/%d следующая=%s retries=%d цель=%s',
    'путь=%d/%d следующая=%s план_игры=%d/%d перекладок_игры=%d retries=%d цель=%s', "строка встанки")
rep("\t\t\t\tretries, goal_kind])",
    "\t\t\t\tcm_path_idx, cm_path_n, cm_stall_rp_max, retries, goal_kind])", "аргументы встанки")

rep("\tif intends and frame - last_moved_frame > 600:\n",
    "\t# t45-аддендум: предел вастдога поднят над ЗАКОННЫМ простоем у цели.\n"
    "\t# Максимальный hold в списке марша — 12 с = 720 кадров; прежний порог 600\n"
    "\t# кадров (10 с) срабатывал раньше конца законной задержки и записывал её\n"
    "\t# как «встанку». Учёт stuck_sec НЕ изменён (окна по 25 кадров), поэтому\n"
    "\t# браковка сравнима с базой; изменился только момент «цель сброшена».\n"
    "\tif hold_until < 0 and intends and frame - last_moved_frame > 840:\n", "вастдог")

rep('\t\tGameState.call("start_new_run")\n',
    '\t\tGameState.call("start_new_run")\n\t\t_clear_taken_flags("рестарт после мягкой смерти")\n', "рестарт")

rep("func _add_count(d: Dictionary, k: String) -> void:\n",
    "## t45-аддендум (27.11): прогон обязан начинаться с ЖИВЫми точками интереса.\n"
    "## Разбор t45: на марш-прогоне 777 бот маршировал к поляне, чей флаг fw.glade_taken\n"
    "## уже был снят сбором, — держание у пустой цели мерка записывала как геометрическую\n"
    "## встанку. Снимаем только флаги сбора (*_taken), ничего больше.\n"
    "func _clear_taken_flags(why: String) -> void:\n"
    "\tvar cleared: Array = []\n"
    "\tfor k in GameState.flags.keys():\n"
    "\t\tif String(k).ends_with(\"_taken\") and int(GameState.flags[k]) != 0:\n"
    "\t\t\tGameState.flags[k] = 0\n\t\t\tcleared.append(String(k))\n"
    "\tif not cleared.is_empty():\n"
    "\t\t_note(\"мерка: сняты флаги сбора (%s): %s\" % [why, \", \".join(cleared)])\n\n\n"
    "func _add_count(d: Dictionary, k: String) -> void:\n", "_add_count")

rep('\t\t"panels_closed": panels_closed,\n',
    '\t\t"panels_closed": panels_closed,\n\t\t"cm_stall_rp_max": cm_stall_rp_max,\n', "json")

io.open(p, "w", encoding="utf-8").write(s)
print("правок применено: %d" % n)
