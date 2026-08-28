"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  SOL_AGENT_V2_MODEL,
  buildSolAgentV2Input,
  buildSolAgentV2Request,
  extractSolAgentV2Text,
  extractSolAgentV2WebMeta,
  createSolAgentV2Handler,
} = require("./sol_agent_v2");

test("Sol V2 request stays minimal and gives Sol autonomous web search", () => {
  const body = buildSolAgentV2Request({
    message: "O tri týždne idem na koncert. Čo si mám obliecť?",
    clientNow: "2026-08-29T00:20:00+02:00",
  });
  assert.equal(body.model, "gpt-5.6-sol");
  assert.equal(body.model, SOL_AGENT_V2_MODEL);
  assert.deepEqual(body.tools, [{type: "web_search", search_context_size: "low"}]);
  assert.equal(body.tool_choice, "auto");
  assert.equal(body.max_tool_calls, 3);
  assert.deepEqual(body.reasoning, {effort: "low"});
  assert.equal(body.store, true);
  assert.equal(body.previous_response_id, undefined);
  assert.equal(body.input[0].role, "user");
  assert.equal(body.input[0].content[0].type, "input_text");
  assert.match(body.instructions, /Aktuálny čas používateľa/);
});

test("Sol V2 uses native previous_response_id instead of resending chat history", () => {
  const body = buildSolAgentV2Request({
    message: "A čo keby pršalo?",
    previousResponseId: "resp_previous_123",
  });
  assert.equal(body.previous_response_id, "resp_previous_123");
  assert.equal(body.input.length, 1);
  assert.equal(body.input[0].content.length, 1);
  assert.equal(body.input[0].content[0].text, "A čo keby pršalo?");
});

test("Sol V2 sends an uploaded photo as native Responses image input", () => {
  const input = buildSolAgentV2Input({
    message: "Čo povieš na tento outfit?",
    imageUrl: "https://example.com/outfit.jpg",
  });
  assert.deepEqual(input[0].content, [
    {type: "input_text", text: "Čo povieš na tento outfit?"},
    {type: "input_image", image_url: "https://example.com/outfit.jpg", detail: "auto"},
  ]);
});

test("Sol V2 can handle an image-only turn", () => {
  const input = buildSolAgentV2Input({
    message: "",
    imageUrl: "https://example.com/outfit.jpg",
  });
  assert.equal(input[0].content[0].type, "input_text");
  assert.match(input[0].content[0].text, /fotku/i);
  assert.equal(input[0].content[1].type, "input_image");
});

test("Sol V2 extracts normal text and safe web metadata", () => {
  const response = {
    id: "resp_1",
    output: [
      {
        type: "web_search_call",
        action: {
          sources: [
            {url: "https://example.com/a"},
            {url: "https://www.example.com/b"},
            {url: "https://another.example.org/c"},
          ],
        },
      },
      {
        type: "message",
        content: [{type: "output_text", text: "Jasné, toto funguje."}],
      },
    ],
  };
  assert.equal(extractSolAgentV2Text(response), "Jasné, toto funguje.");
  assert.deepEqual(extractSolAgentV2WebMeta(response), {
    used: true,
    callCount: 1,
    sourceHosts: ["example.com", "another.example.org"],
  });
});

function fakeFirestore(initial = {}) {
  const state = {...initial};
  const writes = [];
  return {
    state,
    writes,
    collection(name) {
      assert.equal(name, "users");
      return {
        doc(uid) {
          return {
            collection(subcollection) {
              assert.equal(subcollection, "stylistAgentV2Sessions");
              return {
                doc(chatId) {
                  const key = `${uid}/${chatId}`;
                  return {
                    async get() {
                      return {
                        data: () => state[key] || {},
                      };
                    },
                    async set(value, options) {
                      writes.push({key, value, options});
                      state[key] = {...(state[key] || {}), ...value};
                    },
                  };
                },
              };
            },
          };
        },
      };
    },
  };
}

function fakeHttpsError(code, message) {
  const error = new Error(message);
  error.code = code;
  return error;
}

test("Sol V2 handler persists only the provider response id as conversation state", async () => {
  const db = fakeFirestore({"user_1/chat_1": {previousResponseId: "resp_old"}});
  let capturedRequest;
  const handler = createSolAgentV2Handler({
    db,
    resolveOpenAISecret: () => "test-secret",
    serverTimestamp: () => "SERVER_TIME",
    httpsError: fakeHttpsError,
    logger: {info() {}, warn() {}, error() {}},
    fetchImpl: async (url, request) => {
      capturedRequest = {url, request};
      return {
        ok: true,
        async json() {
          return {
            id: "resp_new",
            output: [{
              type: "message",
              content: [{type: "output_text", text: "Sedí. 😄"}],
            }],
          };
        },
      };
    },
  });

  const result = await handler({
    message: "A čo toto?",
    chatId: "chat_1",
  }, {auth: {uid: "user_1"}});

  const body = JSON.parse(capturedRequest.request.body);
  assert.equal(capturedRequest.url, "https://api.openai.com/v1/responses");
  assert.equal(body.previous_response_id, "resp_old");
  assert.equal(capturedRequest.request.headers.Authorization, "Bearer test-secret");
  assert.equal(result.reply, "Sedí. 😄");
  assert.equal(result.agentVersion, "sol_v2");
  assert.equal(db.state["user_1/chat_1"].previousResponseId, "resp_new");
  assert.equal(db.writes.length, 1);
  assert.equal(db.writes[0].value.updatedAt, "SERVER_TIME");
});

test("Sol V2 handler refuses to mix chats when chatId is missing", async () => {
  const handler = createSolAgentV2Handler({
    db: fakeFirestore(),
    resolveOpenAISecret: () => "test-secret",
    httpsError: fakeHttpsError,
    logger: {info() {}, warn() {}, error() {}},
    fetchImpl: async () => assert.fail("provider must not be called"),
  });

  await assert.rejects(
    handler({message: "Ahoj"}, {auth: {uid: "user_1"}}),
    (error) => error.code === "invalid-argument" && error.message === "chat_id_required",
  );
});
