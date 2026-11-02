// Testes da junção dos limites (functions/speedlimits.js).
// Rodar: node --test functions/test/speedlimits.test.js
const test = require("node:test");
const assert = require("node:assert");
const { mergeLimits, expand, compact } = require("../speedlimits");

const lim = (r) => r.map((p) => p[2]).sort();

test("entra onde não há limite", () => {
  assert.deepStrictEqual(lim(mergeLimits([], [[100, 100, 110, 0, 90]])), [110]);
});

test("troca estimado da mesma via", () => {
  const r = mergeLimits([[100, 100, 80, 1, 90]], [[105, 100, 110, 0, 85]]);
  assert.deepStrictEqual(lim(r), [110]);
});

test("placa real do Pardal não muda", () => {
  const r = mergeLimits([[100, 100, 80, 0, 90]], [[105, 100, 110, 0, 85]]);
  assert.deepStrictEqual(lim(r), [80]);
});

test("outro sentido não interfere", () => {
  const r = mergeLimits([[100, 100, 80, 0, 270]], [[105, 100, 110, 0, 90]]);
  assert.deepStrictEqual(lim(r), [80, 110].sort());
});

test("expand desfaz compact", () => {
  const p = [[10, 20, 60, 0, -1], [15, 18, 80, 1, 90]];
  assert.deepStrictEqual(expand(compact(p).d), p);
});
