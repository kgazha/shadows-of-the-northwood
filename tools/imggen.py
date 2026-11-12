# -*- coding: utf-8 -*-
"""Генератор арта «Теней Северного Леса» через LiteLLM (qwen-image-2.1).

Канон единого стиля зашит здесь (источник истины — ART_STYLE.md в корне репо).

Использование (два режима):
  1) С пресетом (рекомендуется — стиль не зависит от аккуратности автора промпта):
     C:\\Python314\\python.exe tools\\imggen.py --anchor icon --object "a red-capped bolete mushroom" --out art_gen\\items\\mushroom_v1.png
     пресеты: hero | sprite | tile | icon | ui
  2) Полным промптом (обратная совместимость; сам вставь STYLES_ANCHOR дословно):
     ... --prompt "<ANCHOR>. <объект>" --out ...

Правила прокси (проверено живьём):
  - response_format НЕ передавать — бэкенд отвечает 400 UnsupportedParamsError;
  - ответ в data[0].b64_json (PNG RGBA) либо data[0].url;
  - ключ автоматически из ~/.dsh/.credentials.yaml (sk-...), в логах не печатается;
  - рядом пишется <out>.meta.txt (полный промпт, revised_prompt, время).
"""
import argparse, base64, json, os, re, sys, time, urllib.request

BASE = "http://10.14.1.103:4000/v1/images/generations"
MODEL = "qwen-image-2.1"

# === ЕДИНЫЙ СТИЛЬ (ART_STYLE.md) ===
STYLES_ANCHOR = (
    "Dark northern fantasy painterly game art, oil painting style with visible thick "
    "brushstrokes, muted desaturated palette of moss green, slate blue, ash grey with "
    "warm amber accents, soft cold diffuse light, high detail illustration, clean "
    "silhouette, no text, no watermark, no pixel art, no jpeg artifacts"
)
SUFFIXES = {
    "hero":   ("full body character sprite, side view, standing pose, isolated on a plain pure "
               "white background, no drop shadow, no ground contact shadow"),
    "sprite": ("isolated single object centered on a plain pure white background, no drop "
               "shadow, no ground contact shadow, full body visible"),
    "tile":   ("seamless tileable texture, flat top-down view, even lighting, no shadows, no objects"),
    "icon":   ("single game icon, centered, slight bas-relief, dark aged wood and bronze frame, "
               "readable at small size, isolated on a plain pure white background"),
    "ui":     ("ornate dark wooden frame decoration with carved wolf and rune motifs, aged bronze "
               "fittings, parchment surface, isolated on a plain pure white background"),
}
# ========================

def get_key():
    # 1) явный env, 2) файл ключа генератора (вне репозитория), 3) credentials харнесса (исторический путь)
    env = os.environ.get("LITELLM_KEY", "").strip()
    if env:
        return env
    kf = os.path.expanduser("~/.dsh/litellm_key.txt")
    if os.path.exists(kf):
        k = open(kf, encoding="utf-8").read().strip()
        if k:
            return k
    p = os.path.expanduser("~/.dsh/.credentials.yaml")
    m = re.search(r"sk-[A-Za-z0-9_\-]+", open(p, encoding="utf-8").read())
    if not m:
        sys.exit("Ключ sk-* не найден: положите токен в ~/.dsh/litellm_key.txt или задайте env LITELLM_KEY")
    return m.group(0)


def build_prompt(a):
    if a.object:
        return "%s. %s. %s" % (STYLES_ANCHOR, a.object.strip().rstrip('.'), SUFFIXES[a.anchor])
    return a.prompt

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--prompt", help="полный промпт вручную (обратная совместимость)")
    ap.add_argument("--object", help="только описание объекта; anchor/суффикс добавятся из канона")
    ap.add_argument("--anchor", default="sprite", choices=sorted(SUFFIXES), help="пресет суффикса для --object")
    ap.add_argument("--out", required=True)
    ap.add_argument("--size", default="1024x1024")
    ap.add_argument("--model", default=MODEL)
    a = ap.parse_args()
    if bool(a.prompt) == bool(a.object):
        sys.exit("Нужно ровно одно из: --object (+--anchor) ИЛИ --prompt")
    prompt = build_prompt(a)

    key = get_key()
    body = json.dumps({"model": a.model, "prompt": prompt, "n": 1, "size": a.size}).encode("utf-8")

    last_err = None
    for attempt in (1, 2, 3):
        try:
            req = urllib.request.Request(BASE, data=body, headers={
                "Authorization": "Bearer " + key,
                "Content-Type": "application/json",
            })
            t0 = time.time()
            with urllib.request.urlopen(req, timeout=300) as r:
                j = json.loads(r.read().decode("utf-8"))
            d = j["data"][0]
            if d.get("b64_json"):
                raw = base64.b64decode(d["b64_json"])
            elif d.get("url"):
                with urllib.request.urlopen(d["url"], timeout=120) as ru:
                    raw = ru.read()
            else:
                sys.exit("В ответе нет ни b64_json, ни url: " + str(list(d.keys())))
            os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
            with open(a.out, "wb") as f:
                f.write(raw)
            with open(a.out + ".meta.txt", "w", encoding="utf-8") as f:
                f.write("model=%s\nsize=%s\ntime_s=%d\nrevised_prompt=%s\nprompt=%s\n"
                        % (a.model, j.get("size", a.size), time.time() - t0,
                           d.get("revised_prompt") or "", prompt))
            print("OK %s (%d КБ, %d с, попытка %d)" % (a.out, len(raw) // 1024, time.time() - t0, attempt))
            return
        except Exception as e:
            last_err = e
            code = getattr(e, "code", None)
            msg = str(e)
            if code == 400 or "400" in msg[:80]:
                try:
                    print("HTTP 400:", e.read().decode("utf-8", "replace")[:400])
                except Exception:
                    pass
                sys.exit("400 — исправить промпт/параметры, не повторять")
            time.sleep(5 * attempt)
    sys.exit("исчерпаны повторы: %r" % (last_err,))

if __name__ == "__main__":
    main()
