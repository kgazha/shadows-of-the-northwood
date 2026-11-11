# DEV-NOTES — «Тени Северного Леса» (пиксельная RPG для VK Play)

> Журнал контекста разработки. Любая новая сессия ИИ-ассистента должна начать с этого файла.
> Обновлять при каждом значимом изменении.

## Текущий статус (фаза 6)

✅ **Фаза 6 + костры/алхимия + FX-частицы + процедурная музыка/звуки + пещера с боссом
(ребаланс ярусами) + QA-фиксы T1–T10 + персистентность двери/сундука/призраков +
Kenney 9-slice рамки/прицел + лицензии CC0 — ВСЁ В MAIN.**
Headless-смоук чистый (exit 0, SCRIPT ERROR 0). Ждёт живой проверки игроком (чек-лист ниже).

- Движок: **Godot 4.7.2 stable** (портативный, `tools/godot/`), рендер GL Compatibility.
- Git (последние): `5a01fa2` camps+alchemy → `29992b4` FX → `6b91493` music → `748f62d` cave →
  `9def4b9` audio → `ddc0539` qa2 → `707a5e9` qa-fixes T1–T10 → `fb3ae96` door → `6a82877` polish →
  `4d74fd0` chest → `8cc0efa` ghosts → `8cac008` UI → `90d08c6` meta → `2387e53` тени (якоря+region) →
  `f21671a` lock-guard → `ee0b879` dialog-hardening → `aee8731` тени round2.
- Лицензии: `pixel-rpg/LICENSES.md` — все сторонние ассеты CC0 (Kenney RPG Audio, UI Pack
  Pixel Adventure, Cursor Pixel Pack через зеркала GitHub); своё (FX-текстуры, synth UI-звуки,
  процедурная музыка) — тоже CC0. **Политика: только CC0/CC-BY, NEVER NC** (коммерческий релиз).

## Как запустить / проверить

- Игрок: двойной клик `start-game.bat` (сейвы в `tools/appdata`).
- Смоук: `& tools/godot/Godot_v4.7.2-stable_win64.exe --headless --path pixel-rpg --quit-after 240`
  — игнорировать «Failed to read the root certificate store» (шум); судить по отсутствию SCRIPT ERROR.
- После правки ассетов / новых class_name: сначала прогон с `--import`.
- Тайминг-тесты: флаг `--fixed-fps 60` (иначе физика/твины в headless врут).
- ВНИМАНИЕ: `push_input` в headless НЕ двигает GUI-хиттестинг — клики мышью проверяются
  только живым запуском или прямым вызовом методов. Реальные баги от игрока важнее зелёных тестов.
- Сейв пользователя: `tools/appdata/Godot/app_userdata/Тени Северного Леса/save_morkheim.json`
  (герой=лучник). ПЕРЕД тестами, пишущими GameState, ДЕЛАТЬ БЭКАП; агенты пишут только в свои
  `tools/appdata_*`.

## Управление

- **WASD** — прямое движение. **ЛКМ** — атака в сторону курсора (удержание = автоповтор).
  **Пробел** — кувырок с i-frames (~37px, КД ~0.9 с). **E** — взаимодействие/«далее».
  **1–4** — скиллы. **Q** — зелье. **F5/F9** — сейв/лоад. Автосейв: level-up, квесты, дверь.
  Клик-приказов нет; `nav.gd`/`build_path` оставлены про запас (pet/autoroll), в бою не нужны.

## Ключевые механики (сверх фазы 5 — см. git log)

- **Классы** (`classes_data.gd`): warrior hp12/melee, archer hp8/range80, mage hp6/range70.
  XP-кривая ×1.6. Урон — getter (записи в `damage` игнорировать!). Смена класса запрещена.
- **Реген**: вне боя +1 HP/4 с, маг +2 маны/2 с; «в бою» = 6 с после контакта.
- **Костры** (`campfire.gd`): ОДИН на мир — `CAMPFIRE_SPOTS` cf_village(18,13) (замысел сложности, ebe610e);
  отдых 4 с → +6 HP, ОДНОРАЗОВЫЕ, состояние в сейве (`_resync_campfires()` после load/quickload!).
- **Алхимия**: материалы (suhotsvet/zhim) с трав и мобов; MAT_CAP 5, BREWED_CAP 2;
  слаймы дроп 0.25; мобы пещеры (не босс) тоже 0.25 (`brute._roll_mat_drop`);
  выпить можно ТОЛЬКО вне боя (`combat_t` гейт).
