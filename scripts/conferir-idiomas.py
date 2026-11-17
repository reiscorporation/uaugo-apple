"""Confere se todo texto do app tem tradução em inglês e espanhol.

O que faz: acha cada tr('texto') em lib/ e confere se 'texto' está nos
  dicionários lib/l10n/en*.dart e lib/l10n/es*.dart. Lista o que falta.
  Textos montados com variável (tr(x)) não entram (não dá para saber o texto).
Uso: python scripts/conferir-idiomas.py
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIT = r"(?:r?'((?:[^'\\]|\\.)*)'|r?\"((?:[^\"\\]|\\.)*)\")"
TR = re.compile(r"\btr\(\s*" + LIT)
KEY = re.compile(r"^\s*" + LIT + r"\s*:", re.M)


def keys(prefix):
    out = set()
    d = os.path.join(ROOT, 'lib', 'l10n')
    for f in os.listdir(d):
        if f.startswith(prefix) and f.endswith('.dart'):
            for m in KEY.finditer(open(os.path.join(d, f), encoding='utf-8').read()):
                out.add(m.group(1) if m.group(1) is not None else m.group(2))
    return out


used = {}
for base, _, files in os.walk(os.path.join(ROOT, 'lib')):
    if os.sep + 'l10n' in base:
        continue
    for f in files:
        if not f.endswith('.dart'):
            continue
        p = os.path.join(base, f)
        src = open(p, encoding='utf-8').read()
        for m in TR.finditer(src):
            k = m.group(1) if m.group(1) is not None else m.group(2)
            used.setdefault(k, os.path.relpath(p, ROOT))

en, es = keys('en'), keys('es')
falta_en = sorted(k for k in used if k not in en)
falta_es = sorted(k for k in used if k not in es)
print(f'textos com tr(): {len(used)} | sem inglês: {len(falta_en)} | sem espanhol: {len(falta_es)}')
for k in falta_es:
    print(f'  [{"en " if k in falta_en else "   "}es] {k}  ({used[k]})')
sys.exit(1 if falta_en or falta_es else 0)
