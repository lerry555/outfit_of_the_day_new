"use strict";

function groundingClarificationReply(fields, wasCorrection) {
  const wanted = new Set((fields || []).map((value) => String(value || "")
    .trim().toLowerCase()));
  const prefix = wasCorrection ? "Máš pravdu, to som si nemal domýšľať. " : "";
  if (wanted.has("destination") && wanted.has("activity")) {
    return `${prefix}Kam sa chystáš a čo tam budeš približne robiť?`;
  }
  if (wanted.has("destination")) {
    return `${prefix}Kam sa chystáš? Podľa miesta vyberiem vhodné počasie aj outfit.`;
  }
  if (wanted.has("activity") || wanted.has("trip_scope")) {
    return `${prefix}Čo budeš na výlete približne robiť a pôjde o jeden deň alebo viac dní?`;
  }
  return `${prefix}Jasné 🙂 Ešte si potrebujem trochu upresniť plán, aby som ti nevybral outfit naslepo.`;
}

module.exports = {groundingClarificationReply};
