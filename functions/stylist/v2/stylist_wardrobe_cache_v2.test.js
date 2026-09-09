"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  clearWardrobeCacheV2,
  loadRevisionAwareWardrobeV2,
  readWardrobeRevisionTokenV2,
} = require("./firestore_wardrobe_tool_v2");

test.beforeEach(() => clearWardrobeCacheV2());

test("wardrobe cache reuses a full snapshot only while the revision token is unchanged", async () => {
  let revision = "3:1000:item-c:2";
  let loads = 0;
  const load = () => loadRevisionAwareWardrobeV2({
    cacheKey: "user-1",
    loadRevision: async () => revision,
    loadItems: async () => {
      loads += 1;
      return [{id: `item-${loads}`, name: "Tričko"}];
    },
  });

  const first = await load();
  const second = await load();
  assert.equal(loads, 1);
  assert.deepEqual(second, first);

  revision = "4:2000:item-d:1";
  const third = await load();
  assert.equal(loads, 2);
  assert.notDeepEqual(third, first);
});

test("wardrobe cache returns defensive clones so one request cannot mutate another", async () => {
  let loads = 0;
  const args = {
    cacheKey: "user-2",
    loadRevision: async () => "1:1000:item-a:1",
    loadItems: async () => {
      loads += 1;
      return [{id: "item-a", colors: ["black"]}];
    },
  };

  const first = await loadRevisionAwareWardrobeV2(args);
  first[0].colors.push("red");
  const second = await loadRevisionAwareWardrobeV2(args);

  assert.equal(loads, 1);
  assert.deepEqual(second, [{id: "item-a", colors: ["black"]}]);
});

test("unknown revision deliberately bypasses cache instead of risking stale advice", async () => {
  let loads = 0;
  const load = () => loadRevisionAwareWardrobeV2({
    cacheKey: "user-3",
    loadRevision: async () => null,
    loadItems: async () => {
      loads += 1;
      return [{id: `fresh-${loads}`}];
    },
  });

  const first = await load();
  const second = await load();
  assert.equal(loads, 2);
  assert.notDeepEqual(first, second);
});

test("revision token changes for add/remove and ordinary updatedAt edits", async () => {
  function root({count, id, updatedAt, wardrobeItemRevision}) {
    return {
      count() {
        return {get: async () => ({data: () => ({count})})};
      },
      orderBy(field, direction) {
        assert.equal(field, "updatedAt");
        assert.equal(direction, "desc");
        return {
          limit(limit) {
            assert.equal(limit, 1);
            return {
              get: async () => ({
                docs: count === 0 ? [] : [{
                  id,
                  exists: true,
                  data: () => ({updatedAt, wardrobeItemRevision}),
                }],
              }),
            };
          },
        };
      },
    };
  }

  const base = await readWardrobeRevisionTokenV2(root({count: 3, id: "c", updatedAt: 1000, wardrobeItemRevision: 2}));
  const edited = await readWardrobeRevisionTokenV2(root({count: 3, id: "c", updatedAt: 1100, wardrobeItemRevision: 3}));
  const added = await readWardrobeRevisionTokenV2(root({count: 4, id: "d", updatedAt: 1200, wardrobeItemRevision: 1}));
  const empty = await readWardrobeRevisionTokenV2(root({count: 0, id: "", updatedAt: null, wardrobeItemRevision: 0}));

  assert.equal(base, "3:1000:c:2");
  assert.notEqual(edited, base);
  assert.notEqual(added, edited);
  assert.equal(empty, "0:empty");
});

test("revision probe fails closed to no-cache when Firestore capabilities are missing", async () => {
  assert.equal(await readWardrobeRevisionTokenV2({}), null);
  assert.equal(await readWardrobeRevisionTokenV2({count() { return {}; }}), null);
});
