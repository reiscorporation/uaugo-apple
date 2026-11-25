"""Baixa da Apple o perfil "UauGo App Store" atual e instala no Mac do
Codemagic, no lugar da cópia guardada no Codemagic (que fica velha quando
uma capacidade nova, como App Attest, é ligada no identificador).
"""
import base64
import glob
import os
import plistlib
import re
import time

import jwt
import requests

NOME = "UauGo App Store"
PASTA = os.path.expanduser("~/Library/MobileDevice/Provisioning Profiles")


def chave():
    key = os.environ["APP_STORE_CONNECT_PRIVATE_KEY"].strip()
    if key.startswith("@file:"):
        key = open(os.path.expanduser(key[6:])).read()
    elif key.startswith("@env:"):
        key = os.environ[key[5:]]
    key = key.replace("\\n", "\n").strip()
    if "BEGIN" not in key:
        try:
            key = base64.b64decode(key).decode()
        except Exception:
            pass
    body = re.sub(r"\s+", "", re.sub(r"-----[A-Z ]+-----", "", key))
    return ("-----BEGIN PRIVATE KEY-----\n"
            + "\n".join(body[i:i + 64] for i in range(0, len(body), 64))
            + "\n-----END PRIVATE KEY-----\n")


def plist_de(dados):
    ini, fim = dados.find(b"<?xml"), dados.find(b"</plist>")
    return plistlib.loads(dados[ini:fim + 8])


tok = jwt.encode(
    {"iss": os.environ["APP_STORE_CONNECT_ISSUER_ID"],
     "iat": int(time.time()), "exp": int(time.time()) + 600,
     "aud": "appstoreconnect-v1"},
    chave(), algorithm="ES256",
    headers={"kid": os.environ["APP_STORE_CONNECT_KEY_IDENTIFIER"]})
r = requests.get("https://api.appstoreconnect.apple.com/v1/profiles",
                 headers={"Authorization": "Bearer " + tok},
                 params={"filter[name]": NOME, "filter[profileState]": "ACTIVE"})
r.raise_for_status()
perfis = r.json()["data"]
assert perfis, "perfil não encontrado na Apple"
dados = base64.b64decode(perfis[0]["attributes"]["profileContent"])
novo = plist_de(dados)
ent = novo["Entitlements"]
print("Perfil:", novo["Name"], novo["UUID"], "vence", novo["ExpirationDate"])
print("App Attest no perfil:",
      "com.apple.developer.devicecheck.appattest-environment" in ent)

os.makedirs(PASTA, exist_ok=True)
for f in glob.glob(os.path.join(PASTA, "*.mobileprovision")):
    try:
        if plist_de(open(f, "rb").read()).get("Name") == NOME:
            os.remove(f)
            print("Removido perfil velho:", os.path.basename(f))
    except Exception:
        pass
with open(os.path.join(PASTA, novo["UUID"] + ".mobileprovision"), "wb") as f:
    f.write(dados)
print("Instalado.")
