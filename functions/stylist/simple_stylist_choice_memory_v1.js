"use strict";

// The existing client already preserves resultingOutfitItems in chat messages.
// Read their decision summaries, scoped to this user's latest matching outfit.
// No new collection or backend writes are needed.
function selectionReasonsFromChatV1(data, currentIds) {
  if (!Array.isArray(currentIds) || !currentIds.length ||
      new Set(currentIds).size !== currentIds.length) return [];
  const messages = Array.isArray(data?.messages) ? data.messages : [];
  for (let i = messages.length - 1; i >= 0; i -= 1) {
    const message = messages[i];
    if (message?.isUser !== false || !Array.isArray(message.resultingOutfitItems) ||
        !message.resultingOutfitItems.length) continue;
    const items = message.resultingOutfitItems;
    const ids = items.map((item) => item?.id);
    if (ids.length !== currentIds.length || new Set(ids).size !== ids.length ||
        !currentIds.every((id) => ids.includes(id))) return [];
    return items.filter((item) => typeof item.stylistSelectionReason === "string" &&
      item.stylistSelectionReason.trim()).map((item) => ({
      itemId: item.id, reason: item.stylistSelectionReason.trim().slice(0, 240),
    }));
  }
  return [];
}

async function loadSelectionReasonsV1({db, uid, chatId, currentIds, logger}) {
  if (typeof chatId !== "string" || !chatId.trim() || chatId.includes("/") ||
      chatId.length > 180 || !Array.isArray(currentIds) || !currentIds.length) return [];
  try {
    const snapshot = await db.collection("users").doc(uid)
      .collection("stylistChats").doc(chatId.trim()).get();
    return selectionReasonsFromChatV1(snapshot.data(), currentIds);
  } catch (_) {
    // A missing old chat or a read outage must not block a valid outfit turn.
    logger?.warn?.("SIMPLE_AGENT_CHOICE_MEMORY_UNAVAILABLE", {});
    return [];
  }
}

module.exports = {selectionReasonsFromChatV1, loadSelectionReasonsV1};
