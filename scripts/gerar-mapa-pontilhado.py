"""Gera o mapa-múndi pontilhado do fundo da tela inicial (e da arte da loja).

  python scripts/gerar-mapa-pontilhado.py      (precisa do Pillow e de internet)

Baixa os contornos dos continentes (world-atlas, dados Natural Earth, domínio
público), projeta em equirretangular (2:1) e marca um ponto onde há terra.
Saída: assets/branding/mapa_pontilhado.png (fundo transparente, pontos azuis
claros e discretos, para ficar atrás da seta laranja).
"""
import json
import os
import urllib.request
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
URL = "https://cdn.jsdelivr.net/npm/world-atlas@2/land-110m.json"
W, H = 1200, 600          # 2:1 (equirretangular)
STEP = 15                 # distância entre pontos (px)
DOT = 5.0                 # diâmetro do ponto (px)
COLOR = (120, 160, 210, 72)  # azul claro, ~28% de opacidade


def decode(topo):
    """TopoJSON -> lista de anéis [(lon, lat), ...] da camada 'land'."""
    sx, sy = topo["transform"]["scale"]
    tx, ty = topo["transform"]["translate"]
    arcs = []
    for arc in topo["arcs"]:
        x = y = 0
        pts = []
        for dx, dy in arc:
            x += dx
            y += dy
            pts.append((x * sx + tx, y * sy + ty))
        arcs.append(pts)

    def ring(idx):
        out = []
        for i in idx:
            a = arcs[i] if i >= 0 else arcs[~i][::-1]
            out.extend(a if not out else a[1:])
        return out

    rings = []
    for geom in topo["objects"]["land"]["geometries"]:
        polys = geom["arcs"] if geom["type"] == "MultiPolygon" else [geom["arcs"]]
        for poly in polys:
            rings.extend(ring(r) for r in poly)
    return rings


def inside(lon, lat, rings):
    """Regra par-ímpar: dentro de terra se cruza um número ímpar de bordas."""
    c = False
    for r in rings:
        j = len(r) - 1
        for i in range(len(r)):
            xi, yi = r[i]
            xj, yj = r[j]
            if (yi > lat) != (yj > lat) and lon < (xj - xi) * (lat - yi) / (yj - yi) + xi:
                c = not c
            j = i
    return c


topo = json.loads(urllib.request.urlopen(URL, timeout=60).read())
rings = decode(topo)
ss = 3
img = Image.new("RGBA", (W * ss, H * ss), (0, 0, 0, 0))
d = ImageDraw.Draw(img)
r = DOT / 2 * ss
for py in range(STEP // 2, H, STEP):
    lat = 90 - py / H * 180
    if lat < -58:  # sem a Antártida (só uma faixa de pontos embaixo)
        continue
    for px in range(STEP // 2, W, STEP):
        lon = px / W * 360 - 180
        if inside(lon, lat, rings):
            cx, cy = px * ss, py * ss
            d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=COLOR)
out = os.path.join(ROOT, "assets", "branding", "mapa_pontilhado.png")
# Corta o espaço vazio de cima (polo) e de baixo (sem a Antártida).
img.resize((W, H), Image.LANCZOS).crop((0, 10, W, 500)).save(out)
print("ok:", out)
