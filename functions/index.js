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
// 1) „Analýza“ oblečenia – zatiaľ textový mód (neposielame reálny obrázok)
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

    // Skúsime si doplniť počasie podľa polohy, ak nie je poslané
    const finalWeather = await fetchWeatherFromOpenWeather(location, weather);

    logger.info("chatWithStylist input:", {
      hasWardrobe: Array.isArray(wardrobe) && wardrobe.length > 0,
      location,
      hadWeatherFromClient: !!weather,
      hasFinalWeather: !!finalWeather,
    });

    // Podporujeme obidva názvy: userQuery aj userMessage
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
- Pri vysvetlení outfitu sa snaž použiť konkrétne informácie (napr. teplota, či prší, či fúka vietor), ak sú v "weather" dostupné.

Kedy navrhovať outfity:
- Outfity alebo konkrétne kombinácie navrhuj až vtedy, keď používateľ jasne naznačí, že chce pomoc s oblečením (napr. "čo si mám obliecť", "poradíš outfit", "pomôž mi s oblečením", "aké oblečenie na..." a podobne).
- Ak sa používateľ len rozpráva o bežných veciach (smalltalk), odpovedaj priateľsky ako kamarát a nespomínaj v KAŽDEJ správe, že mu vieš pomôcť s outfitom. Pripomeň to iba občas alebo keď to dáva zmysel.

Logika outfitov:
- Pri návrhu outfitu nikdy nepoužívaj duplikované kúsky (napr. dvoje rovnaké nohavice naraz).
- Konkrétny kúsok je definovaný napríklad jeho "id" alebo "imageUrl" – rovnaká "imageUrl" NESMIE byť v outfite dvakrát.
- Typický outfit má: vrch (top), spodok (bottom), obuv, voliteľne vrstvy (mikina, sveter, bunda) a doplnky.
- Ak dostaneš šatník (wardrobe), primárne používaj kúsky z neho.
- Nikdy nevymýšľaj nové oblečenie, ktoré v šatníku neexistuje. Používaj iba to, čo je v "wardrobe".
- Každý kúsok v šatníku môže mať okrem iného aj pole "imageUrl" – je to URL fotky daného oblečenia. Pri návrhu outfitu POUŽÍVAJ tieto URL.

Farby a opis:
- Farby nikdy nevymýšľaj.
- Ak má kúsok v dátach farby (napr. v poliach "colors", "color", "colorName"), opisuj ho podľa týchto farieb.
- Nesmieš povedať, že kúsok je napríklad "modrý", ak v jeho dátach farba neobsahuje "modrá".
- Ak nevieš farbu, radšej ju nešpecifikuj (napr. povedz "mikina" namiesto "modrá mikina").

Obrázky outfitu:
- Keď používateľ požiada o KONKRÉTNY outfit (napr. "porad mi čo si mám obliecť teraz vonka"), okrem textového vysvetlenia vráť aj pole "outfit_images".
- "outfit_images" musí byť pole URL obrázkov z používateľovho šatníka, zoradené v tomto poradí:
  1. čiapka (ak je),
  2. šál (ak je),
  3. bunda / kabát,
  4. mikina / sveter,
  5. tričko / košeľa,
  6. nohavice / rifle / tepláky,
  7. topánky,
  8. doplnky (napr. batoh, kabelka, čiapka s brmbolcom a pod.).
- Ak nejaký typ kúsku v šatníku nie je, jednoducho ho preskoč, ale poradie ostatných dodrž.
- Každá položka v "outfit_images" je čisté URL (string) na fotku daného kúsku.
- V "outfit_images" nesmie byť rovnaká URL dvakrát.
- Ak šatník (wardrobe) neobsahuje žiadne imageUrl, nechaj "outfit_images": [].

Vysvetlenie:
- Keď navrhneš outfit, vždy STRUČNE vysvetli, prečo ho odporúčaš – zohľadni počasie (ak je k dispozícii), typ udalosti, pohodlie, štýl a farby.
- Ak máš informácie o počasí, zmysluplne ich použi (napr. "vonku sú 2 °C a fúka, preto odporúčam...").
- Ak nemáš informácie o počasí (objekt "weather" je prázdny), nesťažuj sa na to. Jednoducho sa slušne spýtaj napríklad:
  "Povieš mi, prosím, aké je asi počasie (teplota, vietor, prší/neprší)?"
- Nepíš romány – stačí 3 až 6 viet praktického vysvetlenia.

Smalltalk:
- Ak sa používateľ pýta na bežné veci (deň, nálada, život), odpovedaj krátko a priateľsky.
- Môžeš mu občas pripomenúť, že mu vieš pomôcť aj s oblečením, ale nie stále.

Doplňujúce otázky:
- Ak nemáš dosť informácií na dobrý outfit, polož 1 až 3 doplňujúce otázky (napr. kam ideš, aký štýl chceš). Ak však máš v kontexte "weather", na počasie sa už NEPÝTAJ.

Formát odpovede:
- VŽDY odpovedaj len v čistom JSON formáte:
  {
    "text": "sem daj odpoveď v slovenčine",
    "outfit_images": ["url1", "url2", ...]
  }
- Aj pri smalltalku vyplň pole "text" a "outfit_images" môže byť prázdne pole.
- Nikdy nepridávaj žiadny text mimo JSON (žiadne vysvetlenia okolo, žiadne markdowny, žiadne komentáre mimo JSON).
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
