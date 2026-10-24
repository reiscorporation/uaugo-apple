/**
 * Envia o pacote (.aab) para o TESTE INTERNO do Google Play, sem abrir o
 * Console. Usa a conta de serviço "uaugo-publicacao" (convidada no Play
 * Console só com "Lançar em faixas de teste"). A produção continua sendo
 * feita à mão no Console.
 *
 *   node scripts/publicar-teste-interno.js <arquivo.aab> "Notas da versão"
 *
 * A chave da conta de serviço fica FORA do projeto (nunca no Git):
 *   %USERPROFILE%\.uaugo\play-publicacao.json   (ou variável PLAY_KEY)
 */
const fs = require("fs");
const os = require("os");
const path = require("path");
const { GoogleAuth } = require(path.join(__dirname, "..", "functions", "node_modules", "google-auth-library"));

const PACKAGE = "helpaitech.comboio";
// Faixa: "internal" (teste interno, padrão) ou outra via PLAY_TRACK (ex.: "alpha" = teste fechado).
const TRACK = process.env.PLAY_TRACK || "internal";
const API = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${PACKAGE}`;
const UPLOAD = `https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/${PACKAGE}`;

async function main() {
  const [aab, notes] = process.argv.slice(2);
  if (!aab || !fs.existsSync(aab)) throw new Error("Informe o arquivo .aab: node scripts/publicar-teste-interno.js <arquivo.aab> \"notas\"");
  const keyFile = process.env.PLAY_KEY || path.join(os.homedir(), ".uaugo", "play-publicacao.json");
  if (!fs.existsSync(keyFile)) throw new Error(`Chave não encontrada: ${keyFile}`);

  const auth = new GoogleAuth({ keyFile, scopes: ["https://www.googleapis.com/auth/androidpublisher"] });
  const client = await auth.getClient();
  const token = (await client.getAccessToken()).token;
  const call = async (method, url, body, headers = {}) => {
    const res = await fetch(url, {
      method,
      headers: { Authorization: `Bearer ${token}`, ...headers },
      body,
    });
    const text = await res.text();
    if (!res.ok) throw new Error(`${method} ${url.replace(API, "").replace(UPLOAD, "")} -> ${res.status}: ${text.slice(0, 400)}`);
    return text ? JSON.parse(text) : {};
  };

  const edit = await call("POST", `${API}/edits`, "{}", { "content-type": "application/json" });
  console.log("Edição aberta:", edit.id);
  const bundle = await call(
    "POST",
    `${UPLOAD}/edits/${edit.id}/bundles?uploadType=media`,
    fs.readFileSync(aab),
    { "content-type": "application/octet-stream" },
  );
  console.log("Pacote enviado: código de versão", bundle.versionCode);
  await call(
    "PUT",
    `${API}/edits/${edit.id}/tracks/${TRACK}`,
    JSON.stringify({
      track: TRACK,
      releases: [{
        versionCodes: [String(bundle.versionCode)],
        status: process.env.PLAY_STATUS || "completed", // "draft" no 1º lançamento de uma faixa nova
        releaseNotes: notes ? [{ language: "pt-BR", text: notes.slice(0, 500) }] : [],
      }],
    }),
    { "content-type": "application/json" },
  );
  await call("POST", `${API}/edits/${edit.id}:commit`, undefined);
  console.log(`Publicado na faixa ${TRACK} (versão ${bundle.versionCode}).`);
}

main().catch((e) => {
  console.error("Erro:", e.message);
  process.exit(1);
});
