"""Gera o ícone do UauGo (conceito D1: trilha do grupo seguindo a seta do líder).

  python scripts/gerar-icone.py      (precisa do Pillow)

Desenha em alta resolução e reduz (bordas suaves). Saída:
  assets/branding/comboio_icon_square.png  1024, quadrado cheio (ícone legado/iOS)
  assets/branding/comboio_icon_fg.png      1024, só o desenho com fundo transparente
                                           (ícone adaptável do Android; o fundo é a cor
                                           adaptive_icon_background do pubspec)
  assets/branding/comboio_logo.png         512, cantos arredondados (logo dentro do app)
  assets/branding/uaugo_marca.png          512, só a trilha e a seta (fundo transparente)
  assets/branding/uaugo_icone.svg          desenho-mestre (referência)
  loja/icone-512.png                       ícone da Google Play
Depois: dart run flutter_launcher_icons
"""
import math
import os
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NAVY = (15, 27, 45, 255)      # #0F1B2D
ORANGE = (255, 122, 26, 255)  # #FF7A1A

# Desenho no quadro 0..100 (o mesmo do rascunho D1).
P0, P1, P2, P3 = (24, 82), (24, 58), (76, 64), (76, 42)
ARROW = [(76, 14), (89, 40), (76, 34), (63, 40)]
DOT_D, DOT_STEP = 8.0, 14.0


def bezier(t):
    u = 1 - t
    return (u**3 * P0[0] + 3 * u * u * t * P1[0] + 3 * u * t * t * P2[0] + t**3 * P3[0],
            u**3 * P0[1] + 3 * u * u * t * P1[1] + 3 * u * t * t * P2[1] + t**3 * P3[1])


def dots():
    """Pontos igualmente espaçados ao longo da curva."""
    pts = [bezier(i / 2000) for i in range(2001)]
    out, acc, last = [pts[0]], 0.0, pts[0]
    for p in pts[1:]:
        acc += math.dist(p, last)
        last = p
        if acc >= DOT_STEP:
            out.append(p)
            acc = 0.0
    return out


def draw(size, scale=1.0, background=True, radius=0.0):
    """Desenha o ícone em [size] px. [scale] encolhe o desenho (zona segura)."""
    ss = 4  # super-amostragem
    S = size * ss
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    if background:
        if radius:
            d.rounded_rectangle([0, 0, S - 1, S - 1], radius=int(S * radius), fill=NAVY)
        else:
            d.rectangle([0, 0, S, S], fill=NAVY)
    k = S / 100 * scale
    off = S * (1 - scale) / 2
    tx = lambda x, y: (off + x * k, off + y * k)
    r = DOT_D / 2 * k
    for x, y in dots():
        cx, cy = tx(x, y)
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=ORANGE)
    d.polygon([tx(x, y) for x, y in ARROW], fill=ORANGE)
    return img.resize((size, size), Image.LANCZOS)


def svg():
    circles = "".join(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="4" fill="#FF7A1A"/>' for x, y in dots())
    arrow = " ".join(f"{x},{y}" for x, y in ARROW)
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">'
            f'<rect width="100" height="100" rx="22" fill="#0F1B2D"/>{circles}'
            f'<polygon points="{arrow}" fill="#FF7A1A"/></svg>\n')


brand = os.path.join(ROOT, "assets", "branding")
draw(1024).convert("RGB").save(os.path.join(brand, "comboio_icon_square.png"))
# Ícone adaptável: o Android recorta em círculo/gota; o desenho fica na zona
# segura central (~60%).
draw(1024, scale=0.60, background=False).save(os.path.join(brand, "comboio_icon_fg.png"))
draw(512, radius=0.22).save(os.path.join(brand, "comboio_logo.png"))
# Só a marca (trilha + seta), sem o quadrado: vai sobre o mapa-múndi da tela inicial.
draw(512, background=False).save(os.path.join(brand, "uaugo_marca.png"))
with open(os.path.join(brand, "uaugo_icone.svg"), "w", encoding="utf-8") as f:
    f.write(svg())
os.makedirs(os.path.join(ROOT, "loja"), exist_ok=True)
draw(512).convert("RGB").save(os.path.join(ROOT, "loja", "icone-512.png"))
print("ícones gerados")
