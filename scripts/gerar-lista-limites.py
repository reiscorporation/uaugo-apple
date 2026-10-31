"""Lista em Excel dos trechos de rodovia sem limite de velocidade confiável.

Cruza as rodovias do OpenStreetMap (motorway, trunk, primary com código de
rodovia) com os arquivos de limites que o app usa (public/limites/UF.json.gz).
A cada 200 m, classifica o ponto:
  - Sem limite: nenhum ponto de limite a menos de 150 m (o alcance do app ao longo da via);
  - Estimado: o app só tem limite estimado pelo tipo de via (sem placa);
  - Divergente: o limite do app difere 20 km/h ou mais do "maxspeed" do mapa.

Uso: python scripts/gerar-lista-limites.py <pasta com UF.json.gz> <br-vias.geojsonseq> <saida.xlsx>
"""
import glob
import gzip
import json
import math
import os
import re
import sys
from collections import Counter, defaultdict

from openpyxl import Workbook
from openpyxl.styles import Alignment, Font, PatternFill
from openpyxl.utils import get_column_letter

REF = re.compile(r'^(BR|[A-Z]{2}[A-Z]?)-?\d{2,3}')
STEP, NEAR, MIN_KM = 200.0, 150.0, 0.5
STATUS = ['Sem limite', 'Estimado (sem placa)', 'Divergente do mapa']


def dist(a, b, c, d):
    k = math.cos(math.radians(a)) * 111320
    return math.hypot((d - b) * k, (c - a) * 110540)


