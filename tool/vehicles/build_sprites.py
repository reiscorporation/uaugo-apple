"""Gera os ícones 3D dos veículos (mapa 2D) a partir das folhas em src/.

Uso:  python -I tool/vehicles/build_sprites.py   (na raiz do projeto)

Cada folha tem o veículo em 4 vistas sobre fundo verde #00FF00. Para cada
vista: tira o verde, fica só com o maior pedaço (a roda do vizinho que
invade o quadro sai), vira para a direção padrão e grava:
  assets/vehicles/<tipo>_<n>.png    imagem (RGBA)
  assets/vehicles/<tipo>_<n>_m.png  onde é pintura (0-255), para trocar a cor
Direções padrão (0 = indo para cima da tela, horário):
  0 = de trás (0°), 1 = ¾ de trás indo para a direita (45°),
  2 = de lado indo para a direita (90°), 3 = ¾ de frente indo para a direita (135°).
As outras direções o app tira espelhando estas. Também grava preview.png.
"""
import os
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(ROOT, '..', '..', 'assets', 'vehicles')
MAX = 256  # maior lado gravado (px)

# tipo: (folha, região x0,y0,x1,y1, direção de cada vista da esquerda para a
#        direita e de cima para baixo, matiz da pintura 0-1 ou None = não troca,
#        [folga da matiz, padrão 0.04])
SHEETS = {
    'custom': ('custom.png', None, [0, 315, 90, 135], 0.0),
    'adventure': ('adventure.png', None, [0, 45, 90, 135], 0.0),
    'car': ('frota.png', (0, 300, 768, 440), [0, 45, 270, 225], 0.62),
    'pickup': ('frota.png', (0, 500, 768, 680), [0, 45, 270, 225], 0.62),
    'motorhome': ('frota.png', (768, 500, 1536, 680), [0, 45, 90, 225], None),
    'truck': ('frota.png', (0, 720, 768, 940), [0, 45, 90, 225], 0.0, 0.08),
    'bus': ('frota.png', (768, 720, 1536, 940), [0, 45, 90, 135], 0.6),
}


def key(rgb):
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    spill = g - np.maximum(r, b)
    alpha = 1 - np.clip((spill - 0.12) / 0.25, 0, 1)
    g2 = np.minimum(g, np.maximum(r, b) + 0.02)  # tira o verde das bordas
    return np.stack([r, g2, b], -1), alpha


