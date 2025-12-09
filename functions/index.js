// functions/index.js - čistá verzia

const { onRequest } = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");

// Inicializácia Firebase Admin SDK (Firestore + Storage)
if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();
const storage = admin.storage();

// ---------------------------------------------------------------------------
// Pomocná funkcia – volanie OpenAI chat modelu (text)
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
      { role: "system", content: systemPrompt },
      { role: "user", content: userPrompt },
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
// Pomocná funkcia – počasie z OpenWeather
// ---------------------------------------------------------------------------
async function fetchWeatherFromOpenWeather(location, existingWeather) {
  if (existingWeather && Object.keys(existingWeather).length > 0) {
    return existingWeather;
  }

  const apiKey = process.env.OPENWEATHER_API_KEY;
  if (!apiKey) {
    logger.warn(
      "OPENWEATHER_API_KEY nie je nastavený – neviem načítať počasie."
    );
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
// Pomocné – zaradenie a zoradenie outfit_images
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

  items.sort((a, b) => {
    if (a.order === b.order) {
      return a.originalIndex - b.originalIndex;
    }
    return a.order - b.order;
  });

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
// 1) analyzeClothingImage – zatiaľ textový režim
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// 1) analyzeClothingImage – vizuálna analýza oblečenia (OpenAI vision)
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// 1) analyzeClothingImage – OpenAI vision + normalizácia farieb
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

    const apiKey = process.env.OPENAI_API_KEY;
    if (!apiKey) {
      logger.error("Chýba OPENAI_API_KEY v prostredí!");
      return res
        .status(500)
        .send("Server nemá nastavený OPENAI_API_KEY.");
    }

    try {
      const systemPrompt = `
Si profesionálny módny stylista a expert na rozpoznávanie oblečenia z fotografií.
Tvojou úlohou je analyzovať obrázok a vrátiť STRICTNÝ JSON podľa zadaného formátu,
bez akéhokoľvek textu okolo.

Používaj iba tieto farby (v slovenčine):
["biela","čierna","sivá","béžová","hnedá","modrá","tmavomodrá","svetlomodrá","červená","bordová","ružová","fialová","zelená","khaki","žltá","oranžová","zlatá","strieborná"].

────────────────────────────────────────────────────────
1) TYP OBLEČENIA – veľmi presné pravidlá
────────────────────────────────────────────────────────
- Tričko: krátky rukáv, tenšia látka, žiadna kapucňa.
- Dlhé tričko / longsleeve: dlhý rukáv, tenká látka, žiadna kapucňa.
- Mikina: dlhý rukáv, hrubší materiál, často kapucňa.
- Košeľa: golier + zapínanie.
- Nohavice: dlhé nohavice.
- Kraťasy: krátke nohavice.
- Rifle/džínsy: rifľovina, švy typické pre džínsy.
Vždy sa snaž určiť čo najpresnejší typ.

────────────────────────────────────────────────────────
2) FARBY – určuj IBA farbu látky (dominantnú)
────────────────────────────────────────────────────────
- Ignoruj farbu potlače (texty, logá, obrázky).
- Pri tričku, ktoré je čierne a má bielu potlač, farby = ["čierna"].
- Ak sú použité 2 materiálové farby, môžeš uviesť 1–2 najdominantnejšie.
- Nepíš farby, ktoré na odeve nie sú.

NORMALIZÁCIA ODTIEŇOV DO SLOVENSKÝCH NÁZVOV:
- burgundy, maroon, wine, dark red → "bordová"
- navy, midnight blue, dark blue, indigo → "tmavomodrá"
- sky blue, baby blue, light blue → "svetlomodrá"
- denim (džínsovina) → "modrá"
- olive, army, military green → "khaki"
- cream, ivory, off white, off-white → "béžová"
- tan, camel, sand, nude → "béžová"
- charcoal, anthracite → "sivá"
- silver, metallic, metallic grey → "strieborná"

Ak je odtieň medzi dvoma farbami, zvoľ najbližšiu z povoleného zoznamu farieb.

────────────────────────────────────────────────────────
3) PATTERN / VZOR (patterns)
────────────────────────────────────────────────────────
- Ak je na odeve text alebo logo → použi "textová potlač".
- Ak je úplne jednofarebný → "jednofarebné".
- Ak sú pruhy → "pruhované".
- Ak je káro / kocky → "káro".
- Ak je maskáč → "maskáčové".
- Ak je iná grafika → "grafická potlač".

────────────────────────────────────────────────────────
4) ŠTÝL (style)
────────────────────────────────────────────────────────
Používaj tieto štýly:
- "casual"
- "streetwear"
- "sport"
- "elegant"
- "smart casual"

Pravidlá:
- "casual" → pridaj pre väčšinu bežných tričiek, mikín, riflí a podobného oblečenia.
- "streetwear" → pridaj, ak je výrazná grafika, logo, urban / relaxed vzhľad.
  Ak pridáš "streetwear", VŽDY pridaj aj "casual".
- "sport" → iba pri zjavne športovom kúsku (funkčné materiály, športový dizajn).
- "elegant" alebo "smart casual" → len pri formálnejších košeliach, sakách, nohaviciach.
Nikdy nepridávaj protichodné štýly (napr. súčasne elegant a streetwear).

────────────────────────────────────────────────────────
5) SEZÓNA (season)
────────────────────────────────────────────────────────
Urči podľa typu:
- tričko → ["jar","leto","jeseň"]
- mikina → ["jeseň","zima","jar"]
- rifle/nohavice → ["celoročne"]
- tenisky → ["jar","leto","jeseň"]
- zimná obuv / hrubá bunda → ["zima"]
Ak si istý, že sa dá nosiť celý rok, môžeš použiť ["celoročne"].

────────────────────────────────────────────────────────
6) ZNAČKA (brand)
────────────────────────────────────────────────────────
- Ak vidíš logo alebo názov značky (napr. na štítku), uveď ho ako string.
- Ak značka nie je jasná, použi prázdny string "".

────────────────────────────────────────────────────────
7) VÝSTUP – MUSÍ BYŤ STRICTNÝ JSON:
────────────────────────────────────────────────────────
Vráť výhradne JSON objekt v tomto tvare:

{
  "type": "tričko",
  "colors": ["bordová"],
  "style": ["casual","streetwear"],
  "season": ["jar","leto","jeseň"],
  "occasions": ["bežný deň","voľný čas","do mesta"],
  "patterns": ["jednofarebné"],
  "brand": "Primark"
}

- "colors" musí obsahovať iba farby zo zoznamu na začiatku (v slovenčine).
- "style" musí byť zo sady ["casual","streetwear","sport","elegant","smart casual"].
- "season" a "occasions" vyplň logicky podľa typu.
- Nepridávaj žiaden text mimo JSON.
`;

      const openAiBody = {
        model: "gpt-4o",
        messages: [
          {
            role: "system",
            content: systemPrompt,
          },
          {
            role: "user",
            content: [
              {
                type: "text",
                text:
                  "Toto je fotka jedného kusu oblečenia z môjho šatníka. " +
                  "Analyzuj ju podľa pravidiel a vráť výhradne JSON objekt v požadovanom formáte.",
              },
              {
                type: "image_url",
                image_url: {
                  url: imageUrl,
                },
              },
            ],
          },
        ],
        temperature: 0.1,
      };

      const response = await fetch(
        "https://api.openai.com/v1/chat/completions",
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: "Bearer " + apiKey,
          },
          body: JSON.stringify(openAiBody),
        }
      );

      if (!response.ok) {
        const errorText = await response.text();
        logger.error(
          "OpenAI analyzeClothingImage error:",
          response.status,
          errorText
        );
        return res
          .status(500)
          .send(
            `OpenAI analyzeClothingImage error ${response.status}: ${errorText}`
          );
      }

      const data = await response.json();
      const choice = data.choices && data.choices[0];
      const text = choice?.message?.content;

      if (!text) {
        throw new Error(
          "OpenAI API nevrátilo žiaden text v odpovedi (analyzeClothingImage)."
        );
      }

      try {
        const jsonResponse = JSON.parse(text);
        return res.status(200).send(jsonResponse);
      } catch (e) {
        logger.error("analyzeClothingImage – neplatný JSON, raw:", text);
        return res.status(200).send({ rawText: text });
      }
    } catch (error) {
      logger.error("Chyba pri analyzeClothingImage:", error);
      return res.status(500).send(
        "Chyba servera pri analýze obrázka. Detail: " +
          (error.message || String(error))
      );
    }
  }
);



