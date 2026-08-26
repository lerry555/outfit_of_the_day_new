"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {groundingClarificationReply} = require("./grounding_reply");

test("correction grounding never repeats an unsupported location", () => {
  const reply = groundingClarificationReply(["destination", "activity"], true);
  assert.match(reply, /^Máš pravdu, to som si nemal domýšľať\./);
  assert.match(reply, /Kam sa chystáte/);
  assert.doesNotMatch(reply, /Martin|turistik|prechádzk/i);
});
