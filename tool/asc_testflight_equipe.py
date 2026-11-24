"""Cria o grupo interno "Equipe" do TestFlight e coloca nele os usuários da
conta App Store Connect (sem precisar entrar no site). Roda no Codemagic
(workflow ios-testadores), com a chave da integração "UauGo ASC".
"""
import base64
import os
import re
import time

import jwt
import requests

BUNDLE = "helpaitech.comboio"
GRUPO = "Equipe"
API = "https://api.appstoreconnect.apple.com/v1"


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


TOKEN = jwt.encode(
    {"iss": os.environ["APP_STORE_CONNECT_ISSUER_ID"],
     "iat": int(time.time()), "exp": int(time.time()) + 1200,
     "aud": "appstoreconnect-v1"},
    chave(), algorithm="ES256",
    headers={"kid": os.environ["APP_STORE_CONNECT_KEY_IDENTIFIER"]})
H = {"Authorization": "Bearer " + TOKEN}


def get(path, **params):
    r = requests.get(API + path, headers=H, params=params)
    r.raise_for_status()
    return r.json()["data"]


def post(path, data):
    r = requests.post(API + path, headers=H, json={"data": data})
    print("POST", path, r.status_code, r.text[:300] if r.status_code >= 300 else "")
    return r


def mascara(email):
    u, _, d = email.partition("@")
    return u[:2] + "***@" + d


app = get("/apps", **{"filter[bundleId]": BUNDLE})[0]
APP = app["id"]
print("App:", app["attributes"]["name"], APP)

for b in get("/builds", **{"filter[app]": APP, "sort": "-uploadedDate", "limit": 5}):
    a = b["attributes"]
    print("Build", a["version"], a["processingState"],
          "criptografia:", a.get("usesNonExemptEncryption"))

grupo = next((g for g in get(f"/apps/{APP}/betaGroups")
              if g["attributes"]["name"] == GRUPO), None)
if grupo is None:
    r = post("/betaGroups", {
        "type": "betaGroups",
        "attributes": {"name": GRUPO, "isInternalGroup": True,
                       "hasAccessToAllBuilds": True},
        "relationships": {"app": {"data": {"type": "apps", "id": APP}}}})
    r.raise_for_status()
    grupo = r.json()["data"]
GID = grupo["id"]
print("Grupo:", GRUPO, GID, "interno:", grupo["attributes"].get("isInternalGroup"))

for u in get("/users", limit=50):
    a = u["attributes"]
    email = a["username"]
    print("Usuário:", mascara(email), a.get("roles"))
    post("/betaTesters", {
        "type": "betaTesters",
        "attributes": {"email": email, "firstName": a.get("firstName") or "",
                       "lastName": a.get("lastName") or ""},
        "relationships": {"betaGroups": {"data": [{"type": "betaGroups", "id": GID}]}}})

print("Testadores no grupo:", len(get(f"/betaGroups/{GID}/betaTesters", limit=50)))
