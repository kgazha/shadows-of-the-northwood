# CONTRACT_PROCGEN — Фаза 2 «процген», канон оркестратора 1.0 (к PROCGEN_PLAN.md)

База: PROCGEN_PLAN.md (решения D1–D5 канон). Здесь — зафиксированные API/схемы/волны. Строки искать по символам, не по номерам.

## 1. API генератора (class_name ProcGen, static, файл scripts/procregion.gd)
- `mixi(a:int,b:int,c:int)->int` — splitmix64-подобный целочисленный перемешиватель (стабильный между платформами: только int64 операции, mask 0xFFFFFFFF для 32-битной совместимости хэшей).
- `seed_zone(run_seed:int, zone_id:String, wave:int)->int` = mixi(run_seed, hash(zone_id), wave).
- `seed_daily(stamp:String)->int` = хэш daily.stamp (зашить, НЕ подключать: daily-run режима нет).
- `cave_map(zone_seed:int)->Dictionary` → `{grid:[String...], meta:{...}}` — форма побайтово = data/map_cave.json (ключи meta: spawn/stairs_out/hermit/boss/boss_trigger/chest — [x,y]; door — [[x,y]] массив пар; имена/структуры читать из фактического JSON).
- `ashen_map(zone_seed:int)->Dictionary` → форма = data/map_ashen.json (spawn, exit_portal, boss, chests:[], herbs:[], mobs:{archers:[], wraiths:[], swarm:{...}}).
- `place_units(...)` — сигнатура T3, в T2 НЕ объявлять.
Железо D3: ни GameState, ни сцен, ни randomize()/randi() — только rng с явным сидом; обход grid строго row-major; никаких Dictionary-итераций в алгоритме раскладки (порядок слотов — фиксированный массив).
Размеры карт: равны фактическим map_cave/map_ashen (map_w/map_h consumers: миникарта, cam-limits).

## 2. Seam (T1)
- `GameState.run_seed: int`, sentinel −1 = legacy. to_dict/from_dict (save v3; версия поднять в save_vault как принято). Миграция: при load без поля/−1 — `run_seed = randi()` (глобальный RNG ДОпустим — это рождение сида, не генерация) и save_game().
- Переброс: в `_wipe_circle()` — `run_seed = -1` (фактический новый сид родит world при первом обращении к seam, если −1; либо сразу randi() в _wipe_circle — выбрать ОДНО и закрепить комментарием; рекомендация: randi() сразу в _wipe_circle).
- В world._ready: `_build_cave()/_build_ashen()` берут словарь из `ProcGen.cave_map(ProcGen.seed_zone(GameState.run_seed, "cave", GameState.ng_wave()))`. В T1 ProcGen — прокси-заглушка, читающая JSON-файлы (поведение 0-дрейфа). Порядок относительно load_game() не меняется (сторожевой qa_rf).
- Границы T1: game_state.gd, world.gd (_ready+билдеры+2 константы), save_vault.gd. Стенды не трогать (qa_sv расширит T6).

## 3. Схема шаблонов комнат (T2-код ∥ T2-шаблоны, пин железный)
Файлы: `data/proc_rooms_cave.json`, `data/proc_rooms_ashen.json`:
```
{ "zone": "cave",
  "rooms": [
    { "id": "c_entry_a",                     // уникальные id
      "tags": ["entry"],                     // entry|boss|chest|hermit|altar|any
      "grid": ["#####","#...#","#...#","#####"],  // строки равной длины, символы СТРОГО из CHAR_TO_TILE своей зоны (dungeon_zone.gd:9-13 / ashen_zone.gd:14-19)
      "anchors": { "spawn": [2,2], "stairs_out": [2,1] } } ] }   // координаты ВНУТРИ шаблона; обязательные слоты по тегу
```
Правила шаблонов: прямоугольник, рамка «#»; интерьер связный; размеры пещерных ≤ 9×9; тег entry → anchors spawn+stairs_out (соседи, 1–2 тайла); boss → boss+boss_trigger на арене «V» (cave)/«a» (ashen, ≥60 тайлов пола, открытые фланги — генератор проколет входы); chest → единственный «C»; hermit → слот hermit; altar → тайлы «A» + якорь altar. Коридоры генератор КАРУЕТ сквозь «#» шириной 2 — двери в шаблонах не нужны и не рисуются.

## 4. Раскладка (T2): сетка комнат ~3×2 (cave), якорный контракт плана §2.2; остов+1–2 кольца; BFS-валидация до эмиссии (связность spawn→все якоря в закрытом состоянии; chest пещеры — в «открытом»), при провале — перераскладка с детерминированной солью (rng-ветка), не рандом.

