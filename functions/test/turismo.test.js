// "Na rota": atrações, postos famosos e planilha da ANP.
//   node --test functions/test/turismo.test.js
const test = require("node:test");
const assert = require("node:assert");
const zlib = require("zlib");
const { compact, redeOf, parseAnp, readXlsx } = require("../turismo");

test("atrações e postos: tipos, famosos marcados, comuns sem marca saem", () => {
  const c = compact([
    { type: "node", lat: -21.17, lon: -47.85, tags: { tourism: "museum", name: "Museu do Café", wikidata: "Q1", wikipedia: "pt:Museu do Café" } },
    { type: "way", center: { lat: -21.2, lon: -47.9 }, tags: { natural: "waterfall", name: "Cachoeira X" } },
    { type: "node", lat: -21.3, lon: -47.7, tags: { historic: "memorial", name: "Sem wikidata" } },
    { type: "node", lat: -21.31, lon: -47.71, tags: { tourism: "attraction" } }, // sem nome
    { type: "node", lat: -21.4, lon: -47.6, tags: { amenity: "fuel", name: "Graal Tropical", brand: "Petrobras" } },
    { type: "node", lat: -21.5, lon: -47.5, tags: { amenity: "fuel", brand: "Shell", "addr:street": "Rod. Anhanguera" } },
    { type: "node", lat: -21.6, lon: -47.4, tags: { amenity: "fuel" } }, // sem nome nem bandeira
  ]);
  assert.deepStrictEqual(c.a.map((x) => [x[2], x[3]]), [["waterfall", "Cachoeira X"], ["museum", "Museu do Café"]]);
  assert.strictEqual(c.a[1][4].w, "pt:Museu do Café");
  assert.deepStrictEqual(c.f.map((x) => [x[2], x[3]]), [["", "Shell"], ["Graal", "Graal Tropical"]]);
  assert.strictEqual(c.f[0][4].r, "Rod. Anhanguera");
});

test("redes famosas", () => {
  assert.strictEqual(redeOf({ name: "Petrograal Rio Claro" }), "Graal");
  assert.strictEqual(redeOf({ name: "Posto Frango Assado Km 72" }), "Frango Assado");
  assert.strictEqual(redeOf({ name: "Posto Shell", brand: "Shell" }), null);
  assert.strictEqual(redeOf({ name: "RodOil Centro" }), null);
});

/** Monta um .xlsx mínimo (zip "stored") para o leitor. */
function xlsx(rows) {
  const strings = [];
  const si = (v) => { let i = strings.indexOf(v); if (i < 0) { i = strings.length; strings.push(v); } return i; };
  const L = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
  const sheet = "<worksheet><sheetData>" + rows.map((r, ri) => `<row r="${ri + 1}">` + r.map((v, ci) =>
    typeof v === "number" ? `<c r="${L[ci]}${ri + 1}"><v>${v}</v></c>` : `<c r="${L[ci]}${ri + 1}" t="s"><v>${si(v)}</v></c>`).join("") + "</row>").join("") + "</sheetData></worksheet>";
  const ss = "<sst>" + strings.map((s) => `<si><t>${s.replace(/&/g, "&amp;")}</t></si>`).join("") + "</sst>";
  const files = [["xl/sharedStrings.xml", ss], ["xl/worksheets/sheet1.xml", sheet]];
  const parts = [], central = [];
  let off = 0;
  for (const [name, txt] of files) {
    const data = zlib.deflateRawSync(Buffer.from(txt));
    const n = Buffer.from(name);
    const lh = Buffer.alloc(30); lh.writeUInt32LE(0x04034b50, 0); lh.writeUInt16LE(8, 8);
    lh.writeUInt32LE(data.length, 18); lh.writeUInt16LE(n.length, 26);
    const ch = Buffer.alloc(46); ch.writeUInt32LE(0x02014b50, 0); ch.writeUInt16LE(8, 10);
    ch.writeUInt32LE(data.length, 20); ch.writeUInt16LE(n.length, 28); ch.writeUInt32LE(off, 42);
    parts.push(lh, n, data); central.push(ch, n);
    off += 30 + n.length + data.length;
  }
  const cd = Buffer.concat(central);
  const end = Buffer.alloc(22); end.writeUInt32LE(0x06054b50, 0); end.writeUInt16LE(files.length, 10);
  end.writeUInt32LE(cd.length, 12); end.writeUInt32LE(off, 16);
  return Buffer.concat([...parts, cd, end]);
}

test("planilha da ANP: agrupa produtos por posto e separa por estado", () => {
  const head = ["CNPJ", "RAZÃO", "FANTASIA", "ENDEREÇO", "NÚMERO", "COMPLEMENTO", "BAIRRO", "CEP",
    "MUNICÍPIO", "ESTADO", "BANDEIRA", "PRODUTO", "UNIDADE DE MEDIDA", "PREÇO DE REVENDA", "DATA DA COLETA"];
  const row = (cnpj, prod, preco, uf) => [cnpj, "AUTO POSTO X LTDA", "POSTO X", "RODOVIA SP-330", "KM 300", "",
    "CENTRO", "14140000", "CRAVINHOS", uf, "IPIRANGA", prod, "R$ / litro", preco, 46325];
  const rows = readXlsx(xlsx([
    ["PERÍODO: 25/10/2026 A 31/10/2026"],
    head,
    row("1", "GASOLINA COMUM", 6.19, "SAO PAULO"),
    row("1", "ETANOL", 4.09, "SAO PAULO"),
    row("1", "GLP", 110, "SAO PAULO"),
    row("2", "DIESEL S10", 6.5, "MINAS GERAIS"),
  ]));
  const { semana, byUf } = parseAnp(rows);
  assert.strictEqual(semana, "25/10/2026 A 31/10/2026");
  assert.strictEqual(byUf.SP.length, 1);
  assert.deepStrictEqual(byUf.SP[0][6], { g: 6.19, e: 4.09 });
  assert.strictEqual(byUf.SP[0][4], "CRAVINHOS");
  assert.strictEqual(byUf.SP[0][7], "2026-10-30");
  assert.deepStrictEqual(byUf.MG[0][6], { d10: 6.5 });
});
