// functions/index.js

const { onRequest } = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");

// ---------------------------------------------------------------------------
// Pomocná funkcia – zavolá OpenAI chat model (gpt-4o-mini) cez HTTP
// ---------------------------------------------------------------------------
async function callOpenAiChat(prompt) {
  const apiKey = process.env.OPENAI_API_KEY;

  if (!apiKey) {
    logger.error("Chýba OPENAI_API_KEY v prostredí!");
    throw new Error("Server nemá nastavený OPENAI_API_KEY.");
  }

  const url = "https://api.openai.com/v1/chat/completions";

  const body = {
    model: "gpt-4o-mini",
    messages: [
      {
        role: "system",
        content:
          "Si profesionálny módny stylista. Odpovedaj po slovensky a vráť vždy ČISTÝ JSON so štruktúrou {\"text\": \"...\", \"outfit_images\": [\"...\"]}.",
      },
      {
        role: "user",
        content: prompt,
      },
    ],
    temperature: 0.8,
  };

  const response = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify(body),
  });

  if (!response.ok) {
    const errorText = await response.text();
    logger.error("OpenAI API error:", response.status, errorText);
    throw new Error(
      `OpenAI API vrátilo chybu ${response.status}: ${errorText}`
    );
  }

  const data = await response.json();
  const choice = data.choices && data.choices[0];
  const text = choice?.message?.content;

  if (!text) {
    throw new Error("OpenAI API nevrátilo žiaden text v odpovedi.");
  }

  return text;
}

// ---------------------------------------------------------------------------
// 1) „Analýza“ oblečenia – zatiaľ len textový mód (neposielame reálny obrázok)
// ---------------------------------------------------------------------------

exports.analyzeClothingImage = onRequest(
  {
    region: "us-east1",
    invoker: "public",
  },
  async (req, res) => {
    if (req.method !== "POST") {
      return res.status(405).send("Metóda nie je povolená. Použite POST.");
    }

    const { imageUrl } = req.body;

    if (!imageUrl) {
      return res.status(400).send("Chýba imageUrl v tele požiadavky.");
    }

    try {
      const prompt = `
Používateľ ti dá URL alebo textový popis obrázka s oblečením:
"${imageUrl}"

Na základe toho popíš kúsok oblečenia v ČISTOM JSON-e:

{
  "type": "mikina",
  "colors": ["čierna", "biela"],
  "style": ["streetwear", "casual"],
  "season": ["jeseň", "zima"],
  "occasions": ["bežný deň", "do mesta", "na voľný čas"],
  "patterns": ["logo"]
}

Odpovedaj len JSONom, žiadne vysvetlenia navyše.
`;

      const text = await callOpenAiChat(prompt);

      try {
        const jsonResponse = JSON.parse(text);
        return res.status(200).send(jsonResponse);
      } catch (e) {
        logger.error("OpenAI nevrátil platný JSON:", text);
        return res.status(200).send({
          rawText: text,
        });
      }
    } catch (error) {
      logger.error("Chyba pri analýze obrázka:", error);
      return res.status(500).send(
        "Chyba servera pri analýze obrázka. Detail: " +
          (error.message || String(error))
      );
    }
  }
);

// ---------------------------------------------------------------------------
// 2) CHAT S AI STYLISTOM – hlavná funkcia pre tvoj chat v appke
// ---------------------------------------------------------------------------

exports.chatWithStylist = onRequest(
  {
    region: "us-east1",
    invoker: "public",
  },
  async (req, res) => {
    if (req.method !== "POST") {
      return res.status(405).send("Metóda nie je povolená. Použite POST.");
    }

    const {
      wardrobe,
      userPreferences,
      location,
      weather,
      focusItem,
    } = req.body;

    // Podporujeme obidva názvy: userQuery aj userMessage
    const userQuery = req.body.userQuery || req.body.userMessage;

    if (!userQuery) {
      return res
        .status(400)
        .send("Chýba používateľská požiadavka (userQuery alebo userMessage).");
    }

    try {
      const systemInstruction = `
Si profesionálny módny stylista.

Tvoja úloha:
- pomáhať používateľovi vybrať outfity a kombinácie z jeho reálneho šatníka,
- zohľadniť jeho preferencie (obľúbené farby, štýly, zakázané kombinácie),
- brať do úvahy počasie a lokalitu, ak sú k dispozícii,
- ak je k dispozícii konkrétny kúsok (focusItem), sústreď sa naň.

Odpovedaj po slovensky, priateľsky, ale vecne a prakticky.
Nepíš príliš dlhé romány, radšej jasné a použiteľné tipy.

Výstup musí byť v ČISTOM JSON formáte:

{
  "text": "Sem daj detailnú odpoveď v slovenčine...",
  "outfit_images": [
    "https://.../obrazok1.jpg",
    "https://.../obrazok2.jpg"
  ]
}

Ak nemáš vhodné URL obrázkov, môžeš "outfit_images" vynechať alebo použiť prázdne pole.
`;

      const context = `
Používateľov šatník (wardrobe - kúsky, kategórie, farby, obrázky):
${JSON.stringify(wardrobe ?? [], null, 2)}

Používateľove preferencie:
${JSON.stringify(userPreferences ?? {}, null, 2)}

Lokalita a počasie:
${JSON.stringify({ location, weather }, null, 2)}

Kúsok v centre pozornosti (focusItem), ak existuje:
${JSON.stringify(focusItem ?? {}, null, 2)}
`;

      const fullPrompt = `
${systemInstruction}

${context}

Používateľská otázka:
${userQuery}
`;

      const text = await callOpenAiChat(fullPrompt);

      // Pokus o parsovanie JSONu
      try {
        const jsonResponse = JSON.parse(text);

        const replyText =
          jsonResponse.text ||
          "Stylista nemá momentálne žiadnu konkrétnu odpoveď.";

        const outfitImages = Array.isArray(jsonResponse.outfit_images)
          ? jsonResponse.outfit_images
          : [];

        return res.status(200).send({
          replyText,
          imageUrls: outfitImages,
        });
      } catch (e) {
        logger.error("OpenAI nevrátil platný JSON:", text);

        // Fallback – pošleme čistý text ako odpoveď
        return res.status(200).send({
          replyText: text,
          imageUrls: [],
        });
      }
    } catch (error) {
      logger.error("Chyba pri volaní OpenAI API:", error);
      return res.status(500).send(
        "Chyba servera pri komunikácii s AI stylistom. Detail: " +
          (error.message || String(error))
      );
    }
  }
);
