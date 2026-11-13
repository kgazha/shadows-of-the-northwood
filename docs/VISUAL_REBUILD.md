# VISUAL_REBUILD — аудит визуала перед пересборкой (t50, 13.11.2026)

Документ — результат **read-only** аудита (код не менялся) для исполнения нового
закона пользователя (13.11):

1. **ВСЕ qwen-image-изображения убираются из игры** (включая иконки
   предметов/талантов, фон талантов и фичевые портреты).
2. **Масштаб мира — назад «до Крупного мира»**: герой ~16 px, зум камеры 1,
   в кадре ~40×22 клетки (вьюпорт 640×360, TILE=16 ⇒ 40×22.5 при zoom 1 — сходится).
3. **Новый стиль** — единый hand-made пиксель (как герои/мобы t17/t27),
   рисование кодом; листы на верстку — до интеграции.

База аудита: HEAD `51a986f`. Генератор: `tools/imggen.py` (LiteLLM
`qwen-image-2.1`, якорь стиля ART_STYLE.md). Исходники-оригиналы 1024 живут
СНАРУЖИ репозитория (`art_gen/` в корне рабочей копии: hero/, monsters/,
npc/, items/, skills/, ui/, environment/, _otbrakovka/) — в игру интегрированы
только кропы из `pixel-rpg/assets/`.

---

## 1. ПОЛНЫЙ инвентарь qwen-ассетов (УБРАТЬ / ЗАМЕНИТЬ)

**52 файла** (40 в `assets/art/`, 7 в `assets/portraits/`, 2 в `assets/ui/`,
3 атласа иконок) + 2 смешанных атласа (клетки). «Монтаж» — скрипт : функция :
строка(и).
«Если удалить» — поведение игры без ассета. Все точки монтажа имеют fail-safe
`ResourceLoader.exists()` (проверено построчно); ни одно удаление не крашит игру.

### 1.1. Пропы мира `pixel-rpg/assets/art/` (31 файл, все — УБРАТЬ)

| ассет (px) | монтаж | рисует | если удалить |
|---|---|---|---|
| `tree_grove_0..5.png` (155×96…83×96) | `world.gd` : константа `GROVE_ART`:35, `_grove_load_art`:423, `_grove_init`:434, `_build_grove_canopy`:468 | кроны рощ над кластерами «t» (слой GroveCanopy, дим-контракт кроны t33) | fail-safe `_grove_init`:438 push_warning — рощи остаются **тайловыми** (atlas «t»/«T») |
| `village_cottage.png` (96×77), `village_well_1/2.png` (35×29), `village_signpost.png` (48×48), `village_campfire.png` (32×32) | `world.gd` : `VILLAGE_ART_*`:45–51, `_village_art`:572, `_add_prop`:580 (k-масштаб избы), `_build_village_props`:603; дим t41 `_ys_update`:1655+ | изба/колодцы/указатель/костёр деревни (слой VillageProps, дим `YS_PROP_DIM_AT`) | fail-safe: кластеры остаются тайловой отрисовкой (CHAR_TO_TILE бит-в-бит) |
| `env4_altar.png` (502×861), `env4_portal.png` (754×843) | `world.gd` : `ENV4_ART`:62, `ENV4_CANON_H`:76 (51/70), `_env4_tex`:699, `_env4_place`:709 (scale=canon/tex_h, MIPMAPS, регистрация в `_ys_props_dim` t48), `_build_env4_props`:754 | алтари пещеры, выходной портал Пепелища | fail-safe `_env4_tex`:701 null → якорь остаётся тайловым |
| `env4_chest.png` (35×19), `env4_stones.png` (64×32), `env4_boulder.png` (32×26) | те же `ENV4_ART`/`ENV4_PROP_CANON_H`:87 (камни 24/валун 21) | сундуки (все три зоны), кластеры камней, одиночные валуны | fail-safe тот же — тайлы «s»/«r» |
| `ground_moss_1/2.png` (26×26/24×24), `ground_needles_1.png` (28×28), `ground_leaves_1.png` (24×24), `ground_clearing_1.png` (26×26), `ground_grass_1.png` (22×22) | `world.gd` : `GROUND_ART`:104, `_build_ground_paint`:863, `_gp_bake`:957, `_gp_bake_sprite`:1064 (слой z=-5, 274 патча по FNV-хэшу) | «живая земля» деревни/леса | fail-safe (коммент :103 + код bake): нет ассетов → прежний рендер; стенд qa_lp T6 прямо пинит fail-safe |
| `path_worn/needles/pebbles_1.png` (30×30) | `world.gd` : `PATH_ART`:112, `_build_ground_paint`:863 | прочерченные тропы «d» с пером 3–4 px | тот же fail-safe |
| `ground_cave_1..3.png` (26/24/28), `ground_ashen_1..3.png` | `world.gd` : `CAVE_FLOOR_ART`:125, `ASHEN_FLOOR_ART`:130, `_build_zone_floor_paint`:1081 | «живые полы» пещеры/Пепелища (z=-5) | fail-safe: слой не создаётся (qa_lp T6 fail-safe-пин :588–592) |

