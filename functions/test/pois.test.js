// Sentido das lombadas (functions/pois.js). Sem emulador:
//   node --test functions/test/pois.test.js
const test = require("node:test");
const assert = require("node:assert");
const { compact } = require("../pois");

const bump = { type: "node", id: 1, lat: -21, lon: -47, tags: { traffic_calming: "bump" } };
const way = (oneway) => ({
  type: "way", nodes: [1, 2], tags: { oneway },
  geometry: [{ lat: -21, lon: -47 }, { lat: -20.99, lon: -47 }],
});

test("lombada em via de mão única guarda o sentido da via", () => {
  assert.deepStrictEqual(compact([bump, way("yes")]).bh, [0]);
  assert.deepStrictEqual(compact([bump, way("-1")]).bh, [180]);
});

test("mão dupla ou sem via: vale para os dois lados", () => {
  assert.deepStrictEqual(compact([bump, way("no")]).bh, [-1]);
  assert.deepStrictEqual(compact([bump]).bh, [-1]);
});
