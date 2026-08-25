"use strict";

const crypto = require("crypto");
const {executeCatalogSearch, refineCatalogSearch} = require("./catalog_search_query_service");
const {
  buildPublicCandidate,
  buildPublicCandidateDetail,
} = require("./public_shopping_dto");
const {createResultPool, markShown, page, rejectCandidate, validateProductFocus} =
  require("./shopping_result_pool");
const {
  createMemoryShoppingSessionStore,
  ShoppingSessionStoreError,
} = require("./shopping_session_store");

const MAX_PAGE_SIZE = 50;
const MAX_CONSTRAINTS = 20;
const SESSION_TTL_MS = 30 * 60 * 1000;

class ShoppingOrchestrationError extends Error {
  constructor(code, message = code) {
    super(message);
    this.code = code;
  }
}

/**
 * Authenticated transport boundary. The injected store owns session state;
 * the production Firestore implementation is server-only and durable.
 */
function createShoppingOrchestrator({repository, sessionStore = createMemoryShoppingSessionStore()}) {
  async function dispatch(auth, request) {
    const uid = requireAuth(auth);
    const operation = String(request?.operation || "");
    switch (operation) {
      case "START_SEARCH": return start(uid, request);
      case "SHOW_MORE": return show(uid, request, false);
      case "SHOW_ALL": return show(uid, request, true);
      case "REJECT_CANDIDATE": return reject(uid, request);
      case "REFINE_QUERY": return refine(uid, request);
      case "FOCUS_CANDIDATE": return focus(uid, request);
      case "GET_CANDIDATE_DETAILS": return details(uid, request);
      case "REVALIDATE_POOL": return revalidate(uid, request);
      default: throw new ShoppingOrchestrationError("INVALID_ARGUMENT", "unknown_operation");
    }
  }

  async function start(uid, request) {
    validateQuery(request.query);
    const pageSize = validatePageSize(request.pageSize);
    const key = request.idempotencyKey == null ? null : safeId(request.idempotencyKey, "idempotency_key");
    if (key) {
      const existingId = await sessionStore.getIdempotency(uid, key);
      const existing = existingId && await sessionStore.get(existingId);
      if (existing && existing.ownerUid === uid && !expired(existing)) {
        const existingSearch = await hydrateSearch(existing);
        return response(existing, existing.initialPresentedCandidateIds, false, existingSearch);
      }
    }
    const result = await executeCatalogSearch({query: request.query, repository});
    const now = sessionStore.now();
    const session = {
      sessionId: opaqueId(), ownerUid: uid, query: request.query, searchResult: result,
      searchMeta: searchMeta(result), pool: createResultPool(result), createdAt: now,
      updatedAt: now, expiresAt: now + SESSION_TTL_MS, version: 0,
      focusedVariantId: null, focusedOfferId: null, interactionState: null,
      operationReceipts: [],
    };
    session.pool = markShown(session.pool, page(session.pool, pageSize));
    session.initialPresentedCandidateIds = [...session.pool.shownCandidateIds];
    const created = await sessionStore.createSession({session, idempotencyKey: key});
    if (!created.created) {
      const existingSearch = await hydrateSearch(created.session);
      return response(created.session, created.session.initialPresentedCandidateIds,
        false, existingSearch);
    }
    return response(created.session, session.pool.shownCandidateIds, false, result);
  }

  async function show(uid, request, all) {
    const session = await requireSession(uid, request.sessionId);
    const current = await assertCurrent(session);
    const limit = all ? MAX_PAGE_SIZE : validatePageSize(request.pageSize);
    const mutation = await mutate(session, request, "SHOW_MORE", (next) => {
      assertCurrentRevision(next, current);
      const ids = page(next.pool, limit);
      return {session: {...next, pool: markShown(next.pool, ids)}, result: {ids}};
    });
    return response(mutation.session, mutation.result.ids, false, current);
  }

  async function reject(uid, request) {
    const session = await requireSession(uid, request.sessionId);
    const current = await assertCurrent(session);
    const id = safeId(request.variantId, "variant_id");
    const mutation = await mutate(session, request, "REJECT_CANDIDATE", (next) => {
      assertCurrentRevision(next, current);
      if (!next.pool.orderedCandidateIds.includes(id)) throw new ShoppingOrchestrationError("CANDIDATE_NOT_IN_POOL");
      return {session: {...next, pool: rejectCandidate(next.pool, id)}, result: {id}};
    });
    return {status: "OK", sessionId: mutation.session.sessionId, version: mutation.session.version};
  }

  async function refine(uid, request) {
    const session = await requireSession(uid, request.sessionId);
    validateQuery(request.query);
    const operationId = request.operationId == null ? null :
      safeId(request.operationId, "operation_id");
    const replay = operationId && (session.operationReceipts || []).find((item) =>
      item.operationId === operationId && item.operationType === "REFINE_QUERY");
    if (replay) {
      const current = await assertCurrent(session);
      return response(session, replay.result.ids, replay.result.reused === true, current);
    }
    const expectedQueryRevision = request.expectedQueryRevision == null ?
      Number(request.query.revision) - 1 :
      Number(request.expectedQueryRevision);
    if (!Number.isSafeInteger(expectedQueryRevision) ||
        expectedQueryRevision !== session.query.revision) {
      throw new ShoppingOrchestrationError("QUERY_REVISION_CONFLICT");
    }
    const previousResult = await assertCurrent(session);
    const decision = refineCatalogSearch({
      previousQuery: session.query, nextQuery: request.query,
      previousResult, currentCatalogRevision: previousResult.catalogRevision,
    });
    let nextResult;
    if (decision.decision === "REQUERY_REQUIRED") {
      nextResult = await executeCatalogSearch({query: request.query, repository});
    } else {
      nextResult = decision.result;
    }
    const limit = validatePageSize(request.pageSize);
    const mutation = await mutate(session, request, "REFINE_QUERY", (next) => {
      if (next.query.revision !== expectedQueryRevision) {
        throw new ShoppingOrchestrationError("QUERY_REVISION_CONFLICT");
      }
      assertCurrentRevision(next, previousResult);
      const newPool = createResultPool(nextResult);
      const ids = page(newPool, limit);
      return {
        session: {
          ...next,
          query: request.query,
          searchMeta: searchMeta(nextResult),
          pool: markShown(newPool, ids),
          initialPresentedCandidateIds: ids,
          focusedVariantId: null,
          focusedOfferId: null,
        },
        result: {ids, reused: decision.decision === "POOL_REUSABLE"},
      };
    });
    return response(mutation.session, mutation.result.ids,
      mutation.result.reused === true, nextResult);
  }

  async function focus(uid, request) {
    const session = await requireSession(uid, request.sessionId);
    const current = await assertCurrent(session);
    const validation = validateProductFocus({
      pool: session.pool, catalogRevision: current.catalogRevision,
      variantId: safeId(request.variantId, "variant_id"), offerId: request.offerId || null,
      searchResult: current,
    });
    if (!validation.valid) throw new ShoppingOrchestrationError(
      validation.reason === "OFFER_NOT_IN_CANDIDATE" ? "OFFER_NOT_IN_CANDIDATE" : "CANDIDATE_NOT_IN_POOL",
    );
    const mutation = await mutate(session, request, "FOCUS_CANDIDATE", (next) => {
      assertCurrentRevision(next, current);
      return {session: {...next, focusedVariantId: validation.focusedVariantId,
        focusedOfferId: validation.focusedOfferId}, result: validation};
    });
    return {status: "OK", ...mutation.result, version: mutation.session.version};
  }

  async function details(uid, request) {
    const session = await requireSession(uid, request.sessionId);
    const id = safeId(request.variantId, "variant_id");
    if (!session.pool.orderedCandidateIds.includes(id)) throw new ShoppingOrchestrationError("CANDIDATE_NOT_IN_POOL");
    const current = await assertCurrent(session);
    const candidate = current.candidates.find((item) => item.variantId === id);
    if (!candidate) throw new ShoppingOrchestrationError("CANDIDATE_UNAVAILABLE");
    return buildPublicCandidateDetail({
      candidate,
      catalog: current._catalogSnapshot,
      query: session.query,
    });
  }

  async function revalidate(uid, request) {
    const session = await requireSession(uid, request.sessionId);
    const current = await executeCatalogSearch({query: session.query, repository});
    return {
      status: current.catalogRevision === session.searchMeta.catalogRevision ? "POOL_VALID" : "REBUILD_REQUIRED",
      catalogRevision: current.catalogRevision,
    };
  }

  async function requireSession(uid, id) {
    let session;
    try {
      session = await sessionStore.get(safeId(id, "session_id"));
    } catch (error) {
      throw mapStoreError(error);
    }
    if (!session) throw new ShoppingOrchestrationError("SESSION_NOT_FOUND");
    if (session.ownerUid !== uid) throw new ShoppingOrchestrationError("SESSION_FORBIDDEN");
    if (expired(session)) throw new ShoppingOrchestrationError("SESSION_EXPIRED");
    return session;
  }
  async function assertCurrent(session) {
    const current = await executeCatalogSearch({query: session.query, repository});
    if (current.catalogRevision !== session.searchMeta.catalogRevision) {
      throw new ShoppingOrchestrationError("POOL_STALE");
    }
    return current;
  }
  async function hydrateSearch(session) { return assertCurrent(session); }
  async function mutate(session, request, operationType, mutation) {
    try {
      return await sessionStore.mutate(session.sessionId, {
        ownerUid: session.ownerUid,
        expectedVersion: request.expectedVersion == null ? null : request.expectedVersion,
        operationId: request.operationId == null ? null : safeId(request.operationId, "operation_id"),
        operationType,
      }, mutation);
    } catch (error) {
      throw mapStoreError(error);
    }
  }
  return {dispatch, sessionStore};
}