def load_limits(folder):
    cells, coarse = defaultdict(list), defaultdict(Counter)
    for f in sorted(glob.glob(folder + '/*.json.gz')):
        uf = os.path.basename(f)[:2]
        j = json.load(gzip.open(f))
        d, lat, lng = j['d'], 0, 0
        for i in range(0, len(d) - 4, 5):
            lat += d[i]
            lng += d[i + 1]
            la, lo = lat / 1e5, lng / 1e5
            cells[(int(la * 400 // 1), int(lo * 400 // 1))].append((la, lo, d[i + 2], d[i + 3]))
            coarse[(round(la * 5), round(lo * 5))][uf] += 1
    return cells, coarse


def lookup(cells, la, lo):
    gx, gy = int(la * 400 // 1), int(lo * 400 // 1)
    best, bd = None, NEAR
    for i in (-1, 0, 1):
        for j in (-1, 0, 1):
            for p in cells.get((gx + i, gy + j), ()):
                x = dist(la, lo, p[0], p[1])
                if x < bd:
                    best, bd = p, x
    return best


def uf_of(coarse, ref, la, lo):
    m = re.match(r'^([A-Z]{2})-', ref)
    if m and m.group(1) != 'BR':
        return m.group(1)
    c = coarse.get((round(la * 5), round(lo * 5)))
    if c:
        return c.most_common(1)[0][0]
    for r in (1, 2, 3):
        t = Counter()
        for i in range(-r, r + 1):
            for j in range(-r, r + 1):
                t.update(coarse.get((round(la * 5) + i, round(lo * 5) + j), {}))
        if t:
            return t.most_common(1)[0][0]
    return '?'


def samples(coords):
    """Pontos a cada STEP metros ao longo da linha (lng, lat)."""
    out, carry = [(coords[0][1], coords[0][0])], 0.0
    for (ax, ay), (bx, by) in zip(coords, coords[1:]):
        L = dist(ay, ax, by, bx)
        if L == 0:
            continue
        d = STEP - carry
        while d <= L:
            u = d / L
            out.append((ay + (by - ay) * u, ax + (bx - ax) * u))
            d += STEP
        carry = L - (d - STEP)
    return out


def maxspeed(p):
    m = re.match(r'^(\d{2,3})', str(p.get('maxspeed', '')))
    return int(m.group(1)) if m else None


def main(folder, src, out):
    cells, coarse = load_limits(folder)
    print('pontos de limite carregados')
    runs, total_km = [], 0.0
    for line in open(src, encoding='utf-8'):
        line = line.strip().lstrip('\x1e')
        if not line:
            continue
        ft = json.loads(line)
        p = ft['properties']
        ref = str(p.get('ref', '')).split(';')[0].strip().upper().replace(' ', '-')
        cls = p.get('highway')
        if not REF.match(ref) and cls == 'primary':
            continue  # avenida urbana, sem código de rodovia
        if not REF.match(ref):
            ref = '(sem código)'
        ms, cur = maxspeed(p), None
        pts = samples(ft['geometry']['coordinates'])
        total_km += len(pts) * STEP / 1000
        for la, lo in pts:
            h = lookup(cells, la, lo)
            if h is None:
                st, lim = 0, None
            elif ms and abs(h[2] - ms) >= 20:
                st, lim = 2, h[2]
            elif h[3] == 1:
                st, lim = 1, h[2]
            else:
                st, lim = None, h[2]
            if cur and cur['st'] == st and cur['lim'] == lim:
                cur['end'] = (la, lo)
                cur['km'] += STEP / 1000
                continue
            cur = None
            if st is not None:
                cur = {'st': st, 'lim': lim, 'ms': ms, 'ref': ref, 'name': p.get('name', ''),
                       'ini': (la, lo), 'end': (la, lo), 'km': STEP / 1000}
                runs.append(cur)
    # junta trechos seguidos da mesma rodovia e situação
    runs.sort(key=lambda r: (r['ref'], r['st'], r['ini']))
    merged = []
    for r in runs:
        m = merged[-1] if merged else None
        if m and (m['ref'], m['st'], m['lim'], m['ms']) == (r['ref'], r['st'], r['lim'], r['ms']) and \
                dist(*m['end'], *r['ini']) < 600:
            m['end'] = r['end']
            m['km'] += r['km']
        else:
            merged.append(dict(r))
    rows = [r for r in merged if r['km'] >= MIN_KM]
    for r in rows:
        r['uf'] = uf_of(coarse, r['ref'], *r['ini'])
    rows.sort(key=lambda r: (r['uf'], r['ref'], r['st'], -r['km']))
    print(len(rows), 'trechos;', round(total_km), 'km analisados')

    wb = Workbook()
    resumo = wb.active
    resumo.title = 'Resumo'
    ws = wb.create_sheet('Trechos')
    head = ['UF', 'Rodovia', 'Nome da via', 'Situação', 'Limite no app (km/h)',
            'Limite no mapa aberto (km/h)', 'Extensão (km)', 'Início lat', 'Início lng',
            'Fim lat', 'Fim lng', 'Ver no mapa']
    ws.append(head)
    for r in rows:
        ws.append([r['uf'], r['ref'], r['name'], STATUS[r['st']], r['lim'], r['ms'], round(r['km'], 1),
                   round(r['ini'][0], 5), round(r['ini'][1], 5), round(r['end'][0], 5), round(r['end'][1], 5), None])
        c = ws.cell(ws.max_row, 12)
        c.value = 'Abrir'
        c.hyperlink = f"https://www.google.com/maps?q={r['ini'][0]:.5f},{r['ini'][1]:.5f}"
        c.font = Font(name='Arial', size=10, color='0563C1', underline='single')
    fill = PatternFill('solid', fgColor='1F3864')
    for row in ws.iter_rows(min_row=2, max_col=11):
        for c in row:
            c.font = Font(name='Arial', size=10)
    for c in ws[1]:
        c.font = Font(name='Arial', size=10, bold=True, color='FFFFFF')
        c.fill = fill
        c.alignment = Alignment(wrap_text=True, vertical='center')
    for i, w in enumerate([6, 14, 38, 22, 11, 12, 10, 11, 11, 11, 11, 10], 1):
        ws.column_dimensions[get_column_letter(i)].width = w
    ws.freeze_panes = 'A2'
    ws.auto_filter.ref = ws.dimensions

    A = Font(name='Arial', size=10)
    B = Font(name='Arial', size=10, bold=True)
    resumo['A1'] = 'Rodovias sem limite de velocidade confiável no UauGo'
    resumo['A1'].font = Font(name='Arial', size=14, bold=True)
    notes = [
        f'Base: rodovias do OpenStreetMap, {round(total_km)} km analisados a cada 200 m; limites: os mesmos arquivos do app.',
        'Sem limite: nenhum ponto de limite a menos de 150 m. Estimado: limite deduzido do tipo de via, sem placa. '
        'Divergente: difere 20 km/h ou mais do mapa aberto (um dos dois pode estar errado).',
        'Trechos menores que 500 m ficam de fora. Em BR, a UF é aproximada pelos pontos próximos.',
    ]
    for i, t in enumerate(notes, 2):
        resumo.cell(i, 1, t).font = A
    top = 6
    hd = ['UF'] + [f'{s} (km)' for s in STATUS] + ['Total (km)', 'Trechos']
    for j, t in enumerate(hd, 1):
        c = resumo.cell(top, j, t)
        c.font = Font(name='Arial', size=10, bold=True, color='FFFFFF')
        c.fill = fill
        c.alignment = Alignment(wrap_text=True, vertical='center')
    ufs = sorted({r['uf'] for r in rows})
    n = ws.max_row
    for i, uf in enumerate(ufs, top + 1):
        resumo.cell(i, 1, uf).font = A
        for j, s in enumerate(STATUS, 2):
            c = resumo.cell(i, j, f'=SUMIFS(Trechos!$G$2:$G${n},Trechos!$A$2:$A${n},$A{i},Trechos!$D$2:$D${n},"{s}")')
            c.font = A
            c.number_format = '#,##0.0'
        c = resumo.cell(i, 5, f'=SUM(B{i}:D{i})')
        c.font = A
        c.number_format = '#,##0.0'
        c = resumo.cell(i, 6, f'=COUNTIF(Trechos!$A$2:$A${n},$A{i})')
        c.font = A
        c.number_format = '#,##0'
    last = top + len(ufs)
    resumo.cell(last + 1, 1, 'Total').font = B
    for j in range(2, 7):
        L = get_column_letter(j)
        c = resumo.cell(last + 1, j, f'=SUM({L}{top + 1}:{L}{last})')
        c.font = B
        c.number_format = '#,##0.0' if j < 6 else '#,##0'
    resumo.column_dimensions['A'].width = 9
    for L in 'BCDEF':
        resumo.column_dimensions[L].width = 15
    wb.save(out)
    print('salvo', out)


if __name__ == '__main__':
    main(*sys.argv[1:4])
