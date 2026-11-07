/**
 * "Na rota": atrações turísticas e postos famosos entre motociclistas, por
 * estado, a partir do OpenStreetMap (ODbL) via Overpass. Preços de
 * combustível por posto da pesquisa semanal da ANP (dados abertos).
 *
 * Saída, por estado:
 *   public/turismo/<UF>.json.gz = { v, uf, a, f }
 *     a = atrações: [lat*1e5, lng*1e5, tipo, nome, extras]
 *         tipo: museum, attraction, viewpoint, zoo, theme_park, gallery,
 *               aquarium, waterfall, cave, beach, peak, historic, park
 *         extras (só o que existir): w = artigo da Wikipédia ("pt:Título"),
 *               q = Wikidata (Q123), i = foto (URL ou "File:..."),
 *               s = site, h = horário, d = descrição, c = cidade
 *     f = postos: [lat*1e5, lng*1e5, rede, nome, extras]
 *         rede = parada famosa entre motociclistas (Graal, Frango Assado...)
 *               ou "" para posto de bandeira comum
 *         extras: b = bandeira, r = rua, n = número, c = cidade, x = 1 se tem
 *               restaurante/lanchonete no OSM
 *   public/combustivel/<UF>.json.gz = { v, uf, semana, p }
 *     p = postos da ANP: [nome, rua, número, bairro, cidade, bandeira,
 *         { produto: preço }, data]
 */

const zlib = require("zlib");

const UFS = ["AC", "AL", "AM", "AP", "BA", "CE", "DF", "ES", "GO", "MA", "MG",
  "MS", "MT", "PA", "PB", "PE", "PI", "PR", "RJ", "RN", "RO", "RR", "RS", "SC",
  "SE", "SP", "TO"];

const OVERPASS = [
  "https://overpass-api.de/api/interpreter",
  "https://overpass.kumi.systems/api/interpreter",
];

/**
 * Redes e pontos de parada conhecidos de quem viaja de moto. O primeiro item
 * é o nome mostrado no app; o segundo, como aparece no nome/marca do OSM.
 */
const REDES = [
  ["Graal", /graal/i],
  ["Frango Assado", /frango assado/i],
  ["Rodoserv", /rodoserv/i],
  ["Sinuelo", /sinuelo/i],
  ["Buffon", /buffon/i],
  ["Arco-Íris", /arco[- ]?[íi]ris/i],
  ["Petrobras Premmia", /premmia/i],
  ["Ponto do motociclista", /moto ?(point|clube|ponto)|motociclista|bikers?\b/i],
];

function query(uf) {
  return `[out:json][timeout:900];
area["ISO3166-2"="BR-${uf}"][admin_level=4]->.a;
(
  nwr["tourism"~"^(attraction|museum|viewpoint|zoo|theme_park|gallery|aquarium)$"]["name"](area.a);
  nwr["natural"~"^(waterfall|cave_entrance|peak)$"]["name"](area.a);
  nwr["natural"="beach"]["name"](area.a);
  nwr["historic"]["name"]["wikidata"](area.a);
  nwr["leisure"~"^(park|nature_reserve)$"]["name"]["wikidata"](area.a);
  nwr["boundary"="protected_area"]["name"]["wikidata"](area.a);
  nwr["amenity"="fuel"](area.a);
);
out center tags;`;
}

async function fetchUf(uf) {
  let last;
  for (let round = 0; round < 3; round++) {
    if (round > 0) await new Promise((r) => setTimeout(r, 20000 * round));
    for (const url of OVERPASS) {
      try {
        const res = await fetch(url, {
          method: "POST",
          headers: {
            "content-type": "application/x-www-form-urlencoded",
            "user-agent": "UauGo/1.0 (app de viagens; contato HelpAITech)",
          },
          body: "data=" + encodeURIComponent(query(uf)),
          signal: AbortSignal.timeout(1000000),
        });
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        return (await res.json()).elements || [];
      } catch (e) {
        last = e;
      }
    }
  }
  throw last;
}

/** Tipo da atração (null = não é atração). */
function kindOf(t) {
  if (t.tourism && /^(attraction|museum|viewpoint|zoo|theme_park|gallery|aquarium)$/.test(t.tourism)) {
    return t.tourism;
  }
  if (t.natural === "waterfall") return "waterfall";
  if (t.natural === "cave_entrance") return "cave";
  if (t.natural === "beach") return "beach";
  if (t.natural === "peak") return t.wikidata || t.tourism ? "peak" : null;
  if (t.historic && t.wikidata) return "historic";
  if ((t.leisure || t.boundary) && t.wikidata) return "park";
  return null;
}

