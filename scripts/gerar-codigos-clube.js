// Códigos de ATIVAÇÃO de clube (só a HelpAITech gera).
//
// Cada código permite que UM presidente cadastre UM clube no app
// (Clube → "Sou presidente: cadastrar o clube"). Depois de usado, não
// vale mais. Os códigos ficam em Firestore → clubActivations (o app não lê).
//
// Uso (na raiz do projeto, com o gcloud logado na conta da HelpAITech):
//   node scripts/gerar-codigos-clube.js 1 "Clube Lobos da Estrada - pres. João"
//   node scripts/gerar-codigos-clube.js 5 "Lote evento Franca"
//   node scripts/gerar-codigos-clube.js --listar
//
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

async function create(code, note) {
  // currentDocument.exists=false: nunca sobrescreve um código existente.
  const res = await fetch(`${BASE}/clubActivations/${code}?currentDocument.exists=false`, {
    method: "PATCH",
    headers,
    body: JSON.stringify({
      fields: {
        status: { stringValue: "available" },
        note: { stringValue: note },
        createdAt: { timestampValue: new Date().toISOString() },
      },
    }),
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
        clube: f.clubName?.stringValue || "",
      });
    }
    pageToken = r.nextPageToken || "";
  } while (pageToken);
  console.table(rows);
}

(async () => {
  if (process.argv[2] === "--listar") return list();
  const n = parseInt(process.argv[2], 10);
  const note = (process.argv[3] || "").slice(0, 200);
  if (!(n >= 1 && n <= 50) || !note) {
    console.log('Uso: node scripts/gerar-codigos-clube.js <quantidade 1-50> "anotação (para quem é)"');
    console.log("     node scripts/gerar-codigos-clube.js --listar");
    process.exit(1);
  }
  const made = [];
  while (made.length < n) {
    const code = randomCode(12);
    if (await create(code, note)) made.push(show(code));
  }
  console.log(`\n${made.length} código(s) de ativação — "${note}":\n`);
  made.forEach((c) => console.log(`  ${c}`));
  console.log("\nEnvie cada código a UM presidente. Ele cadastra o clube em Clube →");
  console.log('"Sou presidente: cadastrar o clube". Cada código vale uma vez.\n');
})().catch((e) => { console.error(e.message); process.exit(1); });
