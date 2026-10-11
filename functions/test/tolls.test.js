// Testes da tabela de pedágios (functions/tolls.js). Sem emulador:
//   node --test functions/test/tolls.test.js
const test = require("node:test");
const assert = require("node:assert");
const t = require("../tolls");

const csv = (head, rows) => [head, ...rows].join("\n");

test("nomes de concessionária iguais entre planilhas", () => {
  assert.strictEqual(t.concKey("RIO-SP"), t.concKey("RIOSP"));
  assert.ok(t.concSimilar(t.concKey("ECOVIAS RIO MINAS"), t.concKey("ECO RIOMINAS")) >= 0.75);
});

test("praça casada pelo número e pelo nome", () => {
  const eq = ["P01 São Luiz do Purunã", "P02 Porto Amazonas"];
  assert.strictEqual(
    t.matchPlaza("P02 - Porto Amazonas - BR-277/PR - 165,7Km", eq), "P02 Porto Amazonas");
});

test("praça separada por sentido numa planilha é somada", () => {
  assert.deepStrictEqual(
    t.matchPlazas("Moreira César", ["Moreira César Norte", "Moreira César Sul", "Itatiaia"]),
    ["Moreira César Norte", "Moreira César Sul"]);
});

test("preço do carro = receita ÷ veículos equivalentes; moto isenta ou metade", () => {
  const eq = t.parseCsv(csv(
    "concessionaria;mes_ano;sentido;praca;tipo_de_cobranca;categoria_eixo;tipo_de_veiculo;volume_total;multiplicador_de_tarifa;volume_veiculo_equivalente",
    [
      '"VIA X";"12/2025";"Crescente";"P1 Alfa";"Manual";"2";"Passeio";1000,00;1,00;1000,00',
      '"VIA X";"12/2025";"Crescente";"P1 Alfa";"Manual";"6";"Comercial";100,00;6,00;600,00',
      '"VIA X";"12/2025";"Crescente";"P1 Alfa";"Manual";"2";"Moto";50,00;0,50;25,00',
      '"VIA X";"12/2025";"Crescente";"P2 Beta";"Manual";"2";"Passeio";500,00;1,00;500,00',
      '"VIA X";"12/2025";"Crescente";"P2 Beta";"Manual";"2";"Moto";40,00;0,00;0,00',
    ]));
  const rec = t.parseCsv(csv(
    "Concessionaria;Praca_de_pedagio;UF;Latitude;Longitude;Mes_ano;Receita_Praca_de_Pedagio",
    [
      "VIA X;P1 - Alfa;PR;-25,1;-49,1;12/2025;8125",
      "VIA X;P2 - Beta;PR;-25,5;-49,5;12/2025;5000",
    ]));
  const f = t.priceFederal(rec, eq, "12/2025");
  assert.strictEqual(f.length, 2);
  assert.strictEqual(f[0].car, 5); // 8125 / (1000 + 600 + 25)
  assert.strictEqual(f[0].moto, 0.5);
  assert.strictEqual(f[1].car, 10);
  assert.strictEqual(f[1].moto, 0);
});

test("cabines vizinhas viram uma praça e recebem o preço federal", () => {
  const osm = t.clusterBooths([
    [-25.1, -49.1, false], [-25.1005, -49.1002, false], [-23, -46, true],
  ]);
  assert.strictEqual(osm.length, 2);
  const { plazas, matched } = t.mergePlazas(osm, [
    { lat: -25.105, lng: -49.105, car: 5, moto: 0.5 }, // ~700 m: mesma praça
    { lat: -10, lng: -40, car: 7, moto: null }, // sem cabine no OSM
  ]);
  assert.strictEqual(matched, 1);
  assert.strictEqual(plazas[0].car, 5);
  assert.strictEqual(plazas[1].moto, 0); // OSM: moto isenta
  assert.strictEqual(plazas[2].radius, 250);
});

test("pontos de pedágio do arquivo de POIs", () => {
  // lombada (1), pedágio (3), pedágio moto isenta (4); diferenças acumuladas.
  const d = [-2500000, -4900000, 1, 100, 100, 3, 100, 100, 4];
  assert.deepStrictEqual(t.boothsFromPois(d), [[-24.999, -48.999, false], [-24.998, -48.998, true]]);
});