### 1.2. Актёры `pixel-rpg/assets/art/` (9 файлов, все — УБРАТЬ; листы-t17)

| ассет (px) | монтаж | рисует | если удалить |
|---|---|---|---|
| `hero_idle.png` (513×1460), `hero_walk.png` (762×1374), `hero_attack.png` (904×1283) | `player.gd` : `GEN_HERO_*`:33–35, `GEN_CANON_H`:36 (32 px), `GEN_FOOT_LINE`:37, `_build_gen_frames`:123–143 (вызов из `apply_class`:110), scale=32/tex_h :136, MIPMAPS :140 | герой (единый для всех классов!) | fail-safe :124 return false → класс-листы `class_warrior/archer/mage.png` → `player.png` :116 |
| `mob_slime.png` (566×528) | `slime.gd` : :57–68 (s=22/h, MIPMAPS) | слизень | fail-safe :69 → `slime.png` (код-лист, 2 кадра) |
| `mob_archer.png` (438×979) | `mob_archer.gd` : :67–103 (s=24/h) | лучник | fail-safe → `mobs_archer.png` → ColorRect-заглушка :104 |
| `mob_swarmling.png` (698×356) | `mob_swarmling.gd` : :79–121 (18 px канон t22) | мглокрыс | fail-safe → `mobs_swarmling.png` |
| `mob_rotspawn.png` (686×872), `mob_grom.png` (812×773) | `brute.gd` : `GEN_ROTSPAWN/GEN_GROM`:49–50, `GEN_CANON`{1:29,2:35,3:42}:51, `GEN_FOOT_OLD`:52, setup :172–185, `gen_canon_h`:397 (босс 52) | отпрыски Грома (ярусы) и Гром | fail-safe :186 → `brute.png` (32px-кадры) → ColorRect :204 |
| `mob_witch.png` (497×974) | `mob_boss2.gd` : `gen_tex_path`:86, `gen_canon_h`:89 (51 px), `gen_foot_old`:92 (13.91375) | Ведьма Пепелища | fail-safe → ветка `brute.png` в `brute.setup` (scale 51/32 :79) |

Тенеплёт (`mob_wraith`) в ген-ассет НЕ интегрирован (решение пользователя) —
`art/mob_wraith*` в игре отсутствует.

### 1.3. UI и портреты (9 файлов)

| ассет | монтаж | рисует | если удалить | пометка |
|---|---|---|---|---|
| `portraits/elder/farmer/hermit/hero/merchant/smith/witch.png` (7×112×112) | `hud.gd` : `NPC_PORTRAITS`:28–35, `_npc_portrait`:599–610, монтаж в диалоге :520–526 (`PORTRAIT_SLOT`=48 :37) | фичевые портреты NPC в диалоге | fail-safe :607–609 null → легаси-атлас `portraits.png`/`portraits2.png` (40 px) → без портрета | **УБРАТЬ** |
| `ui/decor_paper_edge.png` (999×999, 1.46 MB — тот самый «фон талантов 1024») | `journal.gd`:131–134, `meta_board.gd`:147–149, `run_summary.gd`:116–118 (все с exists-guard) | бумажная кромка: журнал (вкл. вкладки талантов), «Доска пепла», экран итогов | fail-safe: декор не создаётся, панели целы | **УБРАТЬ** |
| `ui/decor_minimap_bronze.png` (128×128) | `minimap.gd` : `BRONZE_PATH`:42, :408–418 | бронзовое кольцо миникарты | fail-safe push_warning «миникарта без кольца» | **УБРАТЬ** |

