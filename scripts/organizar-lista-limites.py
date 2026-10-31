"""Reorganiza a lista gerada por gerar-lista-limites.py (sem refazer o cruzamento).

Corrige a UF, separa as abas e deixa os trechos utilizáveis:
  uma planilha por estado (Por rodovia e Trechos a partir de 1 km) e _Brasil-resumo.
Uso: python scripts/organizar-lista-limites.py <entrada.xlsx> <pasta UF.json.gz> <pasta de saída>
"""
import glob
import gzip
import json
import os
import sys
from collections import Counter, defaultdict

from openpyxl import Workbook, load_workbook
from openpyxl.styles import Alignment, Font, PatternFill
from openpyxl.utils import get_column_letter

UFS = set('AC AL AM AP BA CE DF ES GO MA MG MS MT PA PB PE PI PR RJ RN RO RR RS SC SE SP TO'.split())
STATUS = ['Sem limite', 'Estimado (sem placa)', 'Divergente do mapa']
MIN_KM = 1.0
F, B = Font(name='Arial', size=10), Font(name='Arial', size=10, bold=True)
HEAD = Font(name='Arial', size=10, bold=True, color='FFFFFF')
FILL = PatternFill('solid', fgColor='1F3864')


def coarse_map(folder):
    c = defaultdict(Counter)
    for f in glob.glob(folder + '/*.json.gz'):
        uf = os.path.basename(f)[:2]
        d = json.load(gzip.open(f))['d']
        lat = lng = 0
        for i in range(0, len(d) - 4, 5):
            lat += d[i]
            lng += d[i + 1]
            c[(round(lat / 1e5 * 5), round(lng / 1e5 * 5))][uf] += 1
    return c


def fix_uf(uf, la, lo, coarse):
    if uf in UFS:
        return uf
    for r in range(0, 6):
        t = Counter()
        for i in range(-r, r + 1):
            for j in range(-r, r + 1):
                t.update(coarse.get((round(la * 5) + i, round(lo * 5) + j), {}))
        if t:
            return t.most_common(1)[0][0]
    return 'BR'


def header(ws, row, names, widths):
    for j, (t, w) in enumerate(zip(names, widths), 1):
        c = ws.cell(row, j, t)
        c.font, c.fill = HEAD, FILL
        c.alignment = Alignment(wrap_text=True, vertical='center')
        ws.column_dimensions[get_column_letter(j)].width = w


def por_rodovia(ws, rows):
    """Aba com os km de cada rodovia por situação, maiores primeiro."""
    total = defaultdict(float)
    for r in rows:
        total[(r[0], r[1], r[3])] += r[6]
    header(ws, 1, ['UF', 'Rodovia'] + [f'{s} (km)' for s in STATUS] + ['Total (km)'], [6, 16, 13, 15, 15, 12])
    keys = sorted({(u, x) for u, x, _ in total}, key=lambda k: -sum(total[(k[0], k[1], s)] for s in STATUS))
    for i, (u, x) in enumerate(keys, 2):
        ws.append([u, x, *[round(total[(u, x, s)], 1) for s in STATUS], f'=SUM(C{i}:E{i})'])
    for row in ws.iter_rows(min_row=2):
        for c in row:
            c.font = F
    ws.freeze_panes = 'A2'
    ws.auto_filter.ref = ws.dimensions
    return total


def trechos(ws, rows):
    """Aba com os trechos a partir de 1 km, "Sem limite" primeiro."""
    names = ['UF', 'Rodovia', 'Nome da via', 'Situação', 'Limite no app (km/h)', 'Limite no mapa aberto (km/h)',
             'Extensão (km)', 'Início lat', 'Início lng', 'Fim lat', 'Fim lng', 'Ver no mapa']
    header(ws, 1, names, [6, 14, 36, 21, 10, 11, 10, 10, 10, 10, 10, 10])
    keep = sorted((r for r in rows if r[6] >= MIN_KM), key=lambda r: (STATUS.index(r[3]), r[1], -r[6]))
    for r in keep:
        ws.append(r)
        n = ws.max_row
        for j in range(1, 12):
            ws.cell(n, j).font = F
        c = ws.cell(n, 12, 'Abrir')
        c.hyperlink = f'https://www.google.com/maps?q={r[7]},{r[8]}'
        c.font = Font(name='Arial', size=10, color='0563C1', underline='single')
    ws.freeze_panes = 'A2'
    ws.auto_filter.ref = ws.dimensions
    return len(keep)