/** Rede famosa do posto (null = posto comum, fica de fora). */
function redeOf(t) {
  const txt = `${t.name || ""} ${t.brand || ""} ${t.operator || ""} ${t["name:pt"] || ""}`;
  for (const [nome, re] of REDES) if (re.test(txt)) return nome;
  return null;
}

/** Junta as atrações e os postos famosos de um estado. */
function compact(elements) {
  const a = [], f = [];
  const seen = new Set();
  for (const e of elements) {
    const t = e.tags || {};
    const lat = e.lat ?? e.center?.lat, lng = e.lon ?? e.center?.lon;
    if (!isFinite(lat) || !isFinite(lng)) continue;
    const name = (t["name:pt"] || t.name || "").trim();
    const p = [Math.round(lat * 1e5), Math.round(lng * 1e5)];
    if (t.amenity === "fuel") {
      // Famosos primeiro no app; os demais só se têm bandeira ou nome.
      const rede = redeOf(t) || "";
      if (!rede && !t.brand && !t.name) continue;
      const x = {};
      if (t.brand) x.b = t.brand;
      if (t["addr:street"]) x.r = t["addr:street"];
      if (t["addr:housenumber"]) x.n = t["addr:housenumber"];
      if (t["addr:city"]) x.c = t["addr:city"];
      if (/restaurant|fast_food|cafe/.test(`${t.amenity} ${t.shop || ""} ${t["fuel:services"] || ""}`) ||
        t.restaurant === "yes" || t.food === "yes") x.x = 1;
      f.push([...p, rede, name || rede || t.brand, x]);
      continue;
    }
    const kind = kindOf(t);
    if (!kind || !name) continue;
    // Mesmo lugar marcado como ponto e como área: fica um só.
    const key = `${name.toLowerCase()}|${Math.round(lat * 200)}|${Math.round(lng * 200)}`;
    if (seen.has(key)) continue;
    seen.add(key);
    const x = {};
    if (t.wikipedia) x.w = t.wikipedia;
    if (t.wikidata) x.q = t.wikidata;
    if (t.image || t.wikimedia_commons) x.i = t.image || t.wikimedia_commons;
    if (t.website || t["contact:website"]) x.s = t.website || t["contact:website"];
    if (t.opening_hours) x.h = t.opening_hours;
    if (t.description || t["description:pt"]) x.d = (t["description:pt"] || t.description).slice(0, 300);
    if (t["addr:city"]) x.c = t["addr:city"];
    a.push([...p, kind, name, x]);
  }
  a.sort((m, n) => m[0] - n[0] || m[1] - n[1]);
  f.sort((m, n) => m[0] - n[0] || m[1] - n[1]);
  const box = [Infinity, Infinity, -Infinity, -Infinity];
  for (const [la, ln] of [...a, ...f]) {
    box[0] = Math.min(box[0], la / 1e5); box[1] = Math.min(box[1], ln / 1e5);
    box[2] = Math.max(box[2], la / 1e5); box[3] = Math.max(box[3], ln / 1e5);
  }
  return { a, f, bbox: a.length || f.length ? box.map((v) => +v.toFixed(2)) : null };
}

/** Atualiza os estados mais antigos (mais de 25 dias) até acabar o tempo. */
async function buildTurismo({ previous = {}, save, budgetMs = 1500000, log = console.log }) {
  const ufs = { ...(previous.ufs || {}) };
  const start = Date.now();
  const old = 25 * 24 * 3600 * 1000;
  const due = UFS
    .filter((uf) => !ufs[uf] || Date.now() - (ufs[uf].version || 0) > old)
    .sort((x, y) => (ufs[x]?.version || 0) - (ufs[y]?.version || 0));
  let changed = 0;
  for (const uf of due) {
    if (Date.now() - start > budgetMs) break;
    try {
      const { a, f, bbox } = compact(await fetchUf(uf));
      const gz = zlib.gzipSync(JSON.stringify({ v: 1, uf, a, f }), { level: 9 });
      await save("turismo", uf, gz);
      ufs[uf] = { ...(ufs[uf] || {}), bbox, atracoes: a.length, postos: f.length, version: Date.now(), bytes: gz.length };
      changed++;
      log(`Turismo ${uf}: ${a.length} atrações, ${f.length} postos, ` +
        `${f.filter((x) => x[2]).length} famosos (${(gz.length / 1024).toFixed(0)} KB)`);
    } catch (e) {
      log(`Turismo ${uf}: falhou (${e.message})`);
    }
    await new Promise((r) => setTimeout(r, 5000)); // respeita o Overpass
  }
  return { ufs, changed };
}