### 1.4. Атласы иконок (3 файла — УБРАТЬ, в t53 рисовать заново кодом)

| ассет | монтаж | рисует | если удалить |
|---|---|---|---|
| `item_icons.png` (96×16, 6 слотов 16 px) | `ash_icon.gd` : `ATLAS`:11, guard :17; `hud.gd`:730–732 (хотбар) | иконки предметов/пепла | fail-safe: push_warning, иконка пропущена / хотбар без иконок |
| `skill_icons.png` (192×16, 12 слотов; ген с a5600ae/35c99df) | `hud.gd`:652–655 | иконки скиллов панели | fail-safe: «панель скиллов без иконок» |
| `talent_icons.png` (192×16; t23) | `talents.gd` : `ATLAS_PATH`:233, `_atlas`:239–253, `icon_texture`:275–291 | иконки древа талантов | fail-safe: `_atlas_failed` → процедурная код-иконка :291 |

### 1.5. Смешанные базовые атласы (ЗАМЕНИТЬ КЛЕТКИ, файлы остаются)

| атлас | ген-клетки (коммит 8fb87cb) | монтаж | комментарий |
|---|---|---|---|
| `assets/tiles.png` (256×16) | «живой тайл подстилки леса» — индекс 15 («T») под рощами; остальные клетки — процедурный код-арт (gen_assets*.js, pass v3 7af54a5) | `world.gd` : `CHAR_TO_TILE`:10–11, `_build_tiles`:366 | файл УДАЛЯТЬ НЕЛЬЗЯ (геометрия, коллайдеры, миникарта читают атлас бит-в-бит) → в t53 перерисовать ген-клетки в hand-made стиль, индексы не трогать |
| `assets/dungeon_tiles.png` (256×16) | «пещерные колонна и обломки из генерации» — `dungeon_zone.CHAR_TO_TILE` «P»=6 (колонна), «R»=7 (обломки); CAVE_BLOCK_SHAPES `world.gd`:25–27 | `dungeon_zone.gd`:12–13, `world._build_cave`:1457, `_apply_cave_shapes`:1531 | то же: перерисовать клетки 6/7 (+проверить смежные клетки пола при вскрытии), индексы и коллайдеры ([10,16],[12,10]) — бит-в-бит (пины qa_dn/qa_c2-сканов) |

---

## 2. НЕ-ГЕН ассеты и код-арт — НЕПРИКОСНОВЕННЫ (ОСТАВИТЬ)

Происхождение подтверждено git (коммиты добавления — до ген-волн и/или
процедурные генераторы `tools/gen_assets*.js`, `gen_fx_assets.js`,
`gen_ashen_assets.js`, `gen_music.js`, `gen_ui_sfx.js`):

- **Базовые атласы (кроме клеток из 1.5):** `tiles.png` (кроме ген-клетки — см. 1.5), `ashen_tiles.png`
  (64fd1ca — ген-волн не касался), `anim_tiles.png`, `decor.png`, `shadow.png`,
  `projectiles.png`.
- **Hand-made листы актёров — СТИЛЕВОЙ КАНОН новой волны:** `player.png` (48×64),
  `class_warrior/archer/mage.png` (48×64), `npc_elder/farmer/hermit/merchant/smith.png`
  (16×16), `slime.png` (32×16), `brute.png` (64×32), `mobs_archer/swarmling/wraith.png`
  (48×64) — это и есть «как герои/мобы t17/t27», на который ссылается закон.
- **Легаси-портреты:** `portraits.png`, `portraits2.png` (120×40, слоты 40 px) —
  фолбэк диалогов (см. 1.3), остаются.
- **Пиксель-мелочь:** `heart.png`, `key.png`, `campfire.png` (80×16),
  `alch_icons.png` (48×16), `cursor_move.png`, `cursor_enemy.png`.
- **FX:** `fx/fx_dot|dot_soft|flame|shard|smoke|spark|star.png` (4–8 px,
  gen_fx_assets.js).
- **UI CC0:** `ui/cursor_arrow.png`, `ui/cursor_crosshair.png`,
  `ui/panel_frame.png` (Kenney, LICENSE_KENNEY.txt).
- **Шрифт:** `fonts/handjet.ttf` + LICENSE.txt (OFL, кириллица 76/76, t27).
- **Звук:** `music/*.{ogg,wav}` (процедурный синтез gen_music.js),
  `sfx/*.ogg` (Kenney CC0 + gen_ui_sfx.js). К визуалу не относятся.

---

## 3. МАСШТАБ: таблица «сейчас → было»

«Было» = базис ДО `c5769c3` («Крупный мир ч.1», 12.11, зум 2 + актёры ×1.5);
промежуточное: `648bf7b` зум 1.5, `5ae6a07`/`fc1b1a3` SCALE_CANON H=32,
`7e3c7b3` t22-вердикты. Все константы — visual-only: коллайдеры/скорости/
дистанции боя во всех волнах НЕ менялись (и в обратную сторону — тоже).

| параметр | сейчас (HEAD 51a986f) | было (до c5769c3) | где живёт |
|---|---|---|---|
| зум камеры (все зоны) | **1.5** | **1.0** (строки `cam.zoom` не было вовсе — Godot default) | `world.gd` `_spawn_player` :1155; лимиты `_set_cam_limits` :2032 |
| кадр | 640×360 / 1.5 ⇒ ~26.7×15 клеток | 640×360 ⇒ **40×22.5 клетки** (закон: ~40×22 ✓) | `project.godot` viewport 640×360, stretch canvas_items/expand; `world.gd` `TILE=16` :7 |
| герой | ген-арт s=32/tex_h (канон H=32, стопы +5); фолбэк-листы `VISUAL_SCALE=2.0`, `ANIM_HOME=(0,−5)` | спрайт 16 px, scale 1.0, `anim.position = ZERO` (и в lunging) | `player.gd` :25–26, :33–37, :88–89, :123–143 |
| NPC | `VISUAL_SCALE=1.8125` (29 px), `SPR_HOME_Y=−4.0625`, `MARKER_BASE_Y=−30` | 1.0 / 0 / **−25** | `npc.gd` :9, :14–15, :30–31 |
| слизень | ген s=22/h (pos −3.9375); листы `VISUAL_SCALE=1.375` (pos −1.875) | 1.0 / 0; цифры урона −12 | `slime.gd` :19, :57–78 |
| лучник | ген s=24/h (pos −3.5); листы `VISUAL_SCALE=1.5` (pos −3.5) | 1.0 / 0 | `mob_archer.gd` :25, :92–102 |
| мглокрыс | `VISUAL_SCALE=1.125` (18 px, t22), pos −3.0 | 1.0 / 0 | `mob_swarmling.gd` :27, :109–114 |
| тенеплёт | `VISUAL_SCALE=1.8125` (29 px), pos −2.5 | 1.0 / 0 | `mob_wraith.gd` :31, :88 |
| Гром/отпрыски | ген `GEN_CANON`{29,35,42}, босс 52; листы `VISUAL_SCALE=1.3125`×`TIERS`{0.72,0.85,1.0}, босс (52/42)-база | `TIERS.scale`{0.72,0.85,1.0} на 32px-листе (≤32 px), босс scale 1.0 | `brute.gd` :43, :51–52, :181–203 |
| Ведьма | 51/32=1.59375 (или ген s=51/h) | **1.12** | `mob_boss2.gd` :73–90 |
| цифры урона герой | −18 (игрок/зелье), brute `_head_spawn_y`, слизень −14 | **−12** (все) | `dmg_numbers.gd` :~130, `brute.gd` :386–391, `slime.gd` hurt, `world.gd` `drink_potion` |
| Fx героя (heal/spark/levelup) | −18/−16/−14 | −12/−10/−8 | `player.gd` (regen-тики, cast_skill, `_no_target_reject`) |
| hint-подсказка | `position=(−45,−28)` | **(−45,−26)** | `world.gd` `_spawn_player` |
| пропы ENV4 | screen-canon: алтарь 51 / портал 70 / камни 24 / валун 21, scale=canon/tex_h (ENV4-компенсация), MIPMAPS у алтаря/портала | пропов-спрайтов не было вовсе (8fb87cb ещё не было) — тайлы 16 px | `world.gd` :76–79, :87–90, `_env4_place` :709–729 |
| изба | k=clamp(bbox·1.12/texture, 0.5, 1.45) | (не было) | `world.gd` `_build_village_props` :603 |
| кроны | 96 px (fit-оверхед 12%) | (не было) | `world.gd` `_build_grove_canopy` :468 |
| шкала глубины | `YS_CYCLE=4800`, `YS_ACTOR_BIAS=10`, foot-z | динамический z от Y/8 (старая шкала «глубины») | `world.gd` :147–151, `_ys_prop`:452 |
| канон пропорций | SCALE_CANON.md **H=32** | «герой = клетка 16 px» (де-факто) | `SCALE_CANON.md` (перепишут t51/t53) |

Замечание: `SCALE_BASE/SCALE_STEP` в `mob_boss2.gd`:25–26 — скейл hp/dmg по
глубине (t39), к визуалу отношения не имеет — не трогать.

---

## 4. QA-пины, завязанные на размер/зум/арт (потребуют ребейзлины)

| стенд | секция/строки | пин | судьба |
|---|---|---|---|
| `qa_lp.gd` | **T6** (:560–600) | alpha патчей пола ∈[0.30,0.42] (meta gp_amax), LINEAR, детерминизм двух миров (вкл. floor paint), fail-safe слоя | после t52 пол-патчей нет → секция удаляется/переписывается под новый слой |
| `qa_lp.gd` | **T7** (:604–712) | экранные altar 51.0±0.05 / portal 70.0±0.05 / boulder 21 / stones 24; tex_h (boulder 26, stones 32, altar/portal ≥3×); фильтры MIPMAPS/LINEAR; полная мип-цепочка .ctex; .import mipmaps/generate=true | удаляется с env4-артом |
| `qa_lp.gd` | **T9/T10** (~:275–290 BAKE/MD5) | MD5/габариты бейка ground-paint | удаляется |
| `qa_lp.gd` | **T11** (:856–1055) | `T11_ART` MD5 девяти art-кропов (+1024-источников art_gen/), w/h, hero drawn=32/стопы 5.0, mob-каноны 24/8.5, 22, 51/13.91375, фильтры | удаляется с актёрским артом |
| `qa_lp.gd` | **T12** (:1142–1283) | тени: масштаб героя (32 px) vs слайма (22), DmgNumbers `POP_FROM`, тинты | ребейзлить под 16 px-силуэты (тени-отношения сохраняются) |
| `qa_lp.gd` | **T13** (y-sort) | общие стопы актёров/пропов | пин по z-шкале (geometry) — пережить перерезку канонов |
| `qa_lp.gd` | **T14** (:401–520) | залы 5×5 под алтарём/порталом по экранным ширинам `_eff_w` (51/70), живой пол (детерминизм/MD5), гейт сундука | ребейзлить габариты зал под новые пропы |
| `qa_lp.gd` | **T15** (t48, :1394+) | env4 структурный 13/13 в `_ys_props_dim`, dim alpha 0.5, METRIC строки | удалится вместе с env4-спрайтами (или переедет на новые пропы) |
| `qa_vlg.gd` | **inv8** (:434–490) | слои VillageProps/GroveCanopy, 32 спрайта, z==стопа, крона 0.5/1.0 | пины по слоям — переписать под новые проп-слои/их отсутствие |
| `qa_vlg.gd` | **inv9** (:533–560) | дим-контракт «знак/костёр/колодец» (покрытие %, alpha) | удалится/переедет с village-артом |
| `qa_gb.gd` | **G1** (:88–90) | радиус Грома ≤1.2×**рисованого** силуэта (`tex.width × anim.scale` mob_grom.png) | ребейзлить на новый лист Грома |
| `qa_mb.gd` | **R7** (:389) | `ResourceLoader.exists(".../decor_paper_edge.png")` | инвертировать/удалить после сноса |
| `qa_dn`, qa_c2-скан | пещерные атлас-индексы/проходимость | клетки колонны/обломков | **не ломаются при перерисовке клеток** (индексы/коллайдеры бит-в-бит) — не трогать |
| `qa_mm` | цвета миникарты из атласов | перерисовка клеток tiles/dungeon меняет пиксели | проверить при t53 (цвета патчей миникарты пинуются) |
| `mb_1..6` | поведение мобов | коллайдеры/скорости от визуала не зависят | ребейзлина НЕ нужна |

---

## 5. План сноса по слоям и порядок слияний t51→t52→t53

