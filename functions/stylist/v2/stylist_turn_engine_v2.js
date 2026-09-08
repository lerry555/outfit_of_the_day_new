"use strict";

const {clone, validateStylistSessionStateV2} = require("./stylist_session_state_v2");
const {validateTurnRequestV2} = require("./stylist_turn_contract_v2");
const {StaleSessionRevisionError} = require("./stylist_preflight_v2");
const {createStylistTurnCoordinatorV2} = require("./stylist_turn_coordinator_v2");
const {StylistSessionRepositoryV2Error} = require("./stylist_session_repository_v2");

function requirePort(value, label) {
  if (!value) throw new TypeError(`${label} is required`);
  return value;
}

function latestTurnReplay(state, turnId) {
  const matches = (state.replay?.turns || []).filter((entry) => entry.turnId === turnId);
  return matches.length ? matches[matches.length - 1] : null;
}

function createBoundCoordinatorRepository({durableRepository, uid, request, initialState}) {
  let workingState = clone(validateStylistSessionStateV2(initialState));
  let commitOutcome = null;

  return {
    async read(chatId) {
      if (chatId !== request.chatId) throw new TypeError("bound V2 repository chat mismatch");
      return clone(workingState);
    },

    async write(nextState) {
      const validated = validateStylistSessionStateV2(nextState);
      const replay = latestTurnReplay(validated, request.turnId);
      if (!replay?.result) {
        throw new StylistSessionRepositoryV2Error(
          "TURN_RECEIPT_MALFORMED",
          "accepted turn must be present in replay before durable commit",
        );
      }

      try {
        commitOutcome = await durableRepository.commitTurn({
          uid,
          chatId: request.chatId,
          turnId: request.turnId,
          expectedRevision: request.expectedSessionRevision,
          nextState: validated,
          result: replay.result,
        });
      } catch (error) {
        if (error instanceof StylistSessionRepositoryV2Error && error.code === "SESSION_CONFLICT") {
          const latest = await durableRepository.get({uid, chatId: request.chatId});
          throw new StaleSessionRevisionError(
            request.expectedSessionRevision,
            latest?.state?.revision ?? request.expectedSessionRevision,
          );
        }
        throw error;
      }

      const persisted = await durableRepository.get({uid, chatId: request.chatId});
      if (!persisted?.state) {
        throw new StylistSessionRepositoryV2Error("SESSION_NOT_FOUND", "session disappeared after commit");
      }
      workingState = clone(persisted.state);
      return clone(workingState);
    },

    commitOutcome() {
      return clone(commitOutcome);
    },
  };
}

async function ensureCanonicalSession({durableRepository, uid, request, bootstrapInput}) {
  const ensured = bootstrapInput ?
    await durableRepository.ensureFromLegacy({uid, chatId: request.chatId, bootstrapInput}) :
    await durableRepository.ensure({uid, chatId: request.chatId});
  return validateStylistSessionStateV2(ensured.state);
}

function createStylistTurnEngineV2({sessionRepository, wardrobeTool, locationResolver,
  weatherTool, shoppingTool, stylistModel, clock = () => Date.now()}) {
  const durableRepository = requirePort(sessionRepository, "sessionRepository");
  requirePort(durableRepository.ensure, "sessionRepository.ensure");
  requirePort(durableRepository.ensureFromLegacy, "sessionRepository.ensureFromLegacy");
  requirePort(durableRepository.get, "sessionRepository.get");
  requirePort(durableRepository.commitTurn, "sessionRepository.commitTurn");

  const sharedPorts = {
    wardrobeTool: requirePort(wardrobeTool, "wardrobeTool"),
    locationResolver: requirePort(locationResolver, "locationResolver"),
    weatherTool: requirePort(weatherTool, "weatherTool"),
    shoppingTool: requirePort(shoppingTool, "shoppingTool"),
    stylistModel: requirePort(stylistModel, "stylistModel"),
    clock,
  };

  return Object.freeze({
    async resolveTurn({uid, request: untrustedRequest, bootstrapInput = null}) {
      const request = validateTurnRequestV2(untrustedRequest);
      const initialState = await ensureCanonicalSession({
        durableRepository,
        uid,
        request,
        bootstrapInput,
      });

      const boundRepository = createBoundCoordinatorRepository({
        durableRepository,
        uid,
        request,
        initialState,
      });
      const coordinator = createStylistTurnCoordinatorV2({
        sessionRepository: boundRepository,
        ...sharedPorts,
      });

      const result = await coordinator.resolveTurn(request);
      const outcome = boundRepository.commitOutcome();
      return clone(outcome?.replayed ? outcome.result : result);
    },
  });
}

module.exports = {
  createBoundCoordinatorRepository,
  createStylistTurnEngineV2,
  ensureCanonicalSession,
  latestTurnReplay,
};
