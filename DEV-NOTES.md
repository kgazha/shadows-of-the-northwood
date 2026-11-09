# DEV-NOTES — «Тени Северного Леса» (пиксельная RPG для VK Play)

> Журнал контекста разработки. Любая новая сессия ИИ-ассистента должна начать с этого файла.
> Обновлять при каждом значимом изменении.

## Текущий статус (2026-11-09)

✅ **Вертикальный срез готов и играбелен** (проверено headless-прогоном и живыми запусками, exit 0).

- Движок: **Godot 4.7.2 stable** (портативный, `tools/godot/`), рендер GL Compatibility.
- Игра: деревня Морхейм + лес; герой с анимацией, 3 NPC, 2 квестовые цепочки, слаймы с ИИ,
  сундук с мечом, опыт/уровни, сердца HP, диалоги с портретами и эффектом печати, F5/F9 сейвы.
- Все ассеты — процедурно сгенерированы (см. «Пайплайн»).

## Как запустить

- Двойной клик по `start-game.bat` (в корне workspace) — сохраняет всё в `tools/appdata`.
- CLI: `tools/godot/Godot_v4.7.2-stable_win64.exe --path pixel-rpg`
- Редактор: тот же exe с флагом `-e --path pixel-rpg`
- Управление: WASD/стрелки — ходьба; E — диалог/действие; Пробел — атака; F5/F9 — сейв/лоад.

## Структура

```
pixel-rpg/               проект Godot
  project.godot          конфиг (input-мапа, viewport 640x360, nearest-фильтр, snap)
  scenes/main.tscn       единственная сцена: Node2D + world.gd (всё остальное строится кодом!)
  scripts/world.gd       мир: парсинг карты, тайлмап, стены, спавн, диалоги, ввод, квест-логика
  scripts/player.gd      персонаж: движение, спрайт-фреймы из листа, атака (Area2D на 2 кадра)
  scripts/npc.gd         NPC-зоны диалога (Area2D, hint "E")
  scripts/interactable.gd трава/сундук
  scripts/slime.gd       враг: блуждание -> преследование, knockback, смерть
  scripts/hud.gd         CanvasLayer: сердца, XP, задания, диалоги, тосты (всё в коде)
  scripts/game_state.gd  Autoload GameState: статы, квесты, save/load (JSON в user://)
  data/map_village.json  карта (генерится, не редактировать руками)
  data/dialogues.json    ВЕСЬ текст игры — правьте свободно
  assets/*.png           генерированные ассеты
tools/
  gen_assets.js          генератор пиксель-арта (чистый Node, PNG-энкодер внутри)
  gen_map.js             генератор карты -> data/map_village.json
  dl.js                  HTTPS-загрузчик через Node (см. «Особенности среды»)
  godot/                 портативный Godot 4.7.2
```

## Пайплайн пересборки контента

1. Правка `tools/gen_assets.js` или `tools/gen_map.js`
2. `node tools/gen_assets.js` и/или `node tools/gen_map.js`
3. `node tools/dl.js` — не нужен; при новых png — re-import: exe + `--headless --path pixel-rpg --import`
4. Дымовой тест: exe + `--headless --path pixel-rpg --quit-after 240` (ловить `SCRIPT ERROR`)
5. Запуск игры.

Ключ: **сцены не содержат данных** — почти всё создаётся кодом в `_ready()`, поэтому
правки карт/ассетов не требуют трогать .tscn, а ручная работа в редакторе почти не нужна.

## Квесты и состояние (GameState, autoload)

- `elder_quest`: 0->1 (диалог) -> 2 (3 травы >= herbs, +25 XP, full heal)
- `slime_quest`: 0->1 (диалог) -> 2 (slime_kills>=3, damage=max(2), +30 XP)
- `has_sword` (сундук в лесу): damage=max(2). Уровни: xp_next 20*2^n, +2 max_hp, full heal.
- Сейв: JSON в `user://save_morkheim.json`; позиция игрока — часть сейва.
- Смерть: hp==0 -> диалог death -> респавн на spawn, full heal.

## Решения (почему так)

- **Godot 4** выбран против Defold/Phaser: визуальный редактор + переносимость; для VK экспорт в Web.
- **gl_compatibility** — требование веба/слабых GPU (VK-аудитория на телефонах).
- 640x360 viewport + window override 1280x720 + canvas_items stretch + nearest = пиксель-перфект.
- Коллизии карты — один StaticBody2D с прямоугольником на тайл (проще TileSet physics).
- Диалоги/квесты — код в world.gd talk() + тексты в JSON (данные отдельно от логики).

## Особенности среды (важно для новых сессий!)

- **Сеть из песочницы**: Invoke-WebRequest и curl (schannel) БЛОКИРУЮТСЯ. качать только через
  `node tools/dl.js <url> <dest>` (TLS Node работает). Скачанный Godot: sha256
  `731980f9...a1e953`, 86 013 866 байт.
- **Запись вне workspace запрещена**: Godot шлёт ошибки про AppData — это шум, НЕ лечится,
  кроме как `APPDATA=$PWD/tools/appdata` (в start-game.bat и моих запусках).
- В pwsh под песочницей `Expand-Archive` ругается Write-Progress — файлы при этом распаковываются.
- read_image недоступен (модель без vision) — проверять headless-логами.

## Дорожная карта (дальше)

1. Фидбек по геймплею (скорость, баланс, тексты) — правки итерациями.
2. Контент: расширить лес/подземелье, музыка+звуки (генерация chiptune в gen_assets), больше квестов.
3. **WebGL-экспорт**: скачать экспорт-шаблоны `Godot_v4.7.2-stable_export_templates.tpz` (~1.2 ГБ,
   через node dl.js), распаковать в `%user%/export_templates/4.7.2.stable/` (у нас = tools/appdata),
   создать export_presets.cfg (Web, threads OFF для VK!) и `--export-release "Web" build/index.html`.
4. **VK Bridge** в index.html: подключить CDN VK Bridge, вызывать `bridge.send("VKWebAppInit", {})`
   в первые 30 секунд; затем покупки/реклама по докам dev.vk.com/ru/games.
5. Хостинг статики VK (CDN) или свой HTTPS-сервер; серверная часть не нужна (одиночная игра).

## Изменения

- 2026-11-09: создан вертикальный срез (день 1). Godot 4.7.2, все ассеты сгенерированы,
  дымовые тесты чистые, два живых запуска по желанию пользователя.
