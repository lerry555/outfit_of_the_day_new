"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {
  ClaimFcmTokenError,
  createClaimFcmTokenHandler,
  createClaimFcmTokenService,
} = require("./claim_fcm_token");

class FakeDoc {
  constructor(id, data) {
    this.id = id;
    this._data = data ? {...data} : null;
  }
  get exists() {
    return this._data != null;
  }
  data() {
    return this._data ? {...this._data} : undefined;
  }
}

class FakeDb {
  constructor(users = {}) {
    this.users = Object.fromEntries(
      Object.entries(users).map(([id, data]) => [id, {...data}]),
    );
  }

  collection(name) {
    assert.equal(name, "users");
    const db = this;
    return {
      where(field, op, value) {
        assert.equal(field, "fcmTokens");
        assert.equal(op, "array-contains");
        return {
          limit() {
            return this;
          },
          async get() {
            const docs = Object.entries(db.users)
              .filter(([, data]) => Array.isArray(data.fcmTokens) &&
                data.fcmTokens.includes(value))
              .map(([id, data]) => new FakeDoc(id, data));
            return {docs};
          },
        };
      },
      doc(id) {
        return {
          id,
          async get() {
            return new FakeDoc(id, db.users[id] || null);
          },
        };
      },
    };
  }

  async runTransaction(fn) {
    const writes = [];
    const users = this.users;
    const tx = {
      async get(ref) {
        return new FakeDoc(ref.id, users[ref.id] || null);
      },
      set(ref, data) {
        writes.push({id: ref.id, data});
      },
    };
    await fn(tx);
    for (const write of writes) {
      const current = {...(users[write.id] || {})};
      const nextTokens = [...(current.fcmTokens || [])];
      const op = write.data.fcmTokens;
      if (op && op._op === "union") {
        if (!nextTokens.includes(op.token)) nextTokens.push(op.token);
      } else if (op && op._op === "remove") {
        const idx = nextTokens.indexOf(op.token);
        if (idx >= 0) nextTokens.splice(idx, 1);
      }
      current.fcmTokens = nextTokens;
      users[write.id] = current;
    }
  }
}

const FieldValue = {
  arrayUnion(token) {
    return {_op: "union", token};
  },
  arrayRemove(token) {
    return {_op: "remove", token};
  },
};

const TOKEN = "fcm-token-value-that-is-long-enough-32ch";
const T1 = "device-one-token-value-32chars!!";
const T2 = "device-two-token-value-32chars!!";

function service(users) {
  const db = new FakeDb(users);
  return {
    db,
    value: createClaimFcmTokenService({db, FieldValue}),
  };
}

function httpsError(code, message) {
  const error = new Error(message);
  error.code = code;
  return error;
}

test("unauthenticated claim rejected", async () => {
  const app = service({});
  await assert.rejects(
    () => app.value.claimForUid("", TOKEN),
    (error) => error instanceof ClaimFcmTokenError &&
      error.code === "unauthenticated",
  );
});

test("handler rejects missing auth without querying", async () => {
  let queried = false;
  const handler = createClaimFcmTokenHandler({
    db: {
      collection() {
        queried = true;
        throw new Error("should_not_query");
      },
    },
    FieldValue,
    logger: {warn() {}},
    httpsError,
  });
  await assert.rejects(
    () => handler({token: TOKEN}, {}),
    (error) => error.code === "unauthenticated",
  );
  assert.equal(queried, false);
});

test("empty and invalid tokens are rejected", async () => {
  const app = service({a: {fcmTokens: []}});
  await assert.rejects(() => app.value.claimForUid("a", ""), ClaimFcmTokenError);
  await assert.rejects(() => app.value.claimForUid("a", "short"), ClaimFcmTokenError);
  await assert.rejects(() => app.value.claimForUid("a", 12), ClaimFcmTokenError);
  await assert.rejects(
    () => app.value.claimForUid("a", `${TOKEN} has space`),
    ClaimFcmTokenError,
  );
  await assert.rejects(
    () => app.value.claimForUid("a", "x".repeat(5000)),
    ClaimFcmTokenError,
  );
});

test("handler rejects invalid token without leaking the value", async () => {
  const handler = createClaimFcmTokenHandler({
    db: new FakeDb({a: {fcmTokens: []}}),
    FieldValue,
    logger: {warn() {}},
    httpsError,
  });
  await assert.rejects(
    () => handler({token: "short"}, {auth: {uid: "a"}}),
    (error) => error.code === "invalid-argument" &&
      error.message === "invalid_token",
  );
});