- **Пещера** (`dungeon_zone.gd`): ярусы мобов по удалённости от входа (Чебышёв):
  tier1 {4..7} cap3 hp6/dmg1/spd24, tier2 {8..11} cap4 hp9/dmg2/spd29, tier3 {12..} cap5 hp12/dmg2/spd33;
  LEASH 64. Босс: hp24/dmg3/spd34, рывок КД 4.0; **тревожная музыка** при первой агрессии
  (радиус LEASH), возврат эмбиента пещеры после смерти в пещере.
- **Звук/музыка** (`game_audio.gd`): НЕ autoload — `class_name GameAudio`, `static var I`,
  add_child в world._ready. Шины Music/SFX создаются рантаймом; конфиг `user://audio_cfg.json`;
  пул 8 плееров SFX; `music()` — кроссфейд 1.5 с, реестр forest/cave/tension. WAV-луп
  выставляется в коде `_enforce_loop` (в .import не работает). Все play_sfx guarded через
  ResourceLoader.exists — отсутствие файла не роняет игру.
- **Персистентность «построено до загрузки»** — ПАТТЕРН ФАЗЫ: world._ready() строит мир
  строкой 102, а `GameState.load_game()` — строкой 113, поэтому любые флаги из сейва приходят
  ПОСЛЕ сборки. Решение — подписка на `GameState.stats_changed` + идемпотентные ресинки:
  `_sync_door()` (дверь ниши), `_sync_cave_chest()` (world: коллайдер сундука), `_sync_chest()`
  (dungeon_zone: тайл+призраки). Плюс охранные проверки в `try_interact` (нет повторного
  heal(4) из сундука, нет повторного save от двери). `has_amulet` — канонический признак
  открытого пещерного сундука ( НЕ chests_used — тот только для деревенских).
- **Сундуки деревенские**: `chests_used` (uid `"chest@x,y"`) в GameState, персистентны.
- **UI-полировка**: `assets/ui/panel_frame.png` (Kenney 32×32 nine-slice, палитр-своп) —
  StyleBoxTexture на диалог (content 4), skill_panel (4), camp_panel (3); у StyleBoxTexture
  `texture_margin_*` — INT (float = SCRIPT ERROR), у NinePatchRect `patch_margin_*` — FLOAT.
  Полоса отдыха = NinePatchRect и ОБЯЗАНА быть `move_child` после camp_panel (PanelContainer
  вырастает до y=322 и иначе её перекрывает — исправленный базовый баг). Курсоры:
  `cursor_crosshair.png` (hotspot 8,8) в мире / `cursor_arrow.png` (0,0) при input_locked,
  враг — красный `cur_enemy` (хук `world._update_cursor`, project.godot не тронут). Тосты —
  намеренно без рамки (прозрачный Label с обводкой поверх мира).
- **Тени** (`atmosphere.gd _ensure_shadow`): лист `assets/shadow.png` 32×16 = два блоба:
  персонаж `Rect(0,0,16,6)`, босс `Rect(8,7,24,9)` — **region enabled ВСЕГДА** (без него у всех
  рисовался весь лист — «призрачная тень» вдали). Позиция — по ИЗМЕРЕННЫМ якорям стоп
  (низ непрозрачных пикселей спрайта, AtlasTexture — по region!, кэш по instance_id с проверкой
  тождества текстуры; инструмент `tools/shadow_dump.js`). Тень — child ПЕРЕД спрайтом,
  modulate (0,0,0,.5). Видимость тени синхронна со спрайтом (пик травы/пепел костра — без тени;
  страховка в `_sync_shadow` при скане). `_on_child_entered` сканирует только вошедшее поддерево,
  полный скан с дебаунсом 0.15 с (иначе FX-шторм = 19% бюджета кадра).
- **Анти-софтлок ввода** (класс «убил слайма — не могу двигаться, F9 не лечит»): `input_locked` —
  рантайм-var, НЕ сериализуется; залипший true переживает F9 (сам F9 глушится веткой locked) и
  снимается только рестартом. Инвариант `f21671a`: в world._unhandled_input — лок без открытой
  панели/модалки снимается первым же вводом. `ee0b879`: hud держит очередь `pending_ends`
  (перетёртый show_dialog колбэк не теряется — респавн после чужого диалога гарантирован),
  хвост transition_to НЕ снимает лок при открытом диалоге. Правила: любую панель закрывать
  только через advance()/свой разлок; новый set-true input_locked обязан иметь «мёртвую» отмычку.
