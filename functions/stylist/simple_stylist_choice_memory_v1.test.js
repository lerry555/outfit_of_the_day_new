"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {selectionReasonsFromChatV1, loadSelectionReasonsV1} = require("./simple_stylist_choice_memory_v1");

const outfit = [{id: "tee", stylistSelectionReason: "Neutral base."},
  {id: "jeans", stylistSelectionReason: "Chosen for the cool morning."}];
const assistant = (items) => ({isUser: false, resultingOutfitItems: items});

test("recorded reasons survive unrelated conversation and an ID order change", () => {
  const messages = [assistant(outfit), {isUser: true, text: "Thanks"},
    ...Array.from({length: 20}, () => ({isUser: false, text: "Hello"}))];
  assert.deepEqual(selectionReasonsFromChatV1({messages}, ["jeans", "tee"]), [
    {itemId: "tee", reason: "Neutral base."},
    {itemId: "jeans", reason: "Chosen for the cool morning."},
  ]);
});

test("a changed latest outfit cannot restore reasons from an older matching outfit", () => {
  assert.deepEqual(selectionReasonsFromChatV1({messages: [assistant(outfit),
    assistant([{id: "tee"}, {id: "shorts"}])]}, ["tee", "jeans"]), []);
  assert.deepEqual(selectionReasonsFromChatV1({messages: [assistant(outfit),
    assistant([{id: "tee"}, {id: "jeans"}])]}, ["tee", "jeans"]), []);
});

test("legacy chats and user-message metadata cannot invent recorded choices", () => {
  assert.deepEqual(selectionReasonsFromChatV1({messages: [{isUser: true,
    resultingOutfitItems: outfit}]}, ["tee", "jeans"]), []);
  assert.deepEqual(selectionReasonsFromChatV1({}, ["tee", "jeans"]), []);
  assert.deepEqual(selectionReasonsFromChatV1({messages: [assistant(outfit)]}, ["tee", "tee"]), []);
});

test("memory reads only the authenticated user's selected chat and fails open on read failure", async () => {
  const paths = [];
  const db = {collection(name) {paths.push(name); return this;},
    doc(id) {paths.push(id); return this;},
    async get() {return {data: () => ({messages: [assistant(outfit)]})};}};
  const args = {db, uid: "owner", chatId: "selected-chat", currentIds: ["tee", "jeans"]};
  assert.equal((await loadSelectionReasonsV1(args)).length, 2);
  assert.deepEqual(paths, ["users", "owner", "stylistChats", "selected-chat"]);
  paths.length = 0;
  assert.deepEqual(await loadSelectionReasonsV1({...args, chatId: "other/chat"}), []);
  assert.deepEqual(paths, []);
  db.get = async () => {throw new Error("unavailable");};
  assert.deepEqual(await loadSelectionReasonsV1(args), []);
});
