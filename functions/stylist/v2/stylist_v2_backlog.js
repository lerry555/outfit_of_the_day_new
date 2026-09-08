"use strict";

const DETERMINISTIC = "deterministic_contract";
const INTEGRATION = "future_integration";
const MODEL_EVAL = "future_model_eval";

const PROBLEM_BACKLOG_V2 = Object.freeze([
  {id: 1, problem: "Outfit generation before key clarification", classification: DETERMINISTIC, safeguard: "preflight grounding gate + clarify result"},
  {id: 2, problem: "Weather from wrong location", classification: DETERMINISTIC, safeguard: "destination-scoped weather provenance validation"},
  {id: 3, problem: "Weak activity/terrain distinction", classification: DETERMINISTIC, safeguard: "orthogonal surface/difficulty/condition facts"},
  {id: 4, problem: "Wardrobe gap with no useful next action", classification: INTEGRATION, safeguard: "missing need + typed pending Shopping action"},
  {id: 5, problem: "Unhelpful no-match Shopping response", classification: MODEL_EVAL, safeguard: "Shopping response quality eval"},
  {id: 6, problem: "Context loss between Stylist and Shopping", classification: DETERMINISTIC, safeguard: "same-session Shopping context handoff"},
  {id: 7, problem: "Yes/No losing its pending meaning", classification: DETERMINISTIC, safeguard: "actionId-bound pending referent"},
  {id: 8, problem: "Simple follow-ups invoking expensive full Stylist", classification: DETERMINISTIC, safeguard: "deterministic pending-action preflight"},
  {id: 9, problem: "Every turn using the most expensive model", classification: INTEGRATION, safeguard: "mutually exclusive production routing policy"},
  {id: 10, problem: "Full wardrobe loaded unnecessarily", classification: DETERMINISTIC, safeguard: "ledgered none/current/category/full retrieval scopes"},
  {id: 11, problem: "Conversation messages failing closed as outfit requests", classification: DETERMINISTIC, safeguard: "chat action permits empty outfit"},
  {id: 12, problem: "Cards appearing during consultation", classification: DETERMINISTIC, safeguard: "explicit display directive"},
  {id: 13, problem: "Repeated irrelevant warnings", classification: INTEGRATION, safeguard: "persisted communicated-warning memory"},
  {id: 14, problem: "Edit explanation missing original reason", classification: DETERMINISTIC, safeguard: "item-bound current and historical reasons"},
  {id: 15, problem: "Historical selection reason invented or changed", classification: DETERMINISTIC, safeguard: "immutable retained reasons + append-only removal history"},
  {id: 16, problem: "Defending a bad previous choice", classification: MODEL_EVAL, safeguard: "honesty and correction eval"},
  {id: 17, problem: "Weak styling reasoning", classification: MODEL_EVAL, safeguard: "styling rationale eval"},
  {id: 18, problem: "Dominant color vs detail confusion", classification: MODEL_EVAL, safeguard: "visual-claim grounding eval"},
  {id: 19, problem: "Text and cards diverging", classification: DETERMINISTIC, safeguard: "single result + display ID validation"},
  {id: 20, problem: "Edits changing unrelated pieces", classification: DETERMINISTIC, safeguard: "edit-scope preservation validation"},
  {id: 21, problem: "Redundant or inconsistent weather wording", classification: MODEL_EVAL, safeguard: "weather-language coherence eval"},
  {id: 22, problem: "Mixing places, dates, or times", classification: DETERMINISTIC, safeguard: "weather provenance tuple"},
  {id: 23, problem: "Technical implementation language exposed", classification: MODEL_EVAL, safeguard: "user-language eval"},
  {id: 24, problem: "Mechanical conversational style", classification: MODEL_EVAL, safeguard: "natural Slovak persona eval"},
  {id: 25, problem: "Answering an old topic", classification: MODEL_EVAL, safeguard: "latest-turn relevance eval"},
  {id: 26, problem: "Missing decision/rejection/action memory", classification: DETERMINISTIC, safeguard: "canonical bounded conversation memory"},
  {id: 27, problem: "Validator strict on cosmetics, weak on advice", classification: DETERMINISTIC, safeguard: "four explicit validator error classes"},
  {id: 28, problem: "Multi-AI chains increase conflict/cost/latency", classification: DETERMINISTIC, safeguard: "one authoritative model result per turn"},
  {id: 29, problem: "Trivial messages routed to expensive reasoning", classification: DETERMINISTIC, safeguard: "deterministic greeting and pending paths"},
  {id: 30, problem: "Poor progress during long operations", classification: INTEGRATION, safeguard: "future UI/runtime progress events"},
]);

const MODEL_QUALITY_EVAL_SPECS_V2 = Object.freeze([
  {
    problemIds: [5],
    input: "No exact shopping result satisfies every preference.",
    relevantSessionState: "hard constraints, soft preferences, missing need, rejected options",
    expectedQualities: ["explains the blocker naturally", "offers one useful soft-constraint choice"],
    forbiddenBehavior: ["silent hard-constraint relaxation", "internal validator language"],
  },
  {
    problemIds: [16, 17],
    input: "These shoes were a bad recommendation for this route, weren't they?",
    relevantSessionState: "original item reason, technical terrain, weather, current outfit",
    expectedQualities: ["admits a poor recommendation when evidence supports it", "gives specific useful reasoning"],
    forbiddenBehavior: ["automatic defense of the old choice", "generic mechanical phrasing"],
  },
  {
    problemIds: [18],
    input: "Why do the shoes work with the outfit?",
    relevantSessionState: "primary color and accent-only canonical metadata",
    expectedQualities: ["distinguishes dominant color from a small detail"],
    forbiddenBehavior: ["invented logo, print, or placement"],
  },
  {
    problemIds: [21],
    input: "What weather are you dressing me for?",
    relevantSessionState: "one destination/date/time-window weather snapshot",
    expectedQualities: ["concise internally consistent weather explanation"],
    forbiddenBehavior: ["contradictory ranges", "irrelevant daily minimum"],
  },
  {
    problemIds: [23, 24, 25],
    input: "A rifle sú v poriadku?",
    relevantSessionState: "latest input, current outfit, prior warnings",
    expectedQualities: ["answers the latest question first", "sounds like a natural Slovak stylist"],
    forbiddenBehavior: ["fail-closed or validator terminology", "returning to an irrelevant old warning"],
  },
]);

module.exports = {
  DETERMINISTIC,
  INTEGRATION,
  MODEL_EVAL,
  MODEL_QUALITY_EVAL_SPECS_V2,
  PROBLEM_BACKLOG_V2,
};
