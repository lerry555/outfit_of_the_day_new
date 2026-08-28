"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  buildConversationBrainResponsesBodyV1,
  extractConversationBrainResponseTextV1,
  extractConversationBrainWebResearchV1,
  safePublicResearchContext,
} = require("./openai_responses_web_search_v1");

test("Brain Responses body exposes conditional hosted web search", () => {
  const body = buildConversationBrainResponsesBodyV1({
    model: "gpt-5.6-terra",
    messages: [
      {role: "system", content: "system"},
      {role: "user", content: "unknown public concept"},
    ],
    maxOutputTokens: 777,
  });
  assert.equal(body.model, "gpt-5.6-terra");
  assert.deepEqual(body.tools, [{type: "web_search", search_context_size: "low"}]);
  assert.equal(body.tool_choice, "auto");
  // This is a per-Responses-request loop guard, not a lifetime chat quota.
  // Every subsequent user turn creates a fresh request with its own allowance.
  assert.equal(body.max_tool_calls, 3);
  assert.equal(body.text.format.type, "json_object");
  assert.equal(body.reasoning.effort, "low");
  assert.equal(body.max_output_tokens, 777);
  assert.equal(body.store, false);
  assert.deepEqual(body.include, ["web_search_call.action.sources"]);
});

test("Response extraction survives reasoning and web-search output items", () => {
  const response = {
    output: [
      {type: "reasoning", id: "r1"},
      {
        type: "web_search_call",
        action: {
          sources: [
            {title: "Source A", url: "https://example.com/a"},
            {title: "duplicate", url: "https://example.com/a"},
          ],
        },
      },
      {
        type: "message",
        content: [{
          type: "output_text",
          text: JSON.stringify({
            reply: "rozumiem",
            action: "chat",
            eventContext: {
              publicResearch: {
                performer: "Example Band",
                dressCode: {
                  id: "arena_concert",
                  labelSk: "koncert v hale",
                  formalityTarget: 3,
                  venueType: "indoor",
                },
                eventStartHour: 20,
                eventEndHour: 23,
                durationMinutes: 180,
              },
            },
          }),
          annotations: [
            {type: "url_citation", title: "Source B", url: "https://example.org/b"},
          ],
        }],
      },
    ],
  };
  assert.match(
    extractConversationBrainResponseTextV1(response),
    /"reply":"rozumiem"/,
  );
  const research = extractConversationBrainWebResearchV1(response);
  assert.equal(research.used, true);
  assert.equal(research.callCount, 1);
  assert.deepEqual(
    research.sources.map((source) => source.url),
    ["https://example.com/a", "https://example.org/b"],
  );
  assert.deepEqual(research.publicContext, {
    performer: "Example Band",
    dressCode: {
      formalityTarget: 3,
      id: "arena_concert",
      labelSk: "koncert v hale",
      venueType: "indoor_casual",
    },
    eventStartHour: 20,
    eventEndHour: 23,
    durationMinutes: 180,
  });
});

test("Public research context is impossible without an actual web-search call", () => {
  const research = extractConversationBrainWebResearchV1({
    output: [{
      type: "message",
      content: [{
        type: "output_text",
        text: JSON.stringify({
          eventContext: {
            publicResearch: {
              performer: "Hallucinated Band",
              dressCode: {formalityTarget: 9, venueType: "formal"},
            },
          },
        }),
      }],
    }],
  });
  assert.equal(research.used, false);
  assert.equal(research.callCount, 0);
  assert.deepEqual(research.sources, []);
  assert.equal(research.publicContext, undefined);
});

test("Public research sanitizer rejects unbounded or unsupported values", () => {
  assert.deepEqual(
    safePublicResearchContext({
      performer: " Example Artist ",
      dressCode: {
        formalityTarget: 99,
        venueType: "somewhere secret",
      },
      eventStartHour: 24,
      eventEndHour: -1,
      durationMinutes: 999999,
      locationLabel: "must never pass",
      dateKey: "2099-01-01",
    }),
    {performer: "Example Artist"},
  );
});

test("No web-search call is reported as unused", () => {
  const research = extractConversationBrainWebResearchV1({
    output: [{type: "message", content: [{type: "output_text", text: "{}"}]}],
  });
  assert.equal(research.used, false);
  assert.equal(research.callCount, 0);
  assert.deepEqual(research.sources, []);
});