// ---------------------------------------------------------------------------
// 2) chatWithStylist – AI chat
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
- Reaguj na emócie používateľa.
- Nepredpokladaj nič, čo používateľ nepovedal.

Práca s počasím:
- Informácie o počasí máš v objekte "weather" v kontexte.
- Tento objekt "weather" už pripravil backend podľa používateľovej polohy (OpenWeather).
- Ak je "weather" definovaný a nie je prázdny objekt, BER TO TAK, že počasie poznáš.
- V takom prípade sa na počasie NEPÝTAJ, ale pracuj s tým, čo máš.
- Pýtať sa na počasie môžeš iba vtedy, keď je "weather" úplne prázdny alebo neexistuje.

Logika outfitov:
- Nepoužívaj duplikované kúsky (rovnaká imageUrl nesmie byť dvakrát).
- V jednom outfite vyber maximálne jedny topánky.
- Používaj výhradne kúsky z "wardrobe" – nevymýšľaj oblečenie, ktoré tam nie je.
- Každý kúsok môže mať pole "imageUrl" – pri outfite POUŽÍVAJ tieto URL.

Farby:
- Farby používaj iba vtedy, ak sú v dátach kúsku (napr. pole "colors", "color", "colorName").
- Ak farba chýba, opisuj bez konkrétnej farby alebo neutrálne (napr. "mikina").

