const { onRequest } = require("firebase-functions/v2/https");
const { GoogleGenerativeAI } = require("@google/generative-ai");
const { HttpsError } = require("firebase-functions/v2/https");

// Nastav API kľúč priamo.
const genAI = new GoogleGenerativeAI("AIzaSyBpGrQbmVnsCbBlwcZ6SsCI4DGxCVZ7HG0");

// NOVÁ FUNKCIA NA ANALÝZU OBRÁZKA
exports.analyzeClothingImage = onRequest({ region: 'us-east1', invoker: "public" }, async (req, res) => {
  if (req.method !== 'POST') {
    return res.status(405).send('Metóda nie je povolená. Použite POST.');
  }

  const { imageUrl } = req.body;

  if (!imageUrl) {
    return res.status(400).send('Chýba URL adresa obrázka (imageUrl).');
  }

  console.log("Prijatý URL obrázka na analýzu:", imageUrl);

  try {
    const model = genAI.getGenerativeModel({ model: "gemini-1.5-flash-latest" });

    const prompt = `Si špičkový asistent pre analýzu oblečenia. Tvojou úlohou je vyhodnotiť obrázok a určiť hlavné vlastnosti oblečenia.
                    V tvojej odpovedi použi prísne formátovanie JSON. Nepoužívaj žiadny Markdown ani dodatočný text, len JSON objekt.
                    Ak nevieš určiť niektorú hodnotu, nastav ju na "neznáme".
                    Príklad:
                    {
                      "category": "Tričká",
                      "color": ["modrá", "biela"],
                      "style": ["ležérny", "športový"],
                      "pattern": ["jednofarebný"],
                      "season": ["leto", "jar"]
                    }
                    Tvoje možné kategórie sú: Tričká, Košele, Blúzky, Svetre, Topy, Nohavice, Kraťasy, Sukne, Šortky, Topánky, Tenisky, Sandále, Lodičky, Bundy, Kabáty, Mikiny, Saká, Ostatné.`;

    const imagePart = {
      inlineData: {
        data: imageUrl,
        mimeType: "image/jpeg"
      },
    };

    const result = await model.generateContent([prompt, imagePart]);
    const response = result.response;
    const text = response.text();

    console.log("Odpoveď od AI (surový text):", text);

    try {
      const jsonResponse = JSON.parse(text);
      return res.status(200).json(jsonResponse);
    } catch (e) {
      console.error("Generative AI nevrátilo platný JSON:", text);
      return res.status(500).send('Chyba servera: AI nevrátila platný formát JSON. Surová odpoveď AI: ' + text);
    }

  } catch (error) {
    console.error("Chyba pri volaní Gemini Vision API:", error);
    return res.status(500).send('Chyba servera pri analýze obrázka. Podrobnosti: ' + error.message);
  }
});

// PÔVODNÁ FUNKCIA PRE CHAT SO STYLISTOM
exports.chatWithStylist = onRequest({ region: 'us-east1' }, async (req, res) => {
  if (req.method !== 'POST') {
    return res.status(405).send('Metóda nie je povolená. Použite POST.');
  }

  const { wardrobe, userPreferences, userQuery } = req.body;

  if (!userQuery) {
    return res.status(400).send('Chýba používateľská požiadavka (userQuery).');
  }

  try {
    const model = genAI.getGenerativeModel({ model: "gemini-1.5-flash-latest" });

    const systemInstruction = `Si profesionálny stylista. Tvojou úlohou je radiť používateľom s výberom outfitov na základe ich šatníka a preferencií.
                               Analyzuj dáta, ktoré obsahujú aj URL obrázkov k jednotlivým kusom oblečenia.
                               Odpovedaj priateľsky, profesionálne a užitočne.
                               Ak nevieš odpovedať, vysvetli to. Tvoja odpoveď musí byť v slovenčine.

                               Namiesto textu, ako "obleč si modré tričko", vytvor výstup vo formáte JSON, ktorý bude obsahovať priamo URL adresy obrázkov.
                               Tvoj výstup musí byť presne v tomto formáte:
                               {
                                 "text": "Tu je navrhovaný outfit, ktorý som pre teba pripravil. Perfektne sa hodí na dnešné počasie a tvoje preferencie!",
                                 "outfit_images": [
                                   "https://example.com/images/modre-tricko.jpg",
                                   "https://example.com/images/biele-rifle.jpg"
                                 ]
                               }
                               Ak nevieš vybrať oblečenie, vráť iba textovú odpoveď s vysvetlením, bez poľa "outfit_images".
                               Napríklad:
                               {
                                 "text": "Prepáč, ale s týmito informáciami ti neviem pomôcť. Skús mi poslať viac detailov o tvojom šatníku."
                               }`;

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

    // Pokus o parsovanie JSON odpovede
    try {
      const jsonResponse = JSON.parse(text);
      return res.status(200).send(jsonResponse);
    } catch (e) {
      // Ak parsovanie zlyhá, pošleme odpoveď ako obyčajný text
      console.error("Generative AI nevrátilo platný JSON:", text);
      return res.status(200).send({
        text: text
      });
    }

  } catch (error) {
    console.error("Chyba pri volaní Gemini API:", error);
    return res.status(500).send('Chyba servera pri komunikácii s AI stylistom.');
  }
});