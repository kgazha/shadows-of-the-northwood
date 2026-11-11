# ART_STYLE — единый стиль «Теней Северного Леса» (SHADOWS OF THE NORTHWOOD)

Канон пользователя. Все изображения игры (монстры, окружение, герой, предметы,
скиллы, UI) генерируются моделью **qwen-image-2.1** через LiteLLM-прокси.
Никакого пиксельного рисования, никаких сторонних картинок, никакой квантизации.

## Модель и вызов
- Прокси: `http://10.14.1.103:4000` → `POST /v1/images/generations`
- Модель: `qwen-image-2.1`, `size` по умолчанию `1024x1024`, ответ `data[0].b64_json` (PNG RGBA)
- ⚠️ Параметр `response_format` не передавать — бэкенд отвечает 400
- Ключ: автоматически из `~/.dsh/.credentials.yaml` (`sk-...`), в логах/коммитах не светить
- Готовый инструмент: `tools\imggen.py` (заглушка-перехват `scratch_cm\imggen.py`
  совместима со старыми джобами). Пример:
  `C:\Python314\python.exe tools\imggen.py --anchor icon --object "a red-capped bolete mushroom" --out art_gen\items\mushroom_v1.png`

## STYLES_ANCHOR — дословная преамбула ЛЮБОГО промпта
```
Dark northern fantasy painterly game art, oil painting style with visible thick
brushstrokes, muted desaturated palette of moss green, slate blue, ash grey with
warm amber accents, soft cold diffuse light, high detail illustration, clean
silhouette, no text, no watermark, no pixel art, no jpeg artifacts
```
Формула промпта: `<ANCHOR>. <объект>. <суффикс типа>` (в imggen.py это `--anchor <пресет> --object "…"`).

## Суффиксы по типу актива (зашиты в tools/imggen.py как пресеты --anchor)
| пресет | для | суффикс |
|---|---|---|
| `hero`   | главный герой | full body character sprite, side view, standing pose, isolated on a plain pure white background, no drop shadow, no ground contact shadow |
| `sprite` | монстры, NPC, предметы | isolated single object centered on a plain pure white background, no drop shadow, no ground contact shadow, full body visible |
| `tile`   | тайлы/текстуры мира | seamless tileable texture, flat top-down view, even lighting, no shadows, no objects |
| `icon`   | иконки скиллов/предметов | single game icon, centered, slight bas-relief, dark aged wood and bronze frame, readable at small size, isolated on a plain pure white background |
| `ui`     | рамки, панели, декор | ornate dark wooden frame decoration with carved wolf and rune motifs, aged bronze fittings, parchment surface, isolated on a plain pure white background |

## Обработка после генерации (неизменяемый канон пользователя)
1. Вырезание фона (белый/маджента) → честный alpha (soft-маска, без багровых ореолов).
2. Кроп по bounding box → LANCZOS до целевого размера.
3. PNG **полной глубины цвета**: никаких палитр/posterize/8-бит/MedianFilter.
4. Тайлы мира в игре рендерятся с `TEXTURE_FILTER_LINEAR` (наследуется от контейнеров
   зон Village/Cave/Ashen) — пиксельность убивается сглаживанием, не понижением качества.
   HUD, шрифты, рамки остаются резкими.
5. Швы тайлов: wrap-around фикс (offset 50% + градиентный кросс-бленд), метрика
   seam ≤ 2×inner.

## Хранилище и ревью
- Все генерации — в `art_gen\<hero|npc|monsters|environment|items|skills|ui>\`
  (регламент: `art_gen\README.md`), именование `<что>_v<N>.png`, ≥2 варианта на объект,
  рядом `.meta.txt`, в папке актуальные `contact_sheet.png` + `MD5SUMS.txt`.
- Отвергнутое пользователем → `art_gen\_otbrakovka\` (не показывать повторно).
- В `pixel-rpg/` утверждённое попадает только через задачу с гейтами батареи и вердикт пользователя.
