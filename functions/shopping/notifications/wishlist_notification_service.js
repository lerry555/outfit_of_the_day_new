"use strict";

const {
  groupedNotification,
  notificationForItem,
} = require("./wishlist_notification_templates");

const INVALID_TOKEN_CODES = new Set([
  "messaging/invalid-registration-token",
  "messaging/registration-token-not-registered",
]);

function createWishlistNotificationService({messaging, tokenStore, eventStore}) {
  if (!messaging || !tokenStore || !eventStore) {
    throw new Error("wishlist_notification_dependencies_required");
  }
  return {
    async deliverOwnerBatch(uid, itemEvents, {syncRunId = ""} = {}) {
      const notifications = itemEvents
        .map(({item, events}) => notificationForItem(item, events))
        .filter(Boolean);
      if (!notifications.length) return {status: "NO_DELIVERABLE_EVENTS"};
      const notification = groupedNotification(notifications, {syncRunId});
      const pendingIds = await eventStore.filterPending(notification.eventIds);
      if (!pendingIds.length) return {status: "ALREADY_DELIVERED"};
      const pending = new Set(pendingIds);
      const filteredItems = itemEvents.map(({item, events}) => ({
        item,
        events: events.filter((event) => pending.has(event.eventId)),
      })).filter(({events}) => events.length);
      const filteredNotifications = filteredItems
        .map(({item, events}) => notificationForItem(item, events))
        .filter(Boolean);
      if (!filteredNotifications.length) return {status: "ALREADY_DELIVERED"};
      const outgoing = groupedNotification(filteredNotifications, {syncRunId});
      const tokens = [...new Set(await tokenStore.getTokens(uid))].filter(Boolean);
      if (!tokens.length) {
        await eventStore.markSkipped(outgoing.eventIds, "NO_REGISTERED_TOKEN");
        return {status: "NO_TOKEN", eventCount: outgoing.eventIds.length};
      }
      try {
        const response = await messaging.sendEachForMulticast({
          tokens,
          notification: {title: outgoing.title, body: outgoing.body},
          data: Object.fromEntries(Object.entries(outgoing.data)
            .map(([key, value]) => [key, String(value)])),
          android: {
            priority: "high",
            notification: {channelId: "wishlist_updates"},
          },
        });
        const invalid = [];
        let accepted = 0;
        response.responses.forEach((result, index) => {
          if (result.success) {
            accepted++;
          } else if (INVALID_TOKEN_CODES.has(result.error?.code)) {
            invalid.push(tokens[index]);
          }
        });
        if (invalid.length) await tokenStore.removeTokens(uid, invalid);
        if (accepted > 0) {
          await eventStore.markDelivered(outgoing.eventIds, {
            acceptedAt: Date.now(),
            acceptedDeviceCount: accepted,
          });
          return {
            status: "ACCEPTED",
            acceptedDeviceCount: accepted,
            invalidTokenCount: invalid.length,
            eventCount: outgoing.eventIds.length,
            route: outgoing.data,
          };
        }
        await eventStore.markFailed(outgoing.eventIds, "FCM_NOT_ACCEPTED");
        return {status: "FAILED", invalidTokenCount: invalid.length};
      } catch (error) {
        await eventStore.markFailed(outgoing.eventIds,
          error?.code || "FCM_SEND_FAILED");
        return {status: "FAILED", errorCode: error?.code || "FCM_SEND_FAILED"};
      }
    },
  };
}

module.exports = {
  INVALID_TOKEN_CODES,
  createWishlistNotificationService,
};
