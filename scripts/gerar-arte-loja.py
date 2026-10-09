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
bg = Image.new("RGBA", icon.size, (245, 124, 0, 255))
bg.alpha_composite(icon)
bg.resize((512, 512), Image.LANCZOS).save(os.path.join(OUT, "icone-512.png"))

# 2) Destaque 1024x500: degradê laranja, ícone à esquerda, nome e frase.
W, H = 1024, 500
g = Image.new("RGB", (W, H))
d = ImageDraw.Draw(g)
top, bottom = (255, 167, 38), (230, 81, 0)
for y in range(H):
    t = y / (H - 1)
    d.line([(0, y), (W, y)], fill=tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
logo = icon.resize((340, 340), Image.LANCZOS)
mask = Image.new("L", logo.size, 0)
ImageDraw.Draw(mask).rounded_rectangle([0, 0, 339, 339], radius=70, fill=255)
g.paste(logo, (70, 80), Image.composite(logo.split()[3], mask, mask))

fonts = r"C:\Windows\Fonts"
title = ImageFont.truetype(os.path.join(fonts, "segoeuib.ttf"), 112)
sub = ImageFont.truetype(os.path.join(fonts, "segoeui.ttf"), 38)
dark = (40, 24, 10)
d.text((450, 120), "UauGo", font=title, fill=dark)
d.text((455, 270), "Viagens em grupo,", font=sub, fill=dark)
d.text((455, 318), "de moto ou de carro", font=sub, fill=dark)
g.save(os.path.join(OUT, "destaque-1024x500.png"))
print("ok:", os.listdir(OUT))
