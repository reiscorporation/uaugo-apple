"""Gera assets/sounds/glug.wav: o "glug" do recálculo de rota (duas bolhas).

Uso:  python -I tool/gerar_glug.py   (na raiz do projeto)
"""
import math
import os
import struct
import wave

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'assets', 'sounds', 'glug.wav')


def bolha(f0, f1, dur, vol):
    """Uma bolha: tom que sobe de f0 a f1 Hz e some rápido."""
    n = int(SR * dur)
    fase, out = 0.0, []
    for i in range(n):
        t = i / n
        f = f0 * (f1 / f0) ** (t ** 0.6)
        fase += 2 * math.pi * f / SR
        env = min(1.0, i / (SR * 0.004)) * (1 - t) ** 2.2
        out.append(vol * env * (math.sin(fase) + 0.25 * math.sin(2 * fase)))
    return out


som = bolha(260, 820, 0.11, 0.8) + [0.0] * int(SR * 0.035) + bolha(340, 1050, 0.12, 0.85)
som += [0.0] * int(SR * 0.05)
with wave.open(OUT, 'wb') as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes(b''.join(struct.pack('<h', int(max(-1, min(1, s)) * 30000)) for s in som))
print('ok', len(som) / SR, 's')
