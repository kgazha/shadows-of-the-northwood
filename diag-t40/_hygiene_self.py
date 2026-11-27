"""t40: самопроверка — CJK/латиница в кириллице/мусор в моих артефактах и в стенде.

Корень: diag-t40 + изменённый файл стенда (только чтение, ничего не правит).
"""
import io
import os
import re
import sys

D = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(D)
FILES = [os.path.join(ROOT, "tools", "qa", "stand", "qa_wreg.gd")]
for name in sorted(os.listdir(D)):
    if name.endswith((".py", ".md", ".gd")):
        FILES.append(os.path.join(D, name))
CJK = re.compile(r"[\u3000-\u30ff\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff\uff00-\uffef]")
MIX = re.compile(r"[а-яёА-ЯЁ]\s?[a-zA-Z]{1,3}\s?[а-яёА-ЯЁ]")
bad = 0
for f in FILES:
    try:
        with io.open(f, encoding="utf-8") as fh:
            lines = list(enumerate(fh, 1))
    except UnicodeDecodeError:
        bad += 1
        print("кодировка %s: не UTF-8" % f)
        continue
    for i, line in lines:
        for m in CJK.finditer(line):
            bad += 1
            print("CJK %s:%d: %s" % (os.path.relpath(f, ROOT), i, line.strip()[:120]))
        for m in MIX.finditer(line):
            print("смесь %s:%d: %s" % (os.path.relpath(f, ROOT), i, m.group(0)))
print("проверено файлов: %d, CJK: %d" % (len(FILES), bad))
sys.exit(1 if bad else 0)