NOTES = [
    'Base: rodovias do mapa aberto (OpenStreetMap), comparadas a cada 200 m com os limites que o app usa hoje.',
    'Sem limite: nenhum ponto de limite a menos de 150 m. Estimado: limite deduzido do tipo de via, sem placa. '
    'Divergente: difere 20 km/h ou mais do mapa aberto (um dos dois pode estar errado).',
    'Pista dupla conta os dois sentidos, então os km somam mais que a extensão da rodovia. '
    '"(sem código)": via sem número de rodovia no mapa. Em BR, a UF é aproximada.',
    'Por rodovia soma tudo; Trechos lista só trechos a partir de 1 km.',
]


def main(src, folder, outdir):
    os.makedirs(outdir, exist_ok=True)
    coarse = coarse_map(folder)
    rows = []
    for r in load_workbook(src, read_only=True)['Trechos'].iter_rows(min_row=2, max_col=11, values_only=True):
        r = list(r)
        r[0] = fix_uf(r[0], r[7], r[8], coarse)
        rows.append(r)
    ufs = sorted({r[0] for r in rows})
    for u in ufs:
        sub = [r for r in rows if r[0] == u]
        wb = Workbook()
        por = wb.active
        por.title = 'Por rodovia'
        por_rodovia(por, sub)
        n = trechos(wb.create_sheet('Trechos'), sub)
        wb.save(f'{outdir}/{u}.xlsx')
        print(u, len(sub), n)

    wb = Workbook()
    res = wb.active
    res.title = 'Resumo'
    por = wb.create_sheet('Por rodovia')
    total = por_rodovia(por, rows)
    res['A1'] = 'Rodovias sem limite de velocidade confiável no UauGo'
    res['A1'].font = Font(name='Arial', size=14, bold=True)
    for i, t in enumerate(NOTES, 2):
        res.cell(i, 1, t).font = F
    top = 7
    header(res, top, ['UF'] + [f'{s} (km)' for s in STATUS] + ['Total (km)'], [9, 15, 15, 15, 15])
    n = por.max_row
    for i, u in enumerate(ufs, top + 1):
        res.cell(i, 1, u).font = F
        for j, L in zip((2, 3, 4), 'CDE'):
            c = res.cell(i, j, f"=SUMIFS('Por rodovia'!${L}$2:${L}${n},'Por rodovia'!$A$2:$A${n},$A{i})")
            c.font, c.number_format = F, '#,##0'
        c = res.cell(i, 5, f'=SUM(B{i}:D{i})')
        c.font, c.number_format = F, '#,##0'
    last = top + len(ufs)
    res.cell(last + 1, 1, 'Total').font = B
    for j in range(2, 6):
        L = get_column_letter(j)
        c = res.cell(last + 1, j, f'=SUM({L}{top + 1}:{L}{last})')
        c.font, c.number_format = B, '#,##0'
    wb.calculation.fullCalcOnLoad = True
    wb.save(f'{outdir}/_Brasil-resumo.xlsx')
    print({s: round(sum(v for k, v in total.items() if k[2] == s)) for s in STATUS})
    ks = sorted({(k[0], k[1]) for k in total}, key=lambda k: -total[(k[0], k[1], STATUS[0])])
    print('top', [(k, round(total[(k[0], k[1], STATUS[0])])) for k in ks[:8]])


if __name__ == '__main__':
    main(*sys.argv[1:4])
