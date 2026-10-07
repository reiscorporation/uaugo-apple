// Pré-cadastra clubes no banco (só a HelpAITech roda).
//
// Os clubes ficam com status "reserved" e SEM administradores: são
// invisíveis no app (só membros enxergam um clube). Depois, para cada pessoa
// que vai administrar um clube, gere um código vinculado a ele:
//   node scripts/gerar-codigos-clube.js --clube <ID> "Fulano (administrador)"
//
// Uso (na raiz do projeto, com o gcloud logado na conta da HelpAITech):
//   node scripts/criar-clubes.js                      # cria os de scripts/clubes-iniciais.json
//   node scripts/criar-clubes.js "Jipeiros do Vale" MG # cria um clube avulso
//   node scripts/criar-clubes.js --listar             # todos os clubes e administradores
//
// Não cria de novo um clube que já existe com o mesmo nome.

const { execSync } = require("child_process");
const crypto = require("crypto");
const path = require("path");

const PROJECT = "helpaitechcomboio";
const ROOT = `projects/${PROJECT}/databases/(default)/documents`;
const BASE = `https://firestore.googleapis.com/v1/${ROOT}`;
const ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

const token = execSync("gcloud auth print-access-token", { encoding: "utf8", shell: true }).trim();
const headers = { Authorization: `Bearer ${token}`, "Content-Type": "application/json" };
const randomCode = (n) => Array.from(crypto.randomBytes(n), (b) => ALPHABET[b % ALPHABET.length]).join("");

/** Todos os clubes: [{ id, nome, status, admins }]. */
async function allClubs() {
  const out = [];
  let pageToken = "";
  do {
    const r = await (await fetch(`${BASE}/clubs?pageSize=300${pageToken ? `&pageToken=${pageToken}` : ""}`, { headers })).json();
    for (const d of r.documents || []) {
      const f = d.fields || {};
      out.push({
        id: d.name.split("/").pop(),
        nome: f.name?.stringValue || "",
        uf: f.uf?.stringValue || "",
        status: f.status?.stringValue || "active",
        administradores: (f.admins?.arrayValue?.values || []).length ||
          (f.presidentId?.stringValue ? 1 : 0),
      });
    }
    pageToken = r.nextPageToken || "";
  } while (pageToken);
  return out;
}

const key = (s) => s.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().replace(/[^a-z0-9]/g, "");

async function create(nome, uf) {
  for (;;) {
    const id = randomCode(8);
    const res = await fetch(`${BASE}/clubs/${id}?currentDocument.exists=false`, {
      method: "PATCH",
      headers,
      body: JSON.stringify({
        fields: {
          name: { stringValue: nome },
          uf: { stringValue: uf || "" },
          status: { stringValue: "reserved" },
          admins: { arrayValue: { values: [] } },
          origin: { stringValue: "pré-cadastro HelpAITech" },
          createdAt: { timestampValue: new Date().toISOString() },
        },
      }),
    });
    if (res.ok) return id;
    if (res.status !== 400 && res.status !== 409) throw new Error(`Erro ${res.status}: ${await res.text()}`);
  }
}

(async () => {
  if (process.argv[2] === "--listar") {
    const list = await allClubs();
    list.sort((a, b) => a.nome.localeCompare(b.nome, "pt-BR"));
    console.table(list);
    return;
  }
  const wanted = process.argv[2]
    ? [{ nome: process.argv[2].trim().slice(0, 60), uf: (process.argv[3] || "").toUpperCase().slice(0, 2) }]
    : require(path.join(__dirname, "clubes-iniciais.json")).clubes;

  const existing = new Map((await allClubs()).map((c) => [key(c.nome), c]));
  const rows = [];
  for (const c of wanted) {
    const found = existing.get(key(c.nome));
    if (found) {
      rows.push({ id: found.id, nome: found.nome, situacao: "já existia" });
      continue;
    }
    const id = await create(c.nome, c.uf);
    existing.set(key(c.nome), { id, nome: c.nome });
    rows.push({ id, nome: c.nome, situacao: "criado (reservado)" });
  }
  console.table(rows);
  console.log('\nPara um administrador: node scripts/gerar-codigos-clube.js --clube <ID> "Nome do administrador"\n');
})().catch((e) => { console.error(e.message); process.exit(1); });