Konzistencia:
- Najprv vyber konkrétne kúsky do outfitu.
- Pole "outfit_images" musí obsahovať URL práve tých kúskov, o ktorých píšeš v texte.
- Nespomínaj v texte bundu, ak žiadnu bundu do "outfit_images" nezaradíš.

Outfit images:
- Vráť "outfit_images" ako pole URL z "wardrobe".
- Backend ich ešte usporiada, ale ty tam nedávaj duplicity.

Formát:
- Odpovedaj LEN v JSON:
{
  "text": "odpoveď v slovenčine",
  "outfit_images": ["url1", "url2", ...]
}
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

// ---------------------------------------------------------------------------
// 3) processClothingImage – odrezanie pozadia cez ClipDrop (async, všetky await
//     sú PRÁVE TU vo vnútri funkcie)
// ---------------------------------------------------------------------------

exports.processClothingImage = onRequest(
  {
    region: "us-east1",
    invoker: "public",
  },
  async (req, res) => {
    if (req.method !== "POST") {
      return res.status(405).send("Použi POST.");
    }

    const { imageUrl, itemId, userId } = req.body;

    if (!imageUrl || !itemId || !userId) {
      return res
        .status(400)
        .send("Chýba imageUrl, itemId alebo userId v tele požiadavky.");
    }

    try {
      const clipApiKey = process.env.CLIPDROP_API_KEY;
      if (!clipApiKey) {
        throw new Error("Chýba CLIPDROP_API_KEY v prostredí.");
      }

      // 1) Stiahni pôvodný obrázok
      const originalResponse = await fetch(imageUrl);
      if (!originalResponse.ok) {
        const txt = await originalResponse.text();
        throw new Error("Nepodarilo sa stiahnuť obrázok: " + txt);
      }
      const originalBuffer = Buffer.from(
        await originalResponse.arrayBuffer()
      );

      // 2) Priprav form-data pre ClipDrop (pole 'image_file')
      const form = new FormData();
      const blob = new Blob([originalBuffer], { type: "image/jpeg" });
      form.append("image_file", blob, "input.jpg");

      // 3) Zavolaj ClipDrop Remove Background API
      const clipResponse = await fetch(
        "https://clipdrop-api.co/remove-background/v1",
        {
          method: "POST",
          headers: {
            "x-api-key": clipApiKey,
          },
          body: form,
        }
      );

      if (!clipResponse.ok) {
        const errorTxt = await clipResponse.text();
        throw new Error("ClipDrop error: " + errorTxt);
      }

      const cleanBuffer = Buffer.from(await clipResponse.arrayBuffer());

      // 4) Ulož vyrezaný obrázok do Storage
      const bucket = storage.bucket(); // default bucket
      const cleanPath = `users/${userId}/wardrobe_clean/${itemId}.png`;
      const file = bucket.file(cleanPath);

      await file.save(cleanBuffer, {
        contentType: "image/png",
        public: true,
      });

      const cleanImageUrl =
        `https://storage.googleapis.com/${bucket.name}/${cleanPath}`;

      // 5) Ulož cleanImageUrl k danému kusu v Firestore
      await db
        .collection("users")
        .doc(userId)
        .collection("wardrobe")
        .doc(itemId)
        .update({
          cleanImageUrl,
          bgRemoved: true,
        });

      return res.status(200).send({
        success: true,
        cleanImageUrl,
      });
    } catch (err) {
      logger.error("processClothingImage error:", err);
      return res.status(500).send("Chyba: " + (err.message || String(err)));
    }
  }
);