/* ------------------------- Preços da ANP ------------------------- */

const ANP_PAGE = "https://www.gov.br/anp/pt-br/assuntos/precos-e-defesa-da-concorrencia/precos/" +
  "levantamento-de-precos-de-combustiveis-ultimas-semanas-pesquisadas";

const UF_NOME = {
  "ACRE": "AC", "ALAGOAS": "AL", "AMAZONAS": "AM", "AMAPA": "AP", "BAHIA": "BA",
  "CEARA": "CE", "DISTRITO FEDERAL": "DF", "ESPIRITO SANTO": "ES", "GOIAS": "GO",
  "MARANHAO": "MA", "MINAS GERAIS": "MG", "MATO GROSSO DO SUL": "MS",
  "MATO GROSSO": "MT", "PARA": "PA", "PARAIBA": "PB", "PERNAMBUCO": "PE",
  "PIAUI": "PI", "PARANA": "PR", "RIO DE JANEIRO": "RJ",
  "RIO GRANDE DO NORTE": "RN", "RONDONIA": "RO", "RORAIMA": "RR",
  "RIO GRANDE DO SUL": "RS", "SANTA CATARINA": "SC", "SERGIPE": "SE",
  "SAO PAULO": "SP", "TOCANTINS": "TO",
};

/** Código curto de cada produto (o app mostra gasolina primeiro). */
const PRODUTO = {
  "GASOLINA COMUM": "g", "GASOLINA ADITIVADA": "ga", "ETANOL": "e",
  "DIESEL": "d", "DIESEL S10": "d10", "GNV": "gnv",
};

const semAcento = (s) => s.normalize("NFD").replace(/[̀-ͯ]/g, "").toUpperCase().trim();

/** Lê um .xlsx (zip) sem biblioteca: devolve as linhas da 1ª planilha. */
function readXlsx(buf) {
  // Diretório central do zip.
  let eocd = buf.length - 22;
  while (eocd >= 0 && buf.readUInt32LE(eocd) !== 0x06054b50) eocd--;
  if (eocd < 0) throw new Error("xlsx inválido");
  const count = buf.readUInt16LE(eocd + 10);
  let p = buf.readUInt32LE(eocd + 16);
  const files = {};
  for (let i = 0; i < count; i++) {
    const method = buf.readUInt16LE(p + 10);
    const csize = buf.readUInt32LE(p + 20);
    const nlen = buf.readUInt16LE(p + 28), xlen = buf.readUInt16LE(p + 30), clen = buf.readUInt16LE(p + 32);
    const local = buf.readUInt32LE(p + 42);
    const name = buf.toString("utf8", p + 46, p + 46 + nlen);
    const lnlen = buf.readUInt16LE(local + 26), lxlen = buf.readUInt16LE(local + 28);
    const data = buf.subarray(local + 30 + lnlen + lxlen, local + 30 + lnlen + lxlen + csize);
    files[name] = () => (method === 8 ? zlib.inflateRawSync(data) : data).toString("utf8");
    p += 46 + nlen + xlen + clen;
  }
  const unxml = (s) => s.replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, "\"")
    .replace(/&apos;/g, "'").replace(/&amp;/g, "&");
  const strings = [];
  const ss = files["xl/sharedStrings.xml"] ? files["xl/sharedStrings.xml"]() : "";
  for (const si of ss.matchAll(/<si>([\s\S]*?)<\/si>/g)) {
    strings.push(unxml([...si[1].matchAll(/<t[^>]*>([\s\S]*?)<\/t>/g)].map((m) => m[1]).join("")));
  }
  const sheet = files["xl/worksheets/sheet1.xml"]();
  const col = (ref) => {
    let n = 0;
    for (const ch of ref.replace(/\d+/g, "")) n = n * 26 + ch.charCodeAt(0) - 64;
    return n - 1;
  };
  const rows = [];
  for (const r of sheet.matchAll(/<row[^>]*>([\s\S]*?)<\/row>/g)) {
    const row = [];
    for (const c of r[1].matchAll(/<c r="([A-Z]+\d+)"([^>]*?)(?:\/>|>([\s\S]*?)<\/c>)/g)) {
      const v = (c[3] || "").match(/<v>([\s\S]*?)<\/v>/)?.[1];
      const inline = (c[3] || "").match(/<t[^>]*>([\s\S]*?)<\/t>/)?.[1];
      let val = v ?? (inline != null ? unxml(inline) : "");
      if (/t="s"/.test(c[2]) && v != null) val = strings[+v] ?? "";
      row[col(c[1])] = val;
    }
    rows.push(row);
  }
  return rows;
}

