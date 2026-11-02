"""Áreas com muitos roubos, a partir de dados públicos (para "Evitar locais de risco").

O que faz: baixa os boletins publicados pela SSP-SP, conta roubos e latrocínios
  dos últimos 12 meses em quadrados de ~250 m e grava só os quadrados críticos.
  O arquivo não leva endereço nem boletim: só o centro do quadrado e a contagem.
  O app pede ao motor para desviar deles (RouteEngineService).

Uso: python scripts/areas-risco.py <areas.json> [pasta para guardar os downloads]
Roda na VPS uma vez por semana (docs/PLANO-MOTOR-ROTAS.md). Sai sem gravar se a
  fonte falhar: o arquivo anterior continua valendo.
"""
import collections
import datetime
import json
import os
import sys
import tempfile
import urllib.request

import openpyxl

SSP = 'https://www.ssp.sp.gov.br/assets/estatistica/transparencia/spDados/SPDadosCriminais_%d.xlsx'
CELL = 250 / 111320  # graus
MIN_ROUBOS = 24  # por ano no quadrado (2 por mês)
MIN_PONTOS = 5  # coordenadas diferentes: evita o endereço padrão de um cadastro
DAYS = 365


def baixar(ano, pasta):
    p = os.path.join(pasta, f'ssp-{ano}.xlsx')
    r = urllib.request.Request(SSP % ano, headers={'User-Agent': 'Mozilla/5.0'})
    with urllib.request.urlopen(r, timeout=120) as f, open(p, 'wb') as o:
        while True:
            b = f.read(1 << 20)
            if not b:
                return p
            o.write(b)


def roubos(arquivo, desde):
    """(lat, lng) de cada roubo desde [desde], sem repetir o mesmo boletim."""
    wb = openpyxl.load_workbook(arquivo, read_only=True)
    vistos = set()
    for aba in wb.sheetnames[1:]:
        h = None
        for r in wb[aba].iter_rows(values_only=True):
            if h is None:
                if r and 'LATITUDE' in r:
                    h = {k: j for j, k in enumerate(r) if k}
                continue
            nat = str(r[h['NATUREZA_APURADA']])
            if not nat.startswith(('ROUBO', 'LATROC')):
                continue
            d = r[h['DATA_OCORRENCIA_BO']]
            if not isinstance(d, datetime.datetime) or d < desde:
                continue
            bo = (r[h['NUM_BO']], r[h['ANO_BO']], r[h['NOME_DELEGACIA']], nat)
            if bo in vistos:
                continue
            vistos.add(bo)
            try:
                la, lo = float(r[h['LATITUDE']]), float(r[h['LONGITUDE']])
            except (TypeError, ValueError):
                continue
            if la:
                yield la, lo


def criticos(pontos):
    n = collections.Counter()
    dif = collections.defaultdict(set)
    for la, lo in pontos:
        c = (round(la / CELL), round(lo / CELL))
        n[c] += 1
        dif[c].add((round(la, 5), round(lo, 5)))
    return sorted(([round(a * CELL, 5), round(o * CELL, 5), v] for (a, o), v in n.items()
                   if v >= MIN_ROUBOS and len(dif[a, o]) >= MIN_PONTOS),
                  key=lambda c: -c[2])


def main(saida, pasta=None):
    hoje = datetime.datetime.now()
    desde = hoje - datetime.timedelta(days=DAYS)
    with tempfile.TemporaryDirectory() as tmp:
        pasta = pasta or tmp
        pts = []
        for ano in (hoje.year, hoje.year - 1):
            pts += roubos(baixar(ano, pasta), desde)
    if len(pts) < 50000:  # SP tem mais de 100 mil por ano
        sys.exit(f'poucos dados: {len(pts)}')
    cel = criticos(pts)
    t = saida + '.tmp'
    with open(t, 'w', encoding='utf-8') as f:
        json.dump({'v': 1, 'criado': hoje.date().isoformat(), 'fontes': ['SSP-SP'],
                   'lado': round(CELL, 6), 'c': cel}, f, separators=(',', ':'))
    os.replace(t, saida)
    print('roubos', len(pts), 'quadrados', len(cel), 'neles', sum(c[2] for c in cel))


if __name__ == '__main__':
    main(*sys.argv[1:3])
