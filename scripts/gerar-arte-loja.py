"""Gera a arte da Google Play a partir do ícone do app (assets/branding).

  python scripts/gerar-arte-loja.py

Saída em loja/:
  - icone-512.png        ícone da loja (512x512, quadrado cheio: a Play arredonda)
  - destaque-1024x500.png imagem de destaque (feature graphic)
"""
import os
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "loja")
os.makedirs(OUT, exist_ok=True)
icon = Image.open(os.path.join(ROOT, "assets", "branding", "comboio_icon_square.png")).convert("RGBA")

# 1) Ícone 512x512, sem transparência (a Play exige PNG 32 bits; fundo laranja).
bg = Image.new("RGBA", icon.size, (15, 27, 45, 255))
bg.alpha_composite(icon)
bg.resize((512, 512), Image.LANCZOS).save(os.path.join(OUT, "icone-512.png"))

# 2) Destaque 1024x500: degradê laranja, ícone à esquerda, nome e frase.
W, H = 1024, 500
g = Image.new("RGB", (W, H))
d = ImageDraw.Draw(g)
top, bottom = (22, 37, 61), (12, 22, 38)  # azul-marinho da marca
for y in range(H):
    t = y / (H - 1)
    d.line([(0, y), (W, y)], fill=tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
# Mapa-múndi pontilhado ao fundo (o mesmo da tela inicial).
mapa = Image.open(os.path.join(ROOT, "assets", "branding", "mapa_pontilhado.png")).convert("RGBA")
mapa = mapa.resize((W, int(mapa.height * W / mapa.width)), Image.LANCZOS)
g = g.convert("RGBA")
g.alpha_composite(mapa, (0, (H - mapa.height) // 2))
g = g.convert("RGB")
d = ImageDraw.Draw(g)
logo = icon.resize((340, 340), Image.LANCZOS)
mask = Image.new("L", logo.size, 0)
ImageDraw.Draw(mask).rounded_rectangle([0, 0, 339, 339], radius=70, fill=255)
d.rounded_rectangle([66, 76, 413, 423], radius=74, outline=(58, 85, 120), width=3)  # contorno: destaca o ícone do fundo
g.paste(logo, (70, 80), Image.composite(logo.split()[3], mask, mask))

fonts = r"C:\Windows\Fonts"
title = ImageFont.truetype(os.path.join(fonts, "segoeuib.ttf"), 112)
sub = ImageFont.truetype(os.path.join(fonts, "segoeui.ttf"), 38)
dark = (234, 241, 250)  # texto claro sobre o marinho
muted = (169, 187, 209)
d.text((450, 120), "UauGo", font=title, fill=dark)
d.text((455, 292), "Em grupo ou sozinho,", font=sub, fill=muted)
d.text((455, 340), "qualquer caminho é UauGo.", font=sub, fill=muted)
d.rounded_rectangle([458, 268, 578, 276], radius=4, fill=(255, 122, 26))  # traço laranja
g.save(os.path.join(OUT, "destaque-1024x500.png"))
print("ok:", os.listdir(OUT))