function response(session, ids, reused, searchResult) {
  const candidateMap = new Map(searchResult.candidates.map((item) => [item.variantId, item]));
  return {
    status: searchResult.candidates.length ? "OK" : "NO_RESULTS",
    sessionId: session.sessionId, queryRevision: searchResult.queryRevision,
    catalogRevision: searchResult.catalogRevision,
    sessionVersion: session.version,
    isComplete: searchResult.completeness === "COMPLETE",
    exactResultCount: searchResult.exactResultCount,
    candidates: ids.map((id) =>
      buildPublicCandidate({
        candidate: candidateMap.get(id),
        catalog: searchResult._catalogSnapshot,
        query: session.query,
      })),
    diagnostics: searchResult.diagnostics,
    poolReused: reused,
  };
}

function requireAuth(auth) {
  if (!auth || typeof auth.uid !== "string" || !auth.uid) throw new ShoppingOrchestrationError("UNAUTHENTICATED");
  return auth.uid;
}
function validateQuery(query) {
  if (!query || !Array.isArray(query.constraints) || query.constraints.length > MAX_CONSTRAINTS) {
    throw new ShoppingOrchestrationError("INVALID_ARGUMENT", "invalid_query");
  }
}
function validatePageSize(value) {
  const size = value == null ? 3 : value;
  if (!Number.isSafeInteger(size) || size < 1 || size > MAX_PAGE_SIZE) {
    throw new ShoppingOrchestrationError("INVALID_ARGUMENT", "invalid_page_size");
  }
  return size;
}
function safeId(value, label) {
  const text = String(value || "");
  if (!/^[A-Za-z0-9_-]{1,128}$/.test(text)) throw new ShoppingOrchestrationError("INVALID_ARGUMENT", `invalid_${label}`);
  return text;
}
function expired(session) { return session.expiresAt <= Date.now(); }
function searchMeta(result) {
  return {
    queryId: result.queryId, queryRevision: result.queryRevision,
    catalogRevision: result.catalogRevision, completeness: result.completeness,
    exactResultCount: result.exactResultCount, diagnostics: result.diagnostics,
  };
}
function assertCurrentRevision(session, searchResult) {
  if (session.searchMeta.catalogRevision !== searchResult.catalogRevision ||
      session.query.revision !== searchResult.queryRevision) {
    throw new ShoppingOrchestrationError("SESSION_CONFLICT");
  }
}
function mapStoreError(error) {
  if (error instanceof ShoppingOrchestrationError) return error;
  if (error instanceof ShoppingSessionStoreError) {
    return new ShoppingOrchestrationError(error.code);
  }
  return error;
}
function opaqueId() { return crypto.randomBytes(18).toString("base64url"); }

module.exports = {
  MAX_PAGE_SIZE, SESSION_TTL_MS, ShoppingOrchestrationError,
  createMemoryShoppingSessionStore, createShoppingOrchestrator,
};
