// functions/index.js

const { onRequest } = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");

// ---------------------------------------------------------------------------
// Pomocná funkcia – volanie OpenAI chat modelu cez HTTP
// ---------------------------------------------------------------------------
async function callOpenAiChat(systemPrompt, userPrompt) {
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
        content: systemPrompt,
      },
      {
        role: "user",
        content: userPrompt,
      },
    ],
    temperature: 0.7,
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
// Pomocná funkcia – načítanie počasia z OpenWeather, ak treba
// ---------------------------------------------------------------------------
async function fetchWeatherFromOpenWeather(location, existingWeather) {
  // Ak už klient poslal validné počasie, necháme ho tak
  if (existingWeather && Object.keys(existingWeather).length > 0) {
    return existingWeather;
  }

  const apiKey = process.env.OPENWEATHER_API_KEY;
  if (!apiKey) {
    logger.warn("OPENWEATHER_API_KEY nie je nastavený – neviem načítať počasie.");
    return existingWeather || null;
  }

  if (!location || typeof location.lat !== "number" || typeof location.lon !== "number") {
    logger.warn("Chýba alebo je neplatná poloha. Počasie neviem zistiť.");
    return existingWeather || null;
  }

  try {
    const url =
      `https://api.openweathermap.org/data/2.5/weather` +
      `?lat=${location.lat}&lon=${location.lon}` +
      `&units=metric&lang=sk&appid=${apiKey}`;

    const response = await fetch(url);
    if (!response.ok) {
      const text = await response.text();
      logger.warn("OpenWeather API error:", response.status, text);
      return existingWeather || null;
    }

    const json = await response.json();
    const main = json.main || {};
    const weatherList = Array.isArray(json.weather) ? json.weather : [];
    const wind = json.wind || {};

    const weatherMain = weatherList[0]?.main || "";
    const weatherDescription = weatherList[0]?.description || "";

    const result = {
      tempC: main.temp,
      feelsLikeC: main.feels_like,
      humidity: main.humidity,
      weatherMain,
      weatherDescription,
      isRaining:
        weatherMain.toLowerCase().includes("rain") ||
        weatherDescription.toLowerCase().includes("dážď"),
      isSnowing:
        weatherMain.toLowerCase().includes("snow") ||
        weatherDescription.toLowerCase().includes("sneh"),
      windSpeed: wind.speed,
    };

    logger.info("Načítané počasie z OpenWeather:", result);
    return result;
  } catch (error) {
    logger.error("Chyba pri načítaní počasia z OpenWeather:", error);
    return existingWeather || null;
  }
}

// ---------------------------------------------------------------------------
// Pomocné funkcie – zoradenie a očistenie outfit_images podľa šatníka
// ---------------------------------------------------------------------------

function classifyWardrobeItem(url, wardrobe) {
  if (!Array.isArray(wardrobe)) {
    return { slot: "accessory", order: 8 };
  }

  const item = wardrobe.find(
    (piece) => piece && (piece.imageUrl === url || piece.imageUrl === String(url))
  );

  const text = [
    item?.mainCategory || "",
    item?.category || "",
    item?.subCategory || "",
    item?.type || "",
    item?.name || "",
  ]
    .join(" ")
    .toLowerCase();

  let slot = "accessory";
  let order = 8;

  if (text.includes("čiap") || text.includes("cap") || text.includes("hat")) {
    slot = "hat";
    order = 1;
  } else if (text.includes("šál") || text.includes("scarf")) {
    slot = "scarf";
    order = 2;
  } else if (
    text.includes("bunda") ||
    text.includes("kabát") ||
    text.includes("coat") ||
    text.includes("jacket")
  ) {
    slot = "jacket";
    order = 3;
  } else if (
    text.includes("mikina") ||
    text.includes("sveter") ||
    text.includes("hoodie") ||
    text.includes("sweater")
  ) {
    slot = "hoodie";
    order = 4;
  } else if (
    text.includes("tričko") ||
    text.includes("tricko") ||
    text.includes("košeľa") ||
    text.includes("kosela") ||
    text.includes("shirt") ||
    text.includes("t-shirt")
  ) {
    slot = "shirt";
    order = 5;
  } else if (
    text.includes("rifle") ||
    text.includes("nohavice") ||
    text.includes("tepláky") ||
    text.includes("teplaky") ||
    text.includes("jeans") ||
    text.includes("pants") ||
    text.includes("legíny") ||
    text.includes("leginy") ||
    text.includes("shorts")
  ) {
    slot = "pants";
    order = 6;
  } else if (
    text.includes("topánky") ||
    text.includes("topanky") ||
    text.includes("tenisky") ||
    text.includes("sneakers") ||
    text.includes("boty") ||
    text.includes("obuv") ||
    text.includes("shoes") ||
    text.includes("boots") ||
    text.includes("čižmy") ||
    text.includes("cizmy")
  ) {
    slot = "shoes";
    order = 7;
  }

  return { slot, order };
}