def components(mask, f=4, min_px=150):
    """Pedaços ligados (em resolução 1/f). Devolve [(tamanho, máscara 1/f)]."""
    H, W = mask.shape
    s = mask[:H // f * f, :W // f * f].reshape(H // f, f, W // f, f).any(axis=(1, 3))
    lab = np.zeros(s.shape, np.int32)
    out = []
    for y0 in range(s.shape[0]):
        for x0 in range(s.shape[1]):
            if not s[y0, x0] or lab[y0, x0]:
                continue
            n = len(out) + 1
            lab[y0, x0] = n
            st, cnt = [(y0, x0)], 0
            while st:
                y, x = st.pop()
                cnt += 1
                for dy in (-1, 0, 1):
                    for dx in (-1, 0, 1):
                        yy, xx = y + dy, x + dx
                        if 0 <= yy < s.shape[0] and 0 <= xx < s.shape[1] and s[yy, xx] and not lab[yy, xx]:
                            lab[yy, xx] = n
                            st.append((yy, xx))
            out.append(cnt)
    res = []
    for i, cnt in enumerate(out):
        if cnt < min_px:
            continue
        m = np.kron(lab == i + 1, np.ones((f, f), bool))
        full = np.zeros(mask.shape, bool)
        full[:m.shape[0], :m.shape[1]] = m
        res.append((cnt, full))
    return res


def paint_mask(rgb, alpha, hue, tol):
    if hue is None:
        return np.zeros(alpha.shape, np.float32)
    hsv = np.asarray(Image.fromarray((rgb * 255).astype(np.uint8)).convert('HSV')).astype(np.float32) / 255
    h, s, v = hsv[..., 0], hsv[..., 1], hsv[..., 2]
    hd = np.abs(h - hue)
    hd = np.minimum(hd, 1 - hd)
    p = np.clip(1 - (hd - tol) / 0.05, 0, 1) * np.clip((s - 0.42) / 0.2, 0, 1) * (alpha > 0.5)
    # Luzes (lanterna, piscas): pedaços pequenos e muito claros não trocam de cor.
    area = (alpha > 0.5).sum()
    keep = np.zeros(p.shape, bool)
    for cnt, m in components(p > 0.3, f=2, min_px=1):
        if cnt * 4 >= area * 0.006:
            keep |= m
    lights = (v > 0.85) & (s > 0.5) & ~keep
    p = p * keep
    p[lights] = 0
    return p.astype(np.float32)


def build(kind, sheet, region, heads, hue, tol=0.04):
    img = np.asarray(Image.open(os.path.join(ROOT, 'src', sheet)).convert('RGB')).astype(np.float32) / 255
    rgb, alpha = key(img)
    H, W = alpha.shape
    if region is None:  # grade 2x2: uma vista por quadrado
        cells = [(qx * W // 2, qy * H // 2, (qx + 1) * W // 2, (qy + 1) * H // 2) for qy in range(2) for qx in range(2)]
        views = []
        for x0, y0, x1, y1 in cells:
            comps = components(alpha[y0:y1, x0:x1] > 0.5)
            m = max(comps, key=lambda c: c[0])[1]
            full = np.zeros(alpha.shape, bool)
            full[y0:y1, x0:x1] = m
            views.append(full)
    else:
        x0, y0, x1, y1 = region
        comps = components(alpha[y0:y1, x0:x1] > 0.5)
        comps = sorted(comps, key=lambda c: -c[0])[:4]
        views = []
        for _, m in comps:
            full = np.zeros(alpha.shape, bool)
            full[y0:y1, x0:x1] = m
            views.append(full)
        views.sort(key=lambda m: np.where(m.any(0))[0][0])
    out = []
    for i, (m, hd) in enumerate(zip(views, heads)):
        # alarga a máscara (a borda suave do recorte fica dentro)
        grow = m.copy()
        for _ in range(6):
            g2 = grow.copy()
            g2[1:] |= grow[:-1]; g2[:-1] |= grow[1:]; g2[:, 1:] |= grow[:, :-1]; g2[:, :-1] |= grow[:, 1:]
            grow = g2
        a = alpha * grow
        ys, xs = np.where(a > 0.02)
        y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
        c, al = rgb[y0:y1, x0:x1], a[y0:y1, x0:x1]
        p = paint_mask(c, al, hue, tol)
        if hd in (315, 270, 225):  # olhando para a esquerda: espelha
            c, al, p = c[:, ::-1], al[:, ::-1], p[:, ::-1]
        im = Image.fromarray(np.dstack([c * 255, al * 255]).clip(0, 255).astype(np.uint8), 'RGBA')
        pm = Image.fromarray((p * 255).astype(np.uint8), 'L')
        sc = MAX / max(im.size)
        if sc < 1:
            size = (round(im.width * sc), round(im.height * sc))
            im, pm = im.resize(size, Image.LANCZOS), pm.resize(size, Image.LANCZOS)
        im.save(os.path.join(OUT, f'{kind}_{i}.png'), optimize=True)
        pm.save(os.path.join(OUT, f'{kind}_{i}_m.png'), optimize=True)
        out.append((im, pm))
    return out


def recolor(im, pm, color):
    """O mesmo cálculo do app (lib/widgets/vehicle_sprite.dart)."""
    import colorsys
    a = np.asarray(im).astype(np.float32) / 255
    hsv = np.asarray(im.convert('RGB').convert('HSV')).astype(np.float32) / 255
    th, ts, tv = colorsys.rgb_to_hsv(*[x / 255 for x in color])
    v = hsv[..., 2]
    if ts < 0.15:
        lum = np.clip(v * (0.15 + 0.9 * tv), 0, 1)
        new = np.stack([lum] * 3, -1)
    else:
        new = np.asarray(Image.fromarray((np.stack([np.full_like(v, th), np.clip(hsv[..., 1] * ts, 0, 1), np.clip(v * (0.25 + 0.85 * tv), 0, 1)], -1) * 255).astype(np.uint8), 'HSV').convert('RGB')).astype(np.float32) / 255
    p = (np.asarray(pm).astype(np.float32) / 255)[..., None]
    rgb = a[..., :3] * (1 - p) + new * p
    return Image.fromarray(np.dstack([rgb, a[..., 3]]).__mul__(255).clip(0, 255).astype(np.uint8), 'RGBA')


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    cols = [(214, 40, 40), (30, 91, 216), (255, 122, 26), (20, 20, 24), (240, 240, 240)]
    cell = 150
    prev = Image.new('RGB', (cell * 4 * len(cols) // 2 + cell * 2, cell * len(SHEETS)), (233, 237, 242))
    for row, (kind, spec) in enumerate(SHEETS.items()):
        views = build(kind, *spec)
        for j, col in enumerate([cols[0], cols[1]] if spec[3] is not None else [None]):
            for i, (im, pm) in enumerate(views):
                t = recolor(im, pm, col) if col else im
                t.thumbnail((cell - 10, cell - 10), Image.LANCZOS)
                prev.paste(t, (j * cell * 4 + i * cell + (cell - t.width) // 2, row * cell + (cell - t.height) // 2), t)
        print(kind, [v[0].size for v in views])
    prev.save(os.path.join(ROOT, 'preview.png'))