- **FX** (`world.gd`+`player.gd`): удары/смерти/лут — частицы из `tools/gen_fx_assets.js`
  (свои CC0-текстуры). `player` при смерти не залипает в прозрачности (qafix).
- **Сейвы**: null-safe `from_dict` (`_num/_numf/_flag/_str`) — битый/старый JSON не роняет;
  HP-потолок: класс/уровень → recalc → hp из сейва.
- **Зоны**: деревня + пещера (y+=4800). Переходы fade-твином. Квест-цепочка: отшельник →
  босс → ключ → дверь(17,18) → сундук(18,18) → амулет → финал. Смерть = мягкая (костёр деревни).

## Структура

```
pixel-rpg/
  project.godot           input: move_*, interact(E), attack(LMB), roll(Space), skill_1..4, potion(Q), F5/F9
  scenes/main.tscn        ЕДИНСТВЕННАЯ сцена: Node2D + world.gd (всё строится кодом в _ready!)
  scripts/world.gd        мир: зоны, карта, ввод, диалоги, квесты, save/load, FX-хуки, _sync_* ресинки
  scripts/game_audio.gd   class_name GameAudio + static var I (НЕ autoload!); музыка/SFX/лупы
  scripts/player.gd       герой: движение WASD, атака к курсору, кувырок, скиллы, снаряды
  scripts/game_state.gd   autoload GameState: флаги/сейвы/null-safe from_dict/chests_used/автосейвы
  scripts/hud.gd          CanvasLayer: HP/мана/XP/тосты/диалоги/панель скиллов/маркер/создание героя
  scripts/dungeon_zone.gd пещера: ярусы мобов, дверь/сундук (сериализ.), босс-триггер, _sync_door/_sync_chest
  scripts/brute.gd        босс: погоня+рывок, tension music, мат-дроп у не-боссов
  scripts/slime.gd, campfire.gd, interactable.gd, npc.gd, projectile.gd, atmosphere.gd, nav.gd
  scripts/classes_data.gd справочник CLASSES/SKILLS (баланс здесь)
  assets/…                tiles/players/slime/brute/dungeon_tiles/decor + sfx/ + music/ (WAV)
  data/map_village.json, data/map_cave.json, data/dialogues*.json
  LICENSES.md             все права (CC0), обновлять при добавлении ассетов
tools/
  gen_assets.js → gen_assets2.js → gen_assets3.js   (ПОРЯДОК ОБЯЗАТЕЛЕН; v3 = тёмное фэнтези)
  gen_fx_assets.js, gen_music.js (+verify_wav.js), gen_ui_sfx.js — генераторы FX/звуков
  gen_map.js, gen_map_cave.js (DEADLOCK-проверка достижимости!)
  png_check.js, dl.js (единственный сетевой доступ), godot/, appdata_*/ (песочницы агентов)
docs/DESIGN_v2_classes.md, QA-REPORT.md, RETENTION-REPORT.md
start-game.bat
```

## Пайплайн ассетов (детерминированный)

1–4. Генераторы (порядок!): `gen_assets.js` → `gen_assets2.js` → `gen_assets3.js` → карты.
   FX/звук: `gen_fx_assets.js`, `gen_music.js`, `gen_ui_sfx.js`.
5. Godot с `--import` (новые PNG/WAV).
6. `node tools/png_check.js pixel-rpg/assets/<файл> 16 16` — 256 непр. пикселей/клетку.
   Листы героя 48×64 (3×4, ряды down/left/right/up), slime 32×16, brute 64×32.
Kenney-ассеты (растровые) скачаны в `tools/assets_in/ui/` (633 PNG, проверены сигнатурами).

## Грабли Godot 4.7 + процесса (проверено на себе)

- CanvasLayer overlay ОБЯЗАТЕЛЬНО `mouse_filter=IGNORE` (иначе ест клики).
- `push_input` headless не двигает GUI-хиттест; `var x := load(...).instantiate()` — без типа.
- `PhysicsPointQueryParameters2D.position`; TileMapLayer: `get_cell_atlas_coords`;
  `String(null)` — ошибка (str() ок); `gui_get_hovered_control()`; лямбды захватывают по значению.