test("current user claim adds token", async () => {
  const app = service({b: {displayName: "B", fcmTokens: ["keep-b"]}});
  const result = await app.value.claimForUid("b", TOKEN);
  assert.equal(result.ok, true);
  assert.deepEqual(app.db.users.b.fcmTokens, ["keep-b", TOKEN]);
  assert.equal(app.db.users.b.displayName, "B");
});

test("duplicate claim is idempotent", async () => {
  const app = service({b: {fcmTokens: [TOKEN], theme: "dark"}});
  await app.value.claimForUid("b", TOKEN);
  await app.value.claimForUid("b", TOKEN);
  assert.deepEqual(app.db.users.b.fcmTokens, [TOKEN]);
  assert.equal(app.db.users.b.theme, "dark");
});

test("token is removed from one previous owner", async () => {
  const app = service({
    a: {fcmTokens: [TOKEN], name: "A"},
    b: {fcmTokens: []},
  });
  await app.value.claimForUid("b", TOKEN);
  assert.deepEqual(app.db.users.a.fcmTokens, []);
  assert.equal(app.db.users.a.name, "A");
  assert.deepEqual(app.db.users.b.fcmTokens, [TOKEN]);
});

test("token is removed from multiple previous owners", async () => {
  const app = service({
    a: {fcmTokens: [TOKEN]},
    c: {fcmTokens: [TOKEN]},
    b: {fcmTokens: []},
  });
  await app.value.claimForUid("b", TOKEN);
  assert.deepEqual(app.db.users.a.fcmTokens, []);
  assert.deepEqual(app.db.users.c.fcmTokens, []);
  assert.deepEqual(app.db.users.b.fcmTokens, [TOKEN]);
});

test("switching device token T1 leaves A's T2 in place", async () => {
  const app = service({
    a: {fcmTokens: [T1, T2], city: "BA"},
    b: {fcmTokens: ["old-b-token-value-32chars!!!!!!"]},
  });
  await app.value.claimForUid("b", T1);
  assert.deepEqual(app.db.users.a.fcmTokens, [T2]);
  assert.equal(app.db.users.a.city, "BA");
  assert.deepEqual(app.db.users.b.fcmTokens, [
    "old-b-token-value-32chars!!!!!!",
    T1,
  ]);
});

test("stale A ownership is repaired when B claims T", async () => {
  const app = service({
    a: {fcmTokens: [TOKEN]},
    b: {fcmTokens: []},
  });
  await app.value.claimForUid("b", TOKEN);
  assert.ok(!app.db.users.a.fcmTokens.includes(TOKEN));
  assert.ok(app.db.users.b.fcmTokens.includes(TOKEN));
});

test("sequential claims leave the last claimant as sole owner", async () => {
  const app = service({
    a: {fcmTokens: []},
    b: {fcmTokens: []},
  });
  await app.value.claimForUid("a", TOKEN);
  await app.value.claimForUid("b", TOKEN);
  assert.deepEqual(app.db.users.a.fcmTokens, []);
  assert.deepEqual(app.db.users.b.fcmTokens, [TOKEN]);
});

test("parallel claims settle on a single owner", async () => {
  const app = service({
    a: {fcmTokens: []},
    b: {fcmTokens: []},
  });
  await Promise.all([
    app.value.claimForUid("a", TOKEN),
    app.value.claimForUid("b", TOKEN),
  ]);
  const aHas = app.db.users.a.fcmTokens.includes(TOKEN);
  const bHas = app.db.users.b.fcmTokens.includes(TOKEN);
  assert.equal(aHas && bHas, false);
  assert.equal(aHas || bHas, true);
});

test("overlapping query-then-write race is repaired by a later claim", async () => {
  const app = service({
    a: {fcmTokens: []},
    b: {fcmTokens: []},
  });
  // Residual race of the flat-array schema: both claimants queried before
  // either write landed, so both arrays contain T. The next claim restores
  // single ownership without a reverse index.
  app.db.users.a.fcmTokens = [TOKEN];
  app.db.users.b.fcmTokens = [TOKEN];
  await app.value.claimForUid("b", TOKEN);
  assert.deepEqual(app.db.users.a.fcmTokens, []);
  assert.deepEqual(app.db.users.b.fcmTokens, [TOKEN]);
});

test("response does not include previous owner uids or the token", async () => {
  const app = service({
    a: {fcmTokens: [TOKEN]},
    b: {fcmTokens: []},
  });
  const result = await app.value.claimForUid("b", TOKEN);
  assert.deepEqual(Object.keys(result).sort(), ["ok"]);
  assert.equal(JSON.stringify(result).includes("a"), false);
  assert.equal(JSON.stringify(result).includes(TOKEN), false);
});
