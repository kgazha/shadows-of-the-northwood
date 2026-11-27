import io, re, sys
TOK = re.compile(r"[A-Za-z\u0400-\u04ff]+")
ESC = re.compile(r"\\[nrtvfae0\"'\\]")   # экпейп-последовательности (\n и иже) — не токены
bad = 0
for f in sys.argv[1:]:
    for i, ln in enumerate(io.open(f, encoding="utf-8").read().splitlines(), 1):
        for t in TOK.findall(ESC.sub(" ", ln)):
            if re.search(r"[\u0400-\u04ff]", t) and re.search(r"[A-Za-z]", t):
                print("ПОДОЗРЕНИЕ %s:%d: %s" % (f, i, t)); bad += 1
print("проверено файлов: %d, смешанных токенов: %d" % (len(sys.argv[1:]), bad))
