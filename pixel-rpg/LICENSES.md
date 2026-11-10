# Лицензии ассетов — «Тени Северного Леса»

Все сторонние ассеты — **CC0 1.0 Public Domain Dedication**
(https://creativecommons.org/publicdomain/zero/1.0/): бесплатны для
коммерческого использования без обязательной атрибуции. Собственные работы
команды публикуются тем же проектом под CC0 1.0. Нет ни одного файла под
лицензией с ограничениями NC/ND и ни одного «серого» семпла.

## 1. Kenney RPG Audio — 10 сэмплов эффектов (OGG), CC0 1.0

- Набор «RPG Audio», Kenney (https://kenney.nl/assets/rpg-audio).
- Скачано с Godot-зеркала https://github.com/Boyquotes/kenney-rpg-audio-for-godot
  (полный текст лицензии CC0: `tools/assets_in/sfx/rpg_LICENSE.txt`).
- Файлы в `assets/sfx/`: knife_slice, draw_knife_1, footstep_0, footstep_2,
  cloth_1, drop_leather, handle_coins_2, belt_handle_1, book_open, metal_pot_2.

## 2. Kenney UI — пиксельные рамки и курсоры (PNG), CC0 1.0

- Пакеты: «UI Pack - Pixel Adventure» и «Cursor Pixel Pack»,
  Kenney (https://kenney.nl/assets/ui-pack-pixel-adventure,
  https://kenney.nl/assets/cursor-pixel-pack).
- Скачано с зеркала https://github.com/shorepine/kenney
  (текст лицензии CC0: `tools/assets_in/ui/kenney_mirror_LICENSE.txt`,
  копия уведомления — `assets/ui/LICENSE_KENNEY.txt`).
- Производные в `assets/ui/`:
  - `panel_frame.png` — 32×32 nine-slice рамка из `tiles_large_thin/tile_0000.png`
    (точный палитр-своп 4 цветов под тёмную палитру игры, геометрия не изменена);
  - `cursor_crosshair.png` — прицел из `cursors_pixel/tile_0057.png`
    (палитр-своп в палитру существующих курсоров, форма не изменена);
  - `cursor_arrow.png` — точная копия `cursors_pixel/tile_0066.png`.
- Полное зеркало паков (633 PNG, вне дерева игры): `tools/assets_in/ui/`.

## 3. VFX-текстуры — собственная CC0-публикация

- `assets/fx/fx_dot.png`, `fx_dot_soft.png`, `fx_spark.png`, `fx_star.png`,
  `fx_flame.png`, `fx_smoke.png`, `fx_shard.png` — сгенерированы с нуля
  скриптом `tools/gen_fx_assets.js` (чистый Node.js/zlib), CC0 1.0.
- `scripts/fx.gd` — написан для проекта, CC0 1.0.
- Опциональная замена на Kenney «Particle Pack» (CC0,
  https://kenney.nl/assets/particle-pack): положить PNG в `assets/fx/` под теми
  же именами (или поправить `TEX_*` в `fx.gd`); тонирование задаётся кодом
  (`color`/`color_ramp`, PNG белые) — правка эффектов не потребуется.

## 4. UI-звуки — собственный синтез (WAV), CC0 1.0

- `assets/sfx/ui_click.wav`, `ui_confirm.wav`, `ui_deny.wav`, `ui_levelup.wav`
  — синтезированы детерминированным скриптом `tools/gen_ui_sfx.js`
  (PRNG mulberry32, фиксированное зерно, воспроизводимость байт-в-байт).

## 5. Музыка — 3 темы (WAV), собственная CC0-публикация

- `assets/music/theme_forest.wav`, `theme_cave.wav`, `theme_tension.wav` —
  полностью оригинальные процедурные композиции, синтезированы скриптом
  `tools/gen_music.js` (чистый Node.js, детерминированный PRNG, SHA256-стабильная
  перегенерация; проверка швов/пиков — `tools/verify_wav.js`).
- Никаких заимствований и семплов; бесшовные лупы, пик −3 dBFS.

## 6. Код

- `scripts/game_audio.gd`, `scripts/fx.gd` и все правки геймплейных скриптов —
  написаны командой для проекта.

## 7. Прочее

- Тайлы/спрайты мира и персонажей (`assets/*.png`) — сгенерированы
  детерминированными скриптами `tools/gen_assets*.js` командой проекта, CC0 1.0.
- Шрифты: системный растеризатор Godot (без сторонних шрифтовых файлов).
