"""t33: одноразовая замена опасных кастов String(Variant) на безопасный str-хелпер."""
import io
import sys

p = r"diag-t33/census_t33.gd"
s = io.open(p, encoding="utf-8").read()
n = s.count("String(")
s = s.replace("String(", "_s(")
io.open(p, "w", encoding="utf-8", newline="\n").write(s)
print("заменено String( -> _s( :", n)
sys.exit(0)
