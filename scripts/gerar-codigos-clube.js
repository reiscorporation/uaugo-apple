// Códigos de ATIVAÇÃO de clube (só a HelpAITech gera).
//
// Cada código transforma UMA pessoa em ADMINISTRADORA de um clube no app
// (Clube → "Sou administrador do clube" → Ativar). Depois de usado, não vale
// mais. Um clube pode ter vários administradores: gere um código para cada.
// Os códigos ficam em Firestore → clubActivations (o app não lê).
//
// Uso (na raiz do projeto, com o gcloud logado na conta da HelpAITech):
//   node scripts/gerar-codigos-clube.js --clube K7M2QX9P "João (diretoria)"   # clube já cadastrado
//   node scripts/gerar-codigos-clube.js 1 "Clube novo - Fulano"               # pessoa cria um clube novo
//   node scripts/gerar-codigos-clube.js --listar
//
// IDs dos clubes cadastrados: node scripts/criar-clubes.js --listar
// O texto entre aspas é só uma anotação para vocês saberem para quem foi.

const { execSync } = require("child_process");
const crypto = require("crypto");

const PROJECT = "helpaitechcomboio";
const BASE = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;
const ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

const token = execSync("gcloud auth print-access-token", { encoding: "utf8", shell: true }).trim();
const headers = { Authorization: `Bearer ${token}`, "Content-Type": "application/json" };

const randomCode = (n) => Array.from(crypto.randomBytes(n), (b) => ALPHABET[b % ALPHABET.length]).join("");
const show = (c) => `${c.slice(0, 4)}-${c.slice(4, 8)}-${c.slice(8)}`;

/** Nome do clube [id] (ou null se não existir). */
async function clubName(id) {
  const r = await fetch(`${BASE}/clubs/${id}`, { headers });
  if (!r.ok) return null;
  return (await r.json()).fields?.name?.stringValue || id;
}

async function create(code, note, clubId) {
  const fields = {
    status: { stringValue: "available" },
    note: { stringValue: note },
    createdAt: { timestampValue: new Date().toISOString() },
  };
  if (clubId) fields.clubId = { stringValue: clubId };
  // currentDocument.exists=false: nunca sobrescreve um código existente.
  const res = await fetch(`${BASE}/clubActivations/${code}?currentDocument.exists=false`, {
    method: "PATCH", headers, body: JSON.stringify({ fields }),
  });
  return res.ok;
}

async function list() {
  let pageToken = "";
  const rows = [];
  do {
    const r = await (await fetch(`${BASE}/clubActivations?pageSize=300${pageToken ? `&pageToken=${pageToken}` : ""}`, { headers })).json();
    for (const d of r.documents || []) {
      const f = d.fields || {};
      rows.push({
        codigo: show(d.name.split("/").pop()),
        situacao: f.status?.stringValue === "used" ? "USADO" : "disponível",
        anotacao: f.note?.stringValue || "",
        clube: f.clubName?.stringValue || f.clubId?.stringValue || "(clube novo)",
      });
    }
    pageToken = r.nextPageToken || "";
  } while (pageToken);
  console.table(rows);
}

(async () => {
  const args = process.argv.slice(2);
  if (args[0] === "--listar") return list();

  let clubId = "";
  let n = 1;
  let note = "";
  if (args[0] === "--clube") {
    clubId = (args[1] || "").toUpperCase();
    note = (args[2] || "").slice(0, 200);
  } else {
    n = parseInt(args[0], 10);
    note = (args[1] || "").slice(0, 200);
  }
  if (!(n >= 1 && n <= 50) || !note || (args[0] === "--clube" && !clubId)) {
    console.log('Uso: node scripts/gerar-codigos-clube.js --clube <ID> "nome do administrador"');
    console.log('     node scripts/gerar-codigos-clube.js <quantidade 1-50> "anotação" (clube novo)');
    console.log("     node scripts/gerar-codigos-clube.js --listar");
    process.exit(1);
  }
  let label = "clube novo (a pessoa informa o nome)";
  if (clubId) {
    const name = await clubName(clubId);
    if (!name) {
      console.log(`Clube ${clubId} não encontrado. Veja os IDs com: node scripts/criar-clubes.js --listar`);
      process.exit(1);
    }
    label = `${name} (${clubId})`;
  }
  const made = [];
  while (made.length < n) {
    const code = randomCode(12);
    if (await create(code, note, clubId)) made.push(show(code));
  }
  console.log(`\nCódigo(s) de ativação — ${label} — "${note}":\n`);
  made.forEach((c) => console.log(`  ${c}`));
  console.log("\nEnvie cada código a UMA pessoa. No app: Clube → \"Sou administrador do clube\"");
  console.log("→ digite o código → Ativar. Cada código vale uma vez.\n");
})().catch((e) => { console.error(e.message); process.exit(1); });