/** Endereço da planilha semanal mais recente de preços por posto. */
async function latestAnpUrl() {
  const html = await (await fetch(ANP_PAGE, {
    headers: { "user-agent": "Mozilla/5.0 (UauGo; contato HelpAITech)" },
    signal: AbortSignal.timeout(60000),
  })).text();
  const links = [...html.matchAll(/href="([^"]*revendas_lpc_[^"]*\.xlsx)"/gi)].map((m) => m[1]);
  if (!links.length) throw new Error("planilha da ANP não encontrada");
  return links[0];
}

/** Planilha da ANP → postos por estado (com os preços de cada produto). */
function parseAnp(rows) {
  const head = rows.findIndex((r) => r && r.includes("CNPJ") && r.includes("PRODUTO"));
  if (head < 0) throw new Error("cabeçalho da ANP não encontrado");
  const h = rows[head].map((x) => semAcento(String(x || "")));
  const ix = (name) => h.indexOf(name);
  const I = {
    cnpj: ix("CNPJ"), razao: ix("RAZAO"), fantasia: ix("FANTASIA"), rua: ix("ENDERECO"),
    num: ix("NUMERO"), bairro: ix("BAIRRO"), mun: ix("MUNICIPIO"), uf: ix("ESTADO"),
    band: ix("BANDEIRA"), prod: ix("PRODUTO"), preco: ix("PRECO DE REVENDA"), data: ix("DATA DA COLETA"),
  };
  const semana = rows.slice(0, head).flat().find((x) => /PER[IÍ]ODO/i.test(String(x || ""))) || "";
  const byUf = {};
  const st = new Map();
  for (const r of rows.slice(head + 1)) {
    if (!r || !r[I.cnpj]) continue;
    const prod = PRODUTO[semAcento(String(r[I.prod] || ""))];
    if (!prod) continue; // GLP e outros: fora
    const uf = UF_NOME[semAcento(String(r[I.uf] || ""))];
    const preco = parseFloat(String(r[I.preco]).replace(",", "."));
    if (!uf || !(preco > 0)) continue;
    let s = st.get(r[I.cnpj]);
    if (!s) {
      // Data do Excel (dias desde 1899-12-30) → "AAAA-MM-DD".
      const d = parseFloat(r[I.data]);
      const data = d > 30000 ? new Date(Date.UTC(1899, 11, 30) + d * 86400000).toISOString().slice(0, 10) : String(r[I.data] || "");
      s = [String(r[I.fantasia] || r[I.razao] || "").trim(), String(r[I.rua] || "").trim(),
        String(r[I.num] || "").trim(), String(r[I.bairro] || "").trim(), String(r[I.mun] || "").trim(),
        String(r[I.band] || "").trim(), {}, data];
      st.set(r[I.cnpj], s);
      (byUf[uf] ||= []).push(s);
    }
    s[6][prod] = Math.round(preco * 100) / 100;
  }
  return { semana: String(semana).replace(/^.*?:\s*/, ""), byUf };
}

/** Baixa a semana mais recente da ANP e grava um arquivo por estado. */
async function buildCombustivel({ previousUrl, save, log = console.log }) {
  const url = await latestAnpUrl();
  if (url === previousUrl) return { url, changed: 0 };
  const res = await fetch(url, {
    headers: { "user-agent": "Mozilla/5.0 (UauGo; contato HelpAITech)" },
    signal: AbortSignal.timeout(120000),
  });
  if (!res.ok) throw new Error(`ANP HTTP ${res.status}`);
  const { semana, byUf } = parseAnp(readXlsx(Buffer.from(await res.arrayBuffer())));
  const ufs = {};
  for (const [uf, p] of Object.entries(byUf)) {
    const gz = zlib.gzipSync(JSON.stringify({ v: 1, uf, semana, p }), { level: 9 });
    await save("combustivel", uf, gz);
    ufs[uf] = { postos: p.length, bytes: gz.length, version: Date.now() };
  }
  log(`ANP ${semana}: ${Object.values(byUf).reduce((n, p) => n + p.length, 0)} postos em ${Object.keys(ufs).length} estados`);
  return { url, semana, ufs, changed: Object.keys(ufs).length };
}

module.exports = { buildTurismo, buildCombustivel, compact, parseAnp, readXlsx, redeOf, kindOf, query, fetchUf, REDES };