## 5. Волны выполнения
- **Волна A (параллельно):** T1=сид+seam+прокси; T2-код=procregion.gd (раскладка/коридоры/граф/эмиссия, валидируется ad-hoc прогонами на шаблонах-заглушках в scratch_cm/, в git не писать шаблоны-заглушки); T2-шаблоны=data/proc_rooms_*.json (х-волидация: символы∈алфавиту, якоря∈интерьеру, рамка, связность — ad-hoc скрипт); T6-пре=стенд qa_pg против API §1 (до генератора — компилируется, RALL-гард, плановый RED).
- **Волна B:** T3 = place_units (золотой-тест: ручная карта пещеры → прежние 11 брутов) + data/proc_profiles.json; перевод хардкодов леса/тенеплётов на механизм (литерал-профили).
- **Волна C:** T4 (cave под генератором) ∥ T5 (ashen + D4 uid `chest@<area>:x,y`, старые ключи валидны) — мир делят по функциям строго; затем T6-полный (golden 42, 50 сидов, пин-сид qa_z1/qa_q5, qa_sv сид-раундтрип) + регистрация qa_pg оркестратором.
- **Финал:** батарея 33/33 GREEN.

## 6. Границы (нарушение = откат)
T1: game_state.gd, world.gd, save_vault.gd. T2-код: scripts/procregion.gd (+.uid), scratch_cm/. T2-шаблоны: data/proc_rooms_cave.json, data/proc_rooms_ashen.json (+ ad-hoc валидатор в scratch_cm/). T6-пре: tools/qa/stand/qa_pg.* (manifest — только оркестратор). Никому: hud.gd, journal.gd, mob_*, dialogues*.

## 7. Проверка
Каждая доставка: смоук Godot (--import, --quit-after 240, whitelist-шум) + затронутые стенды + детерминизм-тест (два прогона генерации — идентичный вывод; golden: один зашит). Доставка: diff в scratch_cm/ (манифест MD5, CRLF) + правки в дерево; battery-вердикт на мерже за оркестратором.

## 8. Факты принятого T2 (2c8a70e) — дополнения к контракту
- **Хеши-канон (две схемы, не путать):** T2-отчётный = `JSON.stringify(map).hash()` (FNV32, порядок вставки): cave42=973020700, ashen42=315586922. Пин qa_pg (PG2) = FNV-1a 64 по канонической сериализации (ключи словарей сортируются рекурсивно, массивы по порядку, строки в кавычках). Значения пина снимаются прогоном qa_pg и фиксируются здесь после фикса PG8a.
- **Допущения генератора (пиняются как контракт для T3/T4/T5):** «zone» в схемах шаблонов — уровня файла (не комнаты); anchors = ключи ключей meta-словаря карты (spawn/boss/chest/hermit/exit_portal/boss_trigger), локальные координаты в рамке; **altar-якоря игнорируются** (ключа altar в статичном формате map_cave.json нет — алтарь вне генерации); chest: 'C' в сетке комнаты → meta.chest, иначе штамповка 'C' в якоре, дверь в нишу по смежности; 'L' ровно одна, MST из сундука не растёт (leaf), кольца через сундук не идут; walkable: пещера B/M/S + (L/C по открытости), ashen арены 'a' и P; ashen scatter: archers=3, wraiths=4, swarm=4, herbs=3 (min_spawn 4/6/6/5); MARGIN=0 между комнатами (рамки=стены).
- **Известный дефект (в работе, фикс = pg_t2_fix.diff):** PG8a — 12-клеточное кольцо воздушного зазора вокруг комнаты-сундука на части сидов не сообщается с главным полом (OPEN-state, пещера). Критерий стенда: карманы ≥2 запрещены, одноклеточные терпимы (§3.2.5).
- **Стенд qa_pg:** 25 строк вердикта (24 проверки + RALL), 50 сидов `97531+i*7919`; в манифесте пока НЕ зарегистрирован — регистрация вместе с golden-пинами после PG8a-фикса.

## 9. Статус волн (актуально на 868f97c)
Волна A: ✅. T5a c697c16, T5b df44741 (qa_z1 пин-сид 42, 67 проверок), T3 5adb01c (place_units+proc_profiles.json), T4 868f97c (пещера из cave_map, мобы из place_units, стенды на пин-сиде 42: qa_q5/qa_s5/qa_rf/qa_r1/qa_r2/mb_base+mb_1). Батарея 33/33 GO (663 проверки). В работе: T6-остаток (qa_pg PG10 place_units-блок). Остаток волн D: финальная батарея на последнем HEAD.
- **ФАКТ-КАРТА seed 42 (стендовая реальность, ng_wave()=0, zone_seed=1323545855):** spawn(4,3) stairs(4,2) hermit(18,17) boss(16,8) trigger(16,10) chest(9,12) door(10,12) approach(11,12) ниша(9,13) wraiths(15,7),(16,7) place_units=10. Контрактная цепь wave 1 (zone_seed=454322940): spawn(14,5) stairs(14,4) hermit(13,17) boss(24,13) trigger(24,14) chest(5,15) door(5,17), units=12.
- **Найденное вне рамок (бэклог):** qa_rf s5 (вне battery-покрытия, предсуществующий баг): achv._ready→_daily() на legacy-сейве без daily.stamp выдаёт +15 зол. и set_flag(daily.*). mb_3 — soak-флейк (краснеет ~1/6 в плотном каскаде, изолированно стабилен).