function normalizeOutfitImages(outfitImages, wardrobe) {
  if (!Array.isArray(outfitImages)) return [];

  // Odstránime prázdne a duplicitné URL
  const unique = Array.from(
    new Set(
      outfitImages
        .map((u) => (typeof u === "string" ? u.trim() : ""))
        .filter((u) => u.length > 0)
    )
  );

  const items = unique.map((url, index) => {
    const { slot, order } = classifyWardrobeItem(url, wardrobe);
    return { url, slot, order, originalIndex: index };
  });

  // Zoradíme podľa slotu (čiapka → šál → bunda → mikina → tričko → nohavice → topánky → doplnky)
  items.sort((a, b) => {
    if (a.order === b.order) {
      return a.originalIndex - b.originalIndex;
    }
    return a.order - b.order;
  });

  // Povolené maximálne jedny topánky
  const usedSlots = new Set();
  const result = [];

  for (const item of items) {
    if (item.slot === "shoes" && usedSlots.has("shoes")) {
      continue;
    }
    result.push(item.url);
    usedSlots.add(item.slot);
  }

  return result;
}

// ---------------------------------------------------------------------------
// 1) „Analýza“ oblečenia – zatiaľ textový mód
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
      const systemPrompt = `
Si módny stylista a expert na oblečenie.
Používateľ ti dá URL alebo textový popis obrázka s oblečením.
Tvojou úlohou je vrátiť ČISTÝ JSON, nič iné.

Formát JSON odpovede:
{
  "type": "mikina",
  "colors": ["čierna", "biela"],
  "style": ["streetwear", "casual"],
  "season": ["jeseň", "zima"],
  "occasions": ["bežný deň", "do mesta", "na voľný čas"],
  "patterns": ["logo"]
}

Odpovedaj LEN JSONom, bez textu mimo JSON.
`;

      const userPrompt = `
Používateľ ti posiela popis alebo URL oblečenia:
"${imageUrl}"

Na základe toho vyplň JSON podľa štruktúry vyššie.
`;

      const text = await callOpenAiChat(systemPrompt, userPrompt);

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

    const { wardrobe, userPreferences, location, weather, focusItem } = req.body;

    const finalWeather = await fetchWeatherFromOpenWeather(location, weather);

    logger.info("chatWithStylist input:", {
      hasWardrobe: Array.isArray(wardrobe) && wardrobe.length > 0,
      location,
      hadWeatherFromClient: !!weather,
      hasFinalWeather: !!finalWeather,
    });

    const userQuery = req.body.userQuery || req.body.userMessage;

    if (!userQuery) {
      return res
        .status(400)
        .send("Chýba používateľská požiadavka (userQuery alebo userMessage).");
    }

    try {
      const systemPrompt = `
Si profesionálny módny stylista v mobilnej aplikácii.

Tvoje správanie:
- Buď profesionálny, ale veľmi priateľský a ľudský.
- Reaguj na emócie používateľa (ak dá smajlík, pochop to; ak sa smeje, môžeš sa „zasmiať“ tiež).
- Môžeš používať jemný humor, ale nikdy neurážaj používateľa a nepreháňaj to.
- Nepredpokladaj nič, čo používateľ nepovedal.

Meno a komunikácia:
- Ak ti používateľ napíše, ako ťa chce volať (napr. "budem ťa volať Fero"), chápeš to tak, že je to prezývka pre teba. Túto prezývku môžeš pri ďalšej komunikácii používateľovi pripomenúť občas, nie v každej správe.
- Nezamieňaj si svoje meno s menom používateľa.
- Ak používateľ nepovie svoje meno, nijako ho neoslovuj menom.

Práca s počasím:
- Informácie o počasí máš v objekte "weather" v kontexte.
- Tento objekt "weather" už pripravil backend podľa používateľovej polohy (OpenWeather).
- Ak je "weather" v kontexte definovaný (nie je null, nie je undefined a nie je prázdny objekt {}), BER TO TAK, že počasie poznáš.
- V takom prípade NESMIEŠ sa pýtať používateľa, aké je počasie. Namiesto toho pracuj s dátami z objektu "weather".
- Pýtať sa na počasie môžeš iba vtedy, keď je "weather" úplne prázdny alebo neexistuje.

Kedy navrhovať outfity:
- Outfity alebo konkrétne kombinácie navrhuj až vtedy, keď používateľ jasne naznačí, že chce pomoc s oblečením.
- Ak sa používateľ len rozpráva o bežných veciach (smalltalk), odpovedaj priateľsky ako kamarát a nespomínaj v KAŽDEJ správe, že mu vieš pomôcť s outfitom.

Logika outfitov:
- Pri návrhu outfitu nikdy nepoužívaj duplikované kúsky.
- Konkrétny kúsok je definovaný napríklad jeho "id" alebo "imageUrl" – rovnaká "imageUrl" NESMIE byť v outfite dvakrát.
- V JEDNOM outfite vyber maximálne jedny topánky.
- Typický outfit má: vrch (top), spodok (bottom), obuv, voliteľne vrstvy (mikina, sveter, bunda) a doplnky.
- Ak dostaneš šatník (wardrobe), primárne používaj kúsky z neho.
- Nikdy nevymýšľaj nové oblečenie, ktoré v šatníku neexistuje. Používaj iba to, čo je v "wardrobe".
- Každý kúsok v šatníku môže mať okrem iného aj pole "imageUrl" – pri návrhu outfitu POUŽÍVAJ tieto URL.

Farby a opis:
- Farby POUŽÍVAJ len vtedy, ak ich vieš prečítať z dát šatníka.
- Môžu to byť polia "colors" (pole stringov), "color", "colorName" alebo podobné.
- Ak kúsok nemá v dátach žiadnu farbu, môžeš ho opísať bez farby (napr. "mikina") alebo neutrálne ("tmavšia mikina"), ale NESMIEŠ mu vymyslieť konkrétnu farbu ("modrá", "žltá", "červená" atď.).
- Nesmieš povedať, že kúsok je napríklad "modrý", ak jeho farby neobsahujú "modrá".

Konzistencia textu a obrázkov:
- Najprv si vyber konkrétny outfit z kúskov v "wardrobe".
- Potom vytvor pole "outfit_images" len z týchto kúskov.
- Nakoniec napíš TEXT tak, aby zodpovedal PRESNE tým kúskom, ktoré sú v "outfit_images".
- NESMIEŠ v texte spomenúť typ kúsku, ktorý nie je v "outfit_images" (napr. nemôžeš písať o bunde, ak žiadnu bundu do outfitu nezaradíš).

Obrázky outfitu:
- Keď používateľ požiada o KONKRÉTNY outfit, okrem textového vysvetlenia vráť aj pole "outfit_images".
- "outfit_images" musí byť pole URL obrázkov z používateľovho šatníka.
- Backend tieto obrázky ešte usporiada do finálneho poradia:
  1. čiapka,
  2. šál,
  3. bunda / kabát,
  4. mikina / sveter,
  5. tričko / košeľa,
  6. nohavice / rifle / tepláky,
  7. topánky,
  8. doplnky.
- V "outfit_images" nesmie byť rovnaká URL dvakrát.
- Ak šatník (wardrobe) neobsahuje žiadne imageUrl, nechaj "outfit_images": [].

Vysvetlenie:
- Keď navrhneš outfit, vždy STRUČNE vysvetli, prečo ho odporúčaš – zohľadni počasie, typ udalosti, pohodlie, štýl a farby (ale len tie, ktoré sú v dátach kúskov).
- Nepíš romány – stačí 3 až 6 viet praktického vysvetlenia.

Doplňujúce otázky:
- Ak nemáš dosť informácií na dobrý outfit, polož 1 až 3 doplňujúce otázky.
- Ak však máš v kontexte "weather", na počasie sa už NEPÝTAJ.

Formát odpovede:
- VŽDY odpovedaj len v čistom JSON formáte:
  {
    "text": "odpoveď v slovenčine",
    "outfit_images": ["url1", "url2", ...]
  }
- Nikdy nepridávaj žiadny text mimo JSON.
`;

      const context = `
Používateľov šatník (wardrobe - kúsky, kategórie, farby, obrázky):
${JSON.stringify(wardrobe ?? [], null, 2)}

Používateľove preferencie:
${JSON.stringify(userPreferences ?? {}, null, 2)}

Lokalita a počasie:
${JSON.stringify({ location, weather: finalWeather }, null, 2)}

Kúsok v centre pozornosti (focusItem), ak existuje:
${JSON.stringify(focusItem ?? {}, null, 2)}
`;

      const userPrompt = `
Toto je kontext o používateľovi a jeho šatníku:
${context}

Toto je jeho správa:
${userQuery}

Na základe system promptu a tohto kontextu vráť odpoveď VÝHRADNE v JSON formáte:
{
  "text": "odpoveď v slovenčine",
  "outfit_images": ["url1", "url2", "..."]
}
`;

      const text = await callOpenAiChat(systemPrompt, userPrompt);

      try {
        const jsonResponse = JSON.parse(text);

        const replyText =
          jsonResponse.text ||
          "Stylista nemá momentálne žiadnu konkrétnu odpoveď.";

        const rawOutfitImages = Array.isArray(jsonResponse.outfit_images)
          ? jsonResponse.outfit_images
          : [];

        const outfitImages = normalizeOutfitImages(rawOutfitImages, wardrobe);

        return res.status(200).send({
          replyText,
          imageUrls: outfitImages,
        });
      } catch (e) {
        logger.error("OpenAI nevrátil platný JSON:", text);

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
