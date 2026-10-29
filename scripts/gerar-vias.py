"""Gera o pacote de rodovias de um estado para a visão 3D do UauGo2 (v2).

O que faz: lê as vias rápidas extraídas do OpenStreetMap (motorway, trunk,
  primary e as alças *_link, em GeoJSON sequencial do `osmium export`) e grava
  um arquivo compacto public/vias/UF.json.gz com, para cada via: tipo, número
  de faixas, mão única e o traçado (coordenadas em 1e-5 grau, em diferenças).
  A visão 3D usa isso para desenhar as faixas reais e as saídas no lugar exato.

Como gerar (exemplo SP, no PC com o mapa do Brasil em E:/UauGo-motor/dados):
  osmium extract -b -53.2,-25.4,-44.1,-19.7 brazil-latest.osm.pbf -o sp.osm.pbf
  osmium tags-filter sp.osm.pbf w/highway=motorway,motorway_link,trunk,trunk_link,primary,primary_link -o sp-vias.osm.pbf
  osmium export sp-vias.osm.pbf -f geojsonseq --geometry-types=linestring -o sp-vias.geojsonseq
  python scripts/gerar-vias.py sp-vias.geojsonseq SP saida/
Publicar: gcloud storage cp saida/SP.json.gz gs://<bucket>/public/vias/SP.json.gz
"""
import gzip
import json
import sys

CLS = {'motorway': 1, 'trunk': 2, 'primary': 3,
       'motorway_link': 4, 'trunk_link': 4, 'primary_link': 4}


def lanes_of(p, cls):
    try:
        n = int(str(p.get('lanes', '')).split(';')[0])
        if n > 0:
            return min(n, 8)
    except ValueError:
        pass
    # sem a informação: alça 1 faixa, via expressa de mão única 2
    return 1 if cls == 4 else 2


def main(src, uf, out_dir):
    ways = []
    bbox = [999, 999, -999, -999]
    with open(src, encoding='utf-8') as f:
        for line in f:
            line = line.strip().lstrip('\x1e')
            if not line:
                continue
            ft = json.loads(line)
            p, g = ft['properties'], ft['geometry']
            cls = CLS.get(p.get('highway'))
            if not cls or g['type'] != 'LineString':
                continue
            oneway = p.get('oneway') in ('yes', '1', 'true') or cls == 1 or (
                cls == 4 and p.get('oneway') != 'no')
            if p.get('oneway') == '-1':
                g['coordinates'] = g['coordinates'][::-1]
                oneway = True
            # pista simples de mão dupla: "lanes" é o total; por sentido = metade
            n = lanes_of(p, cls)
            flat, plat, plon = [], 0, 0
            for lon, lat in g['coordinates']:
                a, b = round(lat * 1e5), round(lon * 1e5)
                flat += [a - plat, b - plon]
                plat, plon = a, b
                bbox = [min(bbox[0], lat), min(bbox[1], lon), max(bbox[2], lat), max(bbox[3], lon)]
            ways.append([cls, n, 1 if oneway else 0, flat])
    data = {'v': 1, 'uf': uf, 'bbox': [round(x, 4) for x in bbox], 'w': ways}
    raw = json.dumps(data, separators=(',', ':')).encode()
    path = f'{out_dir.rstrip("/")}/{uf}.json.gz'
    with gzip.open(path, 'wb', 9) as f:
        f.write(raw)
    print(uf, len(ways), 'vias', len(raw) // 1024, 'KB ->', path)


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2], sys.argv[3])
