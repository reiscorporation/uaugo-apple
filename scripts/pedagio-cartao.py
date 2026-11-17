"""Cartão aceito nas praças de pedágio ESTADUAIS (assets/data/pedagio_cartao.json).

Por quê: pedido do Ricardo (15/11) — mostrar se a praça aceita débito e/ou
crédito. As FEDERAIS não entram aqui: desde a Decisão SUROD/ANTT nº 633
(13/06/2025) todas aceitam débito e crédito, e o app já sabe disso pelo
valor oficial da ANTT (TollCards.of).

Como: cada praça da tabela do app (public/pedagios.json.gz) pega a operadora
das cabines do OpenStreetMap a até 800 m (barrier=toll_booth + operator) e a
operadora vira "cd" (débito e crédito) ou "d" (só débito) pela lista da
ARTESP (praças com cartão por aproximação, atualizada em 23/04/2025) e pelas
notícias das próprias concessionárias (Eixo SP, Entrevias: débito).
Operadora fora da lista: a praça fica sem informação (o app não mostra nada).

Uso:
  osmium tags-filter brazil.osm.pbf n/barrier=toll_booth -o cab.pbf
  osmium export -f geojsonseq cab.pbf -o cab.geojsonseq
  python scripts/pedagio-cartao.py pedagios.json.gz cab.geojsonseq assets/data/pedagio_cartao.json
"""
import gzip
import json
import math
import re
import sys
import unicodedata

FONTE = ('Estaduais SP: ARTESP (23/04/2025) e concessionárias; '
         'federais: Decisão SUROD/ANTT 633/2025 (no app)')

# Operadora (normalizada, trecho do nome) -> código. A ordem importa: o
# primeiro trecho que aparecer no nome vale.
OPERADORAS = [
    # Débito e crédito (ARTESP)
    ('rodoviasdotiete', 'cd'), ('tebe', 'cd'), ('rotadasbandeiras', 'cd'),
    ('ecoviasimigrantes', 'cd'), ('ecopistas', 'cd'), ('viaoeste', 'cd'),
    ('spvias', 'cd'), ('autoban', 'cd'), ('rodoanel', 'cd'), ('tamoios', 'cd'),
    ('renovias', 'cd'), ('econoroeste', 'cd'), ('ecoviasnoroestepaulista', 'cd'),
    # Só débito (ARTESP; Eixo SP e Entrevias pelas notícias delas)
    ('colinas', 'd'), ('viarondon', 'd'), ('intervias', 'd'),
    ('viapaulista', 'd'), ('spmar', 'd'), ('eixosp', 'd'), ('entrevias', 'd'),
]


def norm(s):
    s = unicodedata.normalize('NFD', s).encode('ascii', 'ignore').decode().lower()
    return re.sub(r'[^a-z0-9]', '', s)


def code_of(operator):
    n = norm(operator)
    for key, c in OPERADORAS:
        if key in n:
            return c
    return None


def dist(a, b):
    k = math.cos(math.radians(a[0]))
    return math.hypot((a[0] - b[0]) * 111320, (a[1] - b[1]) * 111320 * k)


def main(table, cabs, out):
    t = json.load(gzip.open(table, 'rt', encoding='utf-8'))
    status = t.get('s', {})
    booths = []
    for line in open(cabs, encoding='utf-8'):
        line = line.strip().lstrip('\x1e')
        if not line:
            continue
        f = json.loads(line)
        p = f['properties']
        if p.get('barrier') != 'toll_booth' or not p.get('operator'):
            continue
        c = f['geometry']['coordinates']
        booths.append(((c[1], c[0]), p['operator']))
    res, hits = {}, {}
    for row in t['p']:
        pts = [(row[0], row[1])] + [(row[i], row[i + 1]) for i in range(5, len(row) - 1, 2)]
        key = '%.5f,%.5f' % (row[0], row[1])
        # Federal com valor da ANTT: o app já aplica a regra da ANTT.
        if key not in status and row[2] is not None:
            continue
        best = None
        for (b, op) in booths:
            if abs(b[0] - pts[0][0]) > 0.02 or abs(b[1] - pts[0][1]) > 0.02:
                continue
            d = min(dist(b, q) for q in pts)
            if d <= 800 and (best is None or d < best[0]):
                best = (d, op)
        if best is None:
            continue
        c = code_of(best[1])
        if c:
            res[key] = c
            hits[best[1]] = hits.get(best[1], 0) + 1
    json.dump({'v': 1, 'fonte': FONTE, 'k': dict(sorted(res.items()))},
              open(out, 'w', encoding='utf-8'), ensure_ascii=False, separators=(',', ':'))
    print('praças com cartão:', len(res), '| cd:', sum(1 for v in res.values() if v == 'cd'),
          '| d:', sum(1 for v in res.values() if v == 'd'))
    for op, n in sorted(hits.items(), key=lambda x: -x[1]):
        print(' ', n, op)


if __name__ == '__main__':
    main(*sys.argv[1:4])
