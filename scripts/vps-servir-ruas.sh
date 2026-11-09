#!/bin/sh
# Uma vez só, na VPS: publica a pasta /opt/helpaitech/ruas em
# https://motor.200-141-16-177.sslip.io/ruas/ (só leitura, arquivos .json.gz
# das ruas do minimapa do 3D). O resto do motor continua exigindo a chave.
# Rodar no PC:  ssh -i ~/.ssh/hostinger_vps root@200.141.16.177 'sh -s' < scripts/vps-servir-ruas.sh
set -e
cd /opt/helpaitech/proxy
mkdir -p /opt/helpaitech/ruas
cp docker-compose.yml docker-compose.yml.bak-antes-ruas
cp sites/motor.caddy /opt/helpaitech/motor.caddy.bak-antes-ruas
python3 - <<'EOF'
p = "docker-compose.yml"
s = open(p).read()
a = "      - ./sites:/etc/caddy/sites:ro\n"
if "/srv/ruas" not in s:
    assert s.count(a) == 1
    s = s.replace(a, a + "      # Ruas do minimapa do UauGo (geradas no PC do Ricardo)\n      - /opt/helpaitech/ruas:/srv/ruas:ro\n")
    open(p, "w").write(s)
p = "sites/motor.caddy"
s = open(p).read()
a = "\tencode gzip\n"
if "/srv/ruas" not in s:
    assert s.count(a) == 1
    s = s.replace(a, a + "\t# Ruas do minimapa do 3D (públicas, só leitura)\n\thandle_path /ruas/* {\n\t\troot * /srv/ruas\n\t\theader Cache-Control \"public, max-age=604800\"\n\t\tfile_server\n\t}\n")
    open(p, "w").write(s)
EOF
docker compose up -d caddy
sleep 3
docker exec caddy caddy validate --config /etc/caddy/Caddyfile
echo "Pronto: /ruas/ publicado"