Принцип: **сначала масштаб (тонкий диф констант), потом снос (толстый диф
удалений), потом новый стиль (новый диф-добавка)** — тогда в `world.gd`
изменения идут непересекающимися блоками и rebase не нужен.

**t51 — масштаб «до Крупного мира»** (не трогает ген-арт):
1. `world.gd`:1155 `cam.zoom = Vector2.ONE` (одна строка).
2. Откат visual-констант актёров к до-базису: `player.gd` VISUAL_SCALE→1.0/
   ANIM_HOME→0 (+ GEN_CANON_H→16, GEN_FOOT_LINE→+5 на ген-арте, пока он жив),
   `npc.gd` 1.0/0/−25, `slime.gd` 1.0, `mob_archer/swarmling/wraith.gd` 1.0,
   `brute.gd` VISUAL_SCALE→1.0, босс-база 1.0, `mob_boss2` 1.12;
   env4-каноны пополам (51/70/24/21 → ~26/35/12/11) либо временный scale·0.5.
3. Метки/Fx: MARKER_BASE_Y −25, hint −26, dmg −12, Fx −12/−10/−8,
   `YS_ACTOR_BIAS` пересчитать под 16 px (стопа ≈+8, узел центра 16px-кадра).
4. Ребейзлин пинов: qa_lp T11/T12 drawn-высоты и тени, qa_lp T14 ширины зал,
   qa_gb G1 силуэт, SCALE_CANON.md H=16.
   Зоны риска: t41/t48 дим-пины (площади накрытия меняются с масштабом —
   пересылать пороги, YS_PROP_DIM_AT не трогать без вердикта).

**t52 — снос qwen-арта** (зависит от t51 — иначе останутся полуконстанты):
1. Удалить 52 файла (§1.1–1.4) + .import; в t53-листе — перерисовка клеток
   `tiles.png`(15)/`dungeon_tiles.png`(6,7) помечена ЗАМЕНИТЬ, файлы остаются.
2. `world.gd`: вынести блоки констант :31–134 (GROVE/VILLAGE/ENV4/GROUND/FLOOR),
   функции `_grove_*`/`_build_grove_canopy`, `_village_art`/`_add_prop`/
   `_build_village_props`, `_env4_*`/`_build_env4_props`, `_build_ground_paint`/
   `_gp_*`/`_build_zone_floor_paint` — всё, что монтирует снесённое; `_ys_*`
   инфраструктуру и `_ys_props_dim` ОСТАВИТЬ (геометрия глубины нужна новой волне).
3. Актёрские скрипты: удалить GEN-ветки (player `_build_gen_frames`, slime
   :57–68, archer/swarmling gen-флаги, brute GEN_*, boss2 gen-виртуалы) —
   фолбэк-ветки становятся единственными.
4. UI: `hud.gd` NPC_PORTRAITS/_npc_portrait (легаси-атлас остаётся!),
   skill/item-icon ветки; `journal/meta_board/run_summary` paper-блоки;
   `minimap.gd` BRONZE; `talents.gd` _atlas (код-иконка :291 становится
   единственной); `ash_icon.gd`.
5. QA: удалить T6/T7/T9/T10/T11/T15, секции inv8/inv9 qa_vlg, qa_mb R7;
   почистить METRIC. Батарея 38/38 на остаточном (пин-счёт меняется —
   манифест 38 стендов НЕ трогать, только содержимое).

**t53 — новый hand-made стиль** (после t52 — монтирует в чистые места):
1. Листы/процедурная рисовка кодом в 16 px-каноне (герой ~16 px, зум 1);
   проп-слои монтируются заново (можно переиспользовать каркасы слоёв и
   y-sort/z-шкалу).
2. Перерисовка ген-клеток атласов (tiles «T», dungeon «P»/«R») без смены
   индексов/коллайдеров.
3. Иконки предметов/скиллов/талантов, портреты, декор — код-арт; пины
   новой волны (drawn-h по 16 px-канону) пишутся заново.

**Итого:** t51 — константный диф (actor-скрипты + 1 строка world.gd + offsets),
t52 — большие удаления (world.gd :31–134 + build-функции + актёрские GEN-ветки),
t53 — новые файлы/блоки. Ни одна пара не правит один и тот же блок:
конфликтов в world.gd нет при порядке слияния t51→t52→t53.
