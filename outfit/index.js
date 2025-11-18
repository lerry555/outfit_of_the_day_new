const { onRequest } = require("firebase-functions/v2/https");
const { GoogleGenerativeAI } = require("@google/generative-ai");

// Nastavte API kľúč pre Gemini AI
const genAI = new GoogleGenerativeAI("AIzaSyAH0NfJ0YmE5laZOkjiEgjA4h2i6EJcloo");

exports.chatWithStylistNew = onRequest({ region: 'us-east1' }, async (req, res) => {
  if (req.method !== 'POST') {
    return res.status(405).send('Metóda nie je povolená. Použite POST.');
  }

  const { wardrobe, userPreferences, userQuery } = req.body;

  if (!userQuery) {
    return res.status(400).send('Chýba používateľská požiadavka (userQuery).');
  }

  try {
    const model = genAI.getGenerativeModel({ model: "gemini-pro-vision" });

    const systemInstruction = `Si profesionálny stylista. Tvojou úlohou je radiť používateľom s výberom outfitov.
                               Analyzuj ich šatník a preferencie, ktoré máš k dispozícii.
                               Odpovedaj priateľsky, profesionálne a užitočne.
                               Ak nevieš odpovedať na otázku, slušne to vysvetli.
                               Tvoja odpoveď musí byť v slovenčine a nesmie obsahovať žiadne Markdown formátovanie (napr. **hrubý text**, # nadpisy).`;

    const context = `Používateľov šatník:
                   ${JSON.stringify(wardrobe, null, 2)}

                   Používateľove preferencie (obľúbené farby, štýly, zakázané kombinácie):
                   ${JSON.stringify(userPreferences, null, 2)}`;

    const fullPrompt = `${systemInstruction}
                       ${context}
                       Používateľská otázka: ${userQuery}`;

    const result = await model.generateContent(fullPrompt);
    const response = result.response;
    const text = response.text();

    return res.status(200).send({
      response: text
    });

  } catch (error) {
    console.error("Chyba pri volaní Gemini API:", error);
    return res.status(500).send('Chyba servera pri komunikácii s AI stylistom.');
  }
});