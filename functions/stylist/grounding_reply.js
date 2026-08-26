"use strict";

function groundingClarificationReply(fields, wasCorrection) {
  const wanted = new Set((fields || []).map((value) => String(value || "")
    .trim().toLowerCase()));
  const prefix = wasCorrection ? "Máš pravdu, to som si nemal domýšľať. " : "";
  if (wanted.has("destination") && wanted.has("activity")) {
    return `${prefix}Kam sa chystáte a čo tam budete približne robiť?`;
  }
  if (wanted.has("destination")) {
    return `${prefix}Kam sa chystáte? Podľa miesta vyberiem vhodné počasie aj outfit.`;
  }
  if (wanted.has("activity") || wanted.has("trip_scope")) {
    return `${prefix}Čo budete na výlete približne robiť a pôjde o jeden deň alebo viac dní?`;
  }
  return `${prefix}Jasné 🙂 Ešte si potrebujem trochu upresniť plán, aby som ti nevybral outfit naslepo.`;
}

module.exports = {groundingClarificationReply};