- AudioStreamWAV: зацикливание ТОЛЬКО в коде (LOOP_FORWARD + loop_end=length*mix_rate).
- project.godot — CRLF; агентам editing ЗАПРЕЩЁН (autoloads добавляет только оркестратор).
- .gd в main — CRLF, диффы агентов — LF: MD5 «фикса» из песочницы и после применения РАЗНЫЕ —
  это норма; сверять `git diff --no-index -w` (пусто = идентично) или совпадение с агентским MD5
  после git apply (git нормализует). Байтовые проверки — В NODE, не PowerShell (5.1 vs 7:
  `-Encoding Byte` vs `-AsByteStream`).
- `git apply` в интерактиве из-под корня W может «Skipped patch» — надёжный гейт:
  `git apply --check` из корня + применение на чистую копию вне репо.
- Голова: `--quit-after N` (парс-ошибка = вечный job). Реген-сигналы дёргают `stats_changed`
  часто — ресинки должны быть идемпотентными и дешёвыми.

## Команда-конвейер (мультиагент) — режим конвейера

Пользователь требует МАКСИМАЛЬНОЙ параллелизации (5–6 агентов). Схема: автор фичи + независимый
адверсариальный QA на фичу; оркестратор — только интеграция/стаджинг/сеть. Агенты:
- работают в своей песочнице `sand_X/pixel-rpg` (копия без .godot), APPDATA/LOCALAPPDATA — свои;
- в main НЕ пишут; хендофф = `git`-дифф в корень W (LF, табы, заголовки `a/pixel-rpg/...`),
  с MD5 базы и фикса, `git apply --check` против АКТУАЛЬНОГО HEAD (перепроверять у оркестратора!);
- сеть только через оркестратора (одноразовая прозрачная эскалация pwsh с видимой командой);
- QA-харнесы (`qa_*`) — временные, в дерево не коммитить.
- **ЗАКОН КОДИРОВОК (грабли aee8731)**: агент, переписывающий файл целиком, может протащить
  двойное перекодирование UTF-8→CP1252→UTF-8: кириллица становится mojibake + невидимыми
  C1-символами, игра рисует «иероглифы» (тофу) в текстах. MD5-совпадение агента с собой ЭТОГО
  НЕ ЛОВИТ. После применения диффа на файлы с русским текстом: `node tools/fix_mojibake.js <файлы>`
  (dry-run, «changed lines» должен быть 0) и скан на C1/U+FFFD; ремонт — реконструкцией из
  чистой git-базы + чистых добавленных строк, а не посимвольной заплаткой.
Харнеси-наследие: sand_cave qa_c1..c5 (688), qa_c3b (686), sand_door qa_d1 v3 (10 режимов),
sand_polish qa_polish (16), sand_sfx audio_tests. Перед прогонами, пишущими GameState, — свежий
`user://save_morkheim.json` (иначе автосейв сам открывает сундук/дверь и ломает ожидания).
Режим оркестратора (уточнение 2026-11-10, волна v2): оркестратор пишет ТОЛЬКО контракты-фундамент
(общие конфликтные файлы save/registry), интеграционные хунки, сеть, staging. Всё остальное —
агентам, включая проверку работы самого оркестратора (sand_fq: адверсариальный QA фундамента).

## Идеи / бэклог

- **VK-сборка**: WebGL-экспорт (export_templates.tpz ~1.2 ГБ; потоки выключить), VK Bridge;
  музыка WAV→OGG (~21MB экономии).
- Перенос `GameState.load_game()` ДО `_build_cave()` в world.gd — устранил бы саму причину
  ресинков (аккуратно: `_resync_campfires` завязан на текущий порядок).
- Q-зелье без боевого гейта (несогласованность дизайна — осознанно оставлено).
- Опция: Kenney Particle Pack вместо своих FX-текстур (инструкция в лицензиях).
- Экономика торговца; автоплитка стен пещеры; диалоги во время fade (не проверялись вживую).
- **ПОЛЬЗОВАТЕЛЬ ЕЩЁ НЕ ВИДЕЛ ГЛАЗАМИ**: костры, FX, управление, арт v3, звук/музыка,
  пещерный ребаланс, фиксы T1–T10, UI-рамки/прицел — обязать прогнать чек-лист в живом окне.
