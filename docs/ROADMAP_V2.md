# ROADMAP v2 — путь к релизу на VK Play (волна «контент»)

Решение пользователя (2026-11-10):.graphics = как есть; направления A+B+C+D одновременно.

## Волна 1 (параллельные авторы, каждый в своей песочнице sand_X)

| Агент | Песочница | Файлы-владение (только новые!) | Что делает |
|---|---|---|---|
| quest | sand_q | quests_data.gd, journal.gd | Реестр квестов + журнал (клавиша J), обёртки над elder/slime/cave-квестами GameState, тосты «квест обновлён», цели-хуки |
| econ  | sand_e | gear_data.gd, shop.gd, loot.gd | Реестр предметов/цены, лавка у старосты (панель), лут-таблицы мобов и сундуков, монеты |
| mobs  | sand_m | mob_archer.gd, mob_wraith.gd, mob_swarm.gd | 3 архетипа: лучник (держит дистанцию, телеграф), призрак (фазит, проходит стену на коротко), рой (мелкие, стаей). Фабрики spawn() |
| cmove | sand_cm | click_move.gd | ПКМ-клик-перемещение поверх nav.gd: синтез WASD-событий (player.gd НЕ трогаем), отмена любой живой кнопкой/WASD/атакой/уклоном, флаг user://clickmove_cfg.json |
| settings | sand_s | settings_menu.gd | Меню (Esc): громкости Music/SFX (GameAudio.set_volumes), вкл/выкл click_move (статический accessor из click_move.gd), позиция окон/тени заглушки. user://settings.json |

Правила для всех (детально — в промпте агента):
1. Владение = НОВЫЕ файлы. Существующие (world/hud/player/interactable/npc/slime/brute/game_state...)
   не правятся: вместо этого в конце отчёта раздел «ИНТЕГРАЦИОННЫЕ ЗАПРОСЫ» — точные
   однострочные хунки, которые применяет ТОЛЬКО оркестратор.
2. project.godot не трогать никогда. Autoload не просить: синглтоны — паттерн GameAudio
   (static var I + создание из world._ready()) или class_name + static-реестры.
3. Хендофф: `git diff` из песочницы в корень W как `sand_X.diff` (LF, табы, a/pixel-rpg/...),
   в отчёте MD5 базы/каждого файла, список новых файлов. Оркестратор: `git apply --check`
   против HEAD, применение, fix_mojibake dry-run, смоук, коммит.
4. Кодировка: файлы в UTF-8 без BOM, LF; русские строки проверять после записи (нет C1/тофу).
   Файлы НЕ переписывать целиком — минимальные правки.
5. Смоук: tools/godot/Godot_v4.7.2-stable_win64.exe --headless --path pixel-rpg
   --quit-after 240 c APPDATA=tools/appdata_X (создать!). 0 SCRIPT ERROR; юзер-сейвы не
   трогать (харнес-режимы чистят save_morkheim.json — это штатно).
6. QA-харнесы qa_* — временные, в дифф НЕ попадают (git status чистый, кроме новых файлов).

## Фундамент (уже в HEAD до волны 1)
- Музыка WAV→OGG: 21.5 МБ → 1.5 МБ (q5 libvorbis); game_audio.MUSIC → .ogg, WAV — эталоны,
  исключить из экспорта фильтром.
- Save v2 (game_state.gd): `v:2`, `gold`, `gear{weapon,armor}`, `flags{}` + API
  add_gold/spend_gold/can_afford/equip_item/get_flag/set_flag, legacy-миграция has_sword→gear.
- Signal gold_changed → автосейв.

## Интеграция после волны 1 (оркестратор)
Хунки интеграционных запросов применяю сам (по одному, между ними — смоук), затем
адверсариальные QA-агенты на каждую влитую фичу, затем коммит волны.

## Волна 2 (после влития 1-й)
- WebGL-экспорт: export_presets.cfg (threads=off, файлы-фильтры WAV/инструментов),
  скрипт tools/export_web.bat, замер пайлайна, ZIP для VK Play. Шаблоны: tools/export_tpl/templates.tpz
  (1.2 ГБ, качается) → распаковать web_*.wasm3x.zip в %APPDATA%\Godot\export_templates\4.7.2.stable\.
- Вторая зона (болото) + босс №2; NG+; достижения VK.
- Полировка: цифры урона, мини-карта/стрелка цели.

## Риски
- hud.gd/world.gd — перегретые файлы: только оркестратор.
- Квест-данные не ломают старые сейвы: elder/slime/cave поля GameState остаются каноном.
- game_state.gd после фундамента правит только оркестратор (хунки от econ/quest).
