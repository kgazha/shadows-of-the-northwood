"""t33: самопроверка моих артефактов — CJK/латиница внутри русских слов/мусорные маркеры.

Не трогает дерево игры: корень — diag-t33, расширения .gd/.tscn/.py/.md.
"""
import glob
import io
import os
import re
import sys

D = os.path.dirname(os.path.abspath(__file__))
EXT = (".gd", ".tscn", ".py", ".md")
CJK = re.compile(r"[\u3000-\u30ff\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff\uff00-\uffef]")
# латинская буква, зажатая кириллицей с обеих сторон (не в латинском слове)
MIX = re.compile(r"[а-яёА-ЯЁ][^\sа-яёА-ЯЁ]{0,3}[a-zA-Z][^\sа-яёА-ЯЁ]{0,3}[а-яёА-ЯЁ]")
TODO = re.compile(r"(TODO|FIXME|XXX|Lorem ipsum)")

bad = 0
files = []
for root, dirs, names in os.walk(D):
    dirs[:] = [d for d in dirs if d not in ("stage", "out", "_hx") and not d.startswith("appdata")]
    for n in names:
        if n.endswith(EXT):
            files.append(os.path.join(root, n))
for f in sorted(files):
    try:
        with io.open(f, encoding="utf-8") as fh:
            lines = list(enumerate(fh, 1))
    except UnicodeDecodeError:
        bad += 1
        print("кодировка %s: файл не UTF-8 (per-разбор логов PowerShell даёт UTF-16) — "
              "пересоздать редиректом внутри python" % os.path.relpath(f, D))
        continue
    for i, line in lines:
            for m in CJK.finditer(line):
                bad += 1
                print("CJK   %s:%d: %s" % (os.path.relpath(f, D), i, line.strip()[:120]))
            for m in MIX.finditer(line):
                # «ПКМ-приказ», «E-кнопка» — легальная латиница между кириллицей
                seg = m.group(0)
                if re.search(r"[а-яё][а-zA-Z\s\-_/().]{1,12}[а-яё]", seg):
                    print("смесь %s:%d: %s" % (os.path.relpath(f, D), i, seg))
            if TODO.search(line):
                print("маркер %s:%d: %s" % (os.path.relpath(f, D), i, line.strip()[:100]))
print("проверено файлов: %d, подозрений CJK: %d" % (len(files), bad))
sys.exit(1 if bad else 0)
