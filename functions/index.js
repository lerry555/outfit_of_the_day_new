require("dotenv").config();
const functions = require("firebase-functions");
const admin = require("firebase-admin");
const https = require("https");

// 🔑 Kľúče z .env
const OPENAI_API_KEY = process.env.OPENAI_API_KEY;
const OPENWEATHER_API_KEY = process.env.OPENWEATHER_API_KEY || null;

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();

// ========== POMOCNÉ FUNKCIE ==========

function pickRandom(items) {
  if (!items || items.length === 0) return null;
  const idx = Math.floor(Math.random() * items.length);
  return items[idx];
}

function detectTemperatureInfo(userQuery) {
  const text = (userQuery || "").toLowerCase();
  let temp = null;

  // Skús nájsť číslo + °C
  const tempMatch =
    text.match(/(-?\d+)\s*(?:°|stupn|c\b)/) ||
    text.match(/(-?\d+)\s*(?:\s*°?\s*c)/);

  if (tempMatch && tempMatch[1]) {
    temp = parseInt(tempMatch[1], 10);
  } else {
    const numMatch = text.match(/(-?\d{1,2})\b/);
    if (numMatch && numMatch[1]) {
      const candidate = parseInt(numMatch[1], 10);
      if (candidate >= -40 && candidate <= 50) {
        temp = candidate;
      }
    }
  }

  let category = "unknown";

  if (temp !== null) {
    if (temp <= 5) category = "cold";
    else if (temp <= 15) category = "cool";
    else if (temp <= 25) category = "warm";
    else category = "hot";
  } else {
    if (text.includes("zima") || text.includes("mrzne") || text.includes("mráz")) {
      category = "cold";
    } else if (text.includes("teplo") || text.includes("horúco") || text.includes("leto")) {
      category = "hot";
    } else if (text.includes("chladno") || text.includes("jar") || text.includes("jeseň")) {
      category = "cool";
    }
  }

  return { temp, category };
}

function detectOccasion(userQuery) {
  const text = (userQuery || "").toLowerCase();

  let occasion = "unknown";
  let stylePreference = "any";
  let description = "";

  if (text.includes("rande") || text.includes("date")) {
    occasion = "date";
    stylePreference = "elegant";
    description = "Vyzerá to, že ideš na rande – zvolím trochu elegantnejší outfit.";
  } else if (
    text.includes("svokra") ||
    text.includes("svokre") ||
    text.includes("svokry") ||
    text.includes("rodina") ||
    text.includes("navštevu") ||
    text.includes("navstevu")
  ) {
    occasion = "family";
    stylePreference = "elegant";
    description =
      "Vyzerá to na rodinnú/serióznejšiu návštevu – skúsim zvoliť slušnejší outfit.";
  } else if (
    text.includes("kamoš") ||
    text.includes("kamos") ||
    text.includes("kamarát") ||
    text.includes("kamarat") ||
    text.includes("pivo") ||
    text.includes("bar") ||
    text.includes("von") ||
    text.includes("prechádzku") ||
    text.includes("prechadzku")
  ) {
    occasion = "friends";
    stylePreference = "casual";
    description =
      "Chápem, že ideš len tak von s kamarátmi – zvolím skôr voľnejší, pohodlný štýl.";
  } else if (
    text.includes("práca") ||
    text.includes("pracu") ||
    text.includes("do práce") ||
    text.includes("do prace") ||
    text.includes("office") ||
    text.includes("pracov")
  ) {
    occasion = "work";
    stylePreference = "elegant";
    description =
      "Vidím, že ideš niekam pracovne – zvolím skôr upravenejší outfit.";
  } else if (
    text.includes("fitko") ||
    text.includes("gym") ||
    text.includes("cvičiť") ||
    text.includes("cvicit") ||
    text.includes("beh") ||
    text.includes("behat") ||
    text.includes("workout") ||
    text.includes("futbal") ||
    text.includes("basket")
  ) {
    occasion = "sport";
    stylePreference = "sporty";
    description =
      "Vyzerá to na športovú aktivitu – uprednostním športové kúsky.";
  } else if (
    text.includes("party") ||
    text.includes("oslava") ||
    text.includes("diskotéka") ||
    text.includes("diskoteka") ||
    text.includes("klub") ||
    text.includes("club")
  ) {
    occasion = "party";
    stylePreference = "casual";
    description =
      "Ideš na párty/oslavu – outfit môže byť trochu výraznejší a uvoľnený.";
  }

  return { occasion, stylePreference, description };
}

function isOutfitRequest(userQuery) {
  const text = (userQuery || "").toLowerCase().trim();
  if (!text) return false;

  const outfitWords = [
    "outfit",
    "obleč",
    "oblec",
    "oblečenie",
    "oblecenie",
    "čo si mám",
    "co si mam",
    "čo na seba",
    "co na seba",
    "idem von",
    "idem do",
    "idem na",
    "idem do práce",
    "idem na rande",
    "idem do mesta",
    "večer idem",
    "vecer idem",
    "čo si mám obliecť",
    "co si mam obliect",
    "čo si dať na seba",
    "co si dat na seba",
    "práca",
    "pracu",
    "fitko",
    "gym",
    "rande",
    "svokra",
    "svokre",
    "svokry",
    "zima",
    "teplo",
    "chladno",
    "mrzne",
    "je vonku",
  ];

  if (outfitWords.some((w) => text.includes(w))) {
    return true;
  }

  if (/-?\d{1,2}/.test(text)) {
    return true;
  }

  return false;
}

function getStyleText(item) {
  const styleField = item.style;
  if (Array.isArray(styleField)) {
    return styleField.join(" ").toLowerCase();
  }
  if (typeof styleField === "string") {
    return styleField.toLowerCase();
  }
  return "";
}

function pickByStylePreference(items, stylePreference) {
  if (!items || items.length === 0) return null;
  if (!stylePreference || stylePreference === "any") {
    return pickRandom(items);
  }

  const preferredKeywords = [];
  const avoidKeywords = [];

  if (stylePreference === "casual") {
    preferredKeywords.push(
      "casual",
      "street",
      "ležér",
      "lezer",
      "volno",
      "streetwear"
    );
    avoidKeywords.push("elegant", "business", "formal");
  } else if (stylePreference === "elegant") {
    preferredKeywords.push(
      "elegant",
      "business",
      "formal",
      "smart",
      "košeľ",
      "kosel",
      "office"
    );
  } else if (stylePreference === "sporty") {
    preferredKeywords.push(
      "sport",
      "šport",
      "sporty",
      "gym",
      "fitness",
      "workout",
      "running"
    );
  }

  const matching = [];
  const neutral = [];
  const avoid = [];

  for (const item of items) {
    const styleText = getStyleText(item);
    if (!styleText) {
      neutral.push(item);
      continue;
    }

    const hasPreferred = preferredKeywords.some((kw) =>
      styleText.includes(kw)
    );
    const hasAvoid = avoidKeywords.some((kw) => styleText.includes(kw));

    if (hasPreferred && !hasAvoid) {
      matching.push(item);
    } else if (hasAvoid && !hasPreferred) {
      avoid.push(item);
    } else {
      neutral.push(item);
    }
  }

  if (matching.length > 0) return pickRandom(matching);
  if (neutral.length > 0) return pickRandom(neutral);
  return pickRandom(avoid.length > 0 ? avoid : items);
}

// ========== POČASIE – OpenWeather ==========

function mapTempToCategory(tempCelsius) {
  if (tempCelsius <= 5) return "cold";
  if (tempCelsius <= 15) return "cool";
  if (tempCelsius <= 25) return "warm";
  return "hot";
}

function fetchWeatherFromOpenWeather(lat, lon) {
  return new Promise((resolve, reject) => {
    const apiKey = OPENWEATHER_API_KEY;
    if (!apiKey) {
      console.warn("OPENWEATHER_API_KEY nie je nastavený");
      return resolve(null);
    }
    if (typeof lat !== "number" || typeof lon !== "number") {
      console.warn("Latitude/longitude nie sú korektné čísla");
      return resolve(null);
    }

    const url = `/data/2.5/weather?lat=${lat}&lon=${lon}&units=metric&appid=${apiKey}`;

    const options = {
      hostname: "api.openweathermap.org",
      path: url,
      method: "GET",
    };

    const req = https.request(options, (res) => {
      let data = "";

      res.on("data", (chunk) => {
        data += chunk;
      });

      res.on("end", () => {
        try {
          if (res.statusCode < 200 || res.statusCode >= 300) {
            console.error("OpenWeather error:", res.statusCode, data);
            return resolve(null);
          }
          const json = JSON.parse(data);
          const temp =
            json.main && typeof json.main.temp === "number"
              ? json.main.temp
              : null;
          const feelsLike =
            json.main && typeof json.main.feels_like === "number"
              ? json.main.feels_like
              : temp;
          const weatherMain =
            Array.isArray(json.weather) && json.weather[0]
              ? json.weather[0].main
              : null;

          const tempToUse = feelsLike != null ? feelsLike : temp;
          const tempCategory =
            tempToUse != null ? mapTempToCategory(tempToUse) : "unknown";

          resolve({
            temp: tempToUse,
            tempCategory,
            raw: json,
            weatherMain,
          });
        } catch (e) {
          console.error("Chyba pri parsovaní OpenWeather:", e);
          resolve(null);
        }
      });
    });

    req.on("error", (err) => {
      console.error("Chyba pri volaní OpenWeather:", err);
      resolve(null);
    });

    req.end();
  });
}

// ========== KONVERZÁCIA – pomocná funkcia ==========

function convertHistoryToOpenAIMessages(history) {
  if (!Array.isArray(history)) return [];
  return history
    .map((h) => {
      const role = h.role === "assistant" ? "assistant" : "user";
      const content =
        typeof h.content === "string" ? h.content.trim() : "";
      if (!content) return null;
      return { role, content };
    })
    .filter((x) => x !== null);
}

// ===== OpenAI volanie cez HTTPS =====

async function callOpenAI(openaiKey, messages) {
  const requestBody = JSON.stringify({
    model: "gpt-4.1-mini",
    messages,
    temperature: 0.7,
  });

  const options = {
    hostname: "api.openai.com",
    path: "/v1/chat/completions",
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${openaiKey}`,
      "Content-Length": Buffer.byteLength(requestBody),
    },
  };

  return new Promise((resolve, reject) => {
    const req = https.request(options, (res) => {
      let data = "";

      res.on("data", (chunk) => {
        data += chunk;
      });

      res.on("end", () => {
        if (res.statusCode < 200 || res.statusCode >= 300) {
          return reject(
            new Error(`OpenAI API error: ${res.statusCode} - ${data}`)
          );
        }
        try {
          const json = JSON.parse(data);
          const content =
            json.choices &&
            json.choices[0] &&
            json.choices[0].message &&
            json.choices[0].message.content;
          if (!content) {
            return reject(new Error("Empty response from OpenAI"));
          }
          resolve(content.trim());
        } catch (e) {
          reject(e);
        }
      });
    });

    req.on("error", (err) => {
      reject(err);
    });

    req.write(requestBody);
    req.end();
  });
}

// =======================
// 1) AI stylista zo šatníka
// =======================

exports.chatWithStylist = functions.https.onRequest(async (req, res) => {
  try {
    if (req.method !== "POST") {
      return res.status(405).json({
        text: "Použi POST metódu.",
        outfit_images: [],
      });
    }

    const body = req.body || {};
    const userQuery = body.userQuery || "";
    const wardrobe = Array.isArray(body.wardrobe) ? body.wardrobe : [];
    const userPreferences = body.userPreferences || {};
    const location = body.location || {};
    const history = Array.isArray(body.history) ? body.history : [];

    console.log("➡️ userQuery:", userQuery);
    console.log("➡️ wardrobe length:", wardrobe.length);
    console.log("➡️ userPreferences:", userPreferences);
    console.log("➡️ location:", location);
    console.log("➡️ history length:", history.length);

    const historyMessages = convertHistoryToOpenAIMessages(history);
    const openaiKey = OPENAI_API_KEY || null;

    const trimmed = userQuery.trim();
    if (!trimmed) {
      return res.status(200).json({
        text:
          "Ahoj! 👋 Som tvoj AI stylista. Napíš mi, kam ideš (napr. rande, práca, von s kamarátmi) " +
          "a aké je približne počasie, a vymyslím ti outfit z tvojho šatníka.",
        outfit_images: [],
      });
    }

    // === 0) SMALL TALK MOD ===
    if (!isOutfitRequest(userQuery)) {
      if (!openaiKey) {
        return res.status(500).json({
          text: "Na serveri nie je nastavený OPENAI_API_KEY.",
          outfit_images: [],
        });
      }

      try {
        const systemMessage = {
          role: "system",
          content:
            "Si priateľský módny stylista, ktorý komunikuje po slovensky. " +
            "Používateľ sa s tebou môže baviť aj nezáväzne (small talk), " +
            "ale vždy zostaň v úlohe kamoša-stylistu. Odpovedaj krátko (2–5 viet), " +
            "môžeš použiť emoji, ale s mierou. Využívaj predošlú konverzáciu, " +
            "ktorú dostaneš v histórii. Aplikácia zobrazuje fotky kúskov nad chatom, " +
            "takže nikdy nepíš, že nevieš ukázať obrázok – radšej sa odvolaj na kúsky, ktoré vidí používateľ.",
        };

        const aiText = await callOpenAI(openaiKey, [
          systemMessage,
          ...historyMessages,
          {
            role: "user",
            content: userQuery,
          },
        ]);

        return res.status(200).json({
          text: aiText,
          outfit_images: [],
        });
      } catch (err) {
        console.error("OpenAI small talk error:", err);
        return res.status(200).json({
          text: `Chyba pri volaní OpenAI (small talk): ${
            err.message || String(err)
          }`,
          outfit_images: [],
        });
      }
    }

    // === 1) OUTFIT MOD ===

    // 1) Skús získať počasie z polohy
    let temp = null;
    let tempCategory = "unknown";

    let weatherInfo = null;
    const lat =
      typeof location.latitude === "number" ? location.latitude : null;
    const lon =
      typeof location.longitude === "number" ? location.longitude : null;

    if (lat != null && lon != null) {
      try {
        weatherInfo = await fetchWeatherFromOpenWeather(lat, lon);
        if (weatherInfo && typeof weatherInfo.temp === "number") {
          temp = Math.round(weatherInfo.temp);
          tempCategory = weatherInfo.tempCategory || "unknown";
          console.log(
            "➡️ OpenWeather – temp:",
            temp,
            "category:",
            tempCategory
          );
        }
      } catch (err) {
        console.error("Chyba pri fetchWeatherFromOpenWeather:", err);
      }
    }

    // 2) Ak sa nepodarí – skús odhadnúť z textu
    if (temp == null || tempCategory === "unknown") {
      const detected = detectTemperatureInfo(userQuery);
      temp = detected.temp;
      tempCategory = detected.category;
    }

    const { occasion, stylePreference, description: occasionDescription } =
      detectOccasion(userQuery);

    console.log("➡️ temperature info:", temp, tempCategory);
    console.log("➡️ occasion info:", occasion, stylePreference);

    // Filtrovanie šatníka – iba čisté veci
    const cleanWardrobe = wardrobe.filter((item) => item.isClean !== false);

    // TOP (vrchy)
    const tops = cleanWardrobe.filter((item) => {
      const c = (item.category || "").toString().toLowerCase();
      return (
        c.includes("tri") ||
        c.includes("shirt") ||
        c.includes("koše") ||
        c.includes("mikina") ||
        c.includes("mikiny") ||
        c.includes("sveter") ||
        c.includes("blúzka") ||
        c.includes("bluzka")
      );
    });

    // BOTTOM (spodky)
    const allBottoms = cleanWardrobe.filter((item) => {
      const c = (item.category || "").toString().toLowerCase();
      return (
        c.includes("nohavice") ||
        c.includes("rifle") ||
        c.includes("kraťasy") ||
        c.includes("kratasy") ||
        c.includes("šortky") ||
        c.includes("sortky") ||
        c.includes("sukňa") ||
        c.includes("sukna") ||
        c.includes("pants") ||
        c.includes("jeans")
      );
    });

    const longBottoms = allBottoms.filter((item) => {
      const c = (item.category || "").toString().toLowerCase();
      return (
        c.includes("nohavice") ||
        c.includes("rifle") ||
        c.includes("jeans") ||
        c.includes("tepláky") ||
        c.includes("teplaky")
      );
    });

    const shortBottoms = allBottoms.filter((item) => {
      const c = (item.category || "").toString().toLowerCase();
      return (
        c.includes("kraťasy") ||
        c.includes("kratasy") ||
        c.includes("šortky") ||
        c.includes("sortky") ||
        c.includes("sukňa") ||
        c.includes("sukna")
      );
    });

    // SHOES (topánky)
    const allShoes = cleanWardrobe.filter((item) => {
      const c = (item.category || "").toString().toLowerCase();
      return (
        c.includes("topánky") ||
        c.includes("topanky") ||
        c.includes("tenisky") ||
        c.includes("sneakers") ||
        c.includes("boty") ||
        c.includes("čižmy") ||
        c.includes("cizmy") ||
        c.includes("sandále") ||
        c.includes("sandale") ||
        c.includes("šľapky") ||
        c.includes("slapky") ||
        c.includes("lodičky") ||
        c.includes("lodicky") ||
        c.includes("shoes")
      );
    });

    const warmShoes = allShoes.filter((item) => {
      const c = (item.category || "").toString().toLowerCase();
      return (
        c.includes("čižmy") ||
        c.includes("cizmy") ||
        c.includes("tenisky") ||
        c.includes("sneakers") ||
        c.includes("topánky") ||
        c.includes("topanky") ||
        c.includes("boty")
      );
    });

    const summerShoes = allShoes.filter((item) => {
      const c = (item.category || "").toString().toLowerCase();
      return (
        c.includes("sandále") ||
        c.includes("sandale") ||
        c.includes("šľapky") ||
        c.includes("slapky") ||
        c.includes("lodičky") ||
        c.includes("lodicky")
      );
    });

    // OUTERWEAR (bundy, kabáty)
    const outerwearAll = cleanWardrobe.filter((item) => {
      const c = (item.category || "").toString().toLowerCase();
      return (
        c.includes("bunda") ||
        c.includes("bundy") ||
        c.includes("kabát") ||
        c.includes("kabat") ||
        c.includes("kabátik") ||
        c.includes("sako") ||
        c.includes("coat") ||
        c.includes("jacket")
      );
    });

    // Výber jednotlivých kúskov podľa štýlu a počasia
    const pickedTop = pickByStylePreference(tops, stylePreference);

    let bottomPool = allBottoms;
    if (tempCategory === "cold" || tempCategory === "cool") {
      bottomPool = longBottoms.length > 0 ? longBottoms : allBottoms;
    } else if (tempCategory === "hot") {
      bottomPool = shortBottoms.length > 0 ? shortBottoms : allBottoms;
    }
    const pickedBottom = pickByStylePreference(bottomPool, stylePreference);

    let shoesPool = allShoes;
    if (tempCategory === "cold" || tempCategory === "cool") {
      shoesPool = warmShoes.length > 0 ? warmShoes : allShoes;
    } else if (tempCategory === "hot") {
      shoesPool = summerShoes.length > 0 ? summerShoes : allShoes;
    }
    const pickedShoes = pickByStylePreference(shoesPool, stylePreference);

    let pickedOuter = null;
    if (tempCategory === "cold" || tempCategory === "cool") {
      pickedOuter = pickByStylePreference(outerwearAll, stylePreference);
    }

    // Poradie objektov pre AI a text: top, bottom, shoes, outer
    const chosenItems = [];
    if (pickedTop) chosenItems.push(pickedTop);
    if (pickedBottom) chosenItems.push(pickedBottom);
    if (pickedShoes) chosenItems.push(pickedShoes);
    if (pickedOuter) chosenItems.push(pickedOuter);

    // Obrázky – BUNDA PRVÁ, potom vrch, spodok, topánky
    const outfitImages = [];
    if (pickedOuter && pickedOuter.imageUrl) outfitImages.push(pickedOuter.imageUrl);
    if (pickedTop && pickedTop.imageUrl) outfitImages.push(pickedTop.imageUrl);
    if (pickedBottom && pickedBottom.imageUrl) outfitImages.push(pickedBottom.imageUrl);
    if (pickedShoes && pickedShoes.imageUrl) outfitImages.push(pickedShoes.imageUrl);

    let fallbackText = "";

    if (cleanWardrobe.length === 0) {
      fallbackText =
        "Pozrel som sa do tvojho šatníka, ale nenašiel som žiadne použiteľné kúsky (možno sú všetky označené ako špinavé alebo šatník je prázdny). Skús pridať alebo označiť nejaké oblečenie ako čisté 🙂";
    } else if (chosenItems.length === 0) {
      fallbackText =
        "Pozrel som sa do tvojho šatníka, ale neviem nájsť kompletný outfit (vrch, spodok, topánky...). Skús skontrolovať, či máš v šatníku uložené tričká, nohavice a topánky.";
    } else {
      fallbackText += `Píšeš: "${userQuery}".\n`;

      if (temp !== null) {
        fallbackText += `Rozumiem, že vonku je približne ${temp} °C (${tempCategory}).\n`;
      } else if (tempCategory !== "unknown") {
        if (tempCategory === "cold")
          fallbackText += "Rozumiem, že je vonku zima.\n";
        if (tempCategory === "cool")
          fallbackText += "Rozumiem, že je vonku skôr chladnejšie.\n";
        if (tempCategory === "warm")
          fallbackText += "Vyzerá to na príjemné teplé počasie.\n";
        if (tempCategory === "hot")
          fallbackText += "Vyzerá to, že je vonku poriadne teplo.\n";
      }

      if (occasionDescription) {
        fallbackText += occasionDescription + "\n";
      }

      fallbackText += `Pozrel som sa do tvojho šatníka a našiel som ${cleanWardrobe.length} čistých kúskov.\n\n`;
      fallbackText += "Navrhujem tento outfit:\n";

      const describe = (item, label) => {
        if (!item) return "";
        const category = item.category || label;
        const color = item.color || "";
        const styleText = getStyleText(item);
        let line = `• ${label}: ${category}`;
        if (color && Array.isArray(color)) {
          line += `, farba: ${color.join(", ")}`;
        } else if (color && typeof color === "string") {
          line += `, farba: ${color}`;
        }
        if (styleText) line += `, štýl: ${styleText}`;
        return line + "\n";
      };

      fallbackText += describe(pickedTop, "vrch");
      fallbackText += describe(pickedBottom, "spodok");
      fallbackText += describe(pickedShoes, "topánky");
      if (pickedOuter) {
        fallbackText += describe(pickedOuter, "vrchná vrstva");
      }

      if (outfitImages.length > 0) {
        fallbackText +=
          "\nPridal som ti aj fotky týchto kúskov, aby si ich v chate videl pekne pod sebou 😉";
      } else {
        fallbackText +=
          "\nVyzerá to, že niektoré kúsky nemajú uloženú fotku, takže ti ich neviem zobraziť v chate.";
      }
    }

    // Ak nemáme OpenAI alebo outfit, vrátime fallback
    if (!openaiKey || chosenItems.length === 0) {
      return res.status(200).json({
        text: fallbackText,
        outfit_images: outfitImages,
      });
    }

    let aiText;

    try {
      const tempInfo =
        temp !== null ? `${temp} °C (${tempCategory})` : tempCategory;

      const lineForAI = (item, label) => {
        if (!item) return "";
        const category = item.category || label;
        const color = item.color || "";
        const styleText = getStyleText(item);
        return `${label}: ${category}, farba: ${
          color || "neznáma"
        }, štýl: ${styleText || "neznámy"}\n`;
      };

      let outfitForAI = "";
      outfitForAI += lineForAI(pickedTop, "vrch");
      outfitForAI += lineForAI(pickedBottom, "spodok");
      outfitForAI += lineForAI(pickedShoes, "topánky");
      outfitForAI += lineForAI(pickedOuter, "vrchná vrstva");
      outfitForAI = outfitForAI.trim();

      const systemMessage = {
        role: "system",
        content:
          "Si priateľský módny stylista, ktorý komunikuje po slovensky. " +
          "Pomáhaš používateľovi vybrať outfit z JEHO ŠATNÍKA. " +
          "Nikdy nevymýšľaj kúsky, ktoré nie sú v zadanom outfite. " +
          "Odpoveď napíš stručne (3–6 viet), môžeš použiť emoji, ale s mierou. " +
          "Najprv používateľa prirodzene oslov, potom vysvetli, prečo je tento outfit vhodný " +
          "na dané počasie a príležitosť. Na konci môžeš pridať krátky tip (napr. vrstvenie, doplnky). " +
          "Využívaj históriu chatu, aby si nadväzoval na predchádzajúcu konverzáciu. " +
          "Aplikácia zobrazuje fotky kúskov nad chatom, takže nikdy nepíš, že nevieš ukázať obrázok – " +
          "radšej sa odvolaj na to, čo používateľ vidí na obrazovke.",
      };

      aiText = await callOpenAI(openaiKey, [
        systemMessage,
        ...historyMessages,
        {
          role: "user",
          content:
            `Používateľ napísal: "${userQuery}".\n` +
            `Teplota/počasie: ${tempInfo}.\n` +
            `Príležitosť: ${occasion}.\n` +
            `Vybraný outfit (NEVYMÝŠĽAJ INÉ KUSY):\n${outfitForAI}\n\n` +
            "Na základe tohto prosím napíš odpoveď používateľovi.",
        },
      ]);
    } catch (err) {
      console.error("OpenAI outfit error:", err);
      aiText = fallbackText;
    }

    return res.status(200).json({
      text: aiText || fallbackText,
      outfit_images: outfitImages,
    });
  } catch (err) {
    console.error("Chyba v chatWithStylist:", err);
    return res.status(500).json({
      text: `Na serveri došlo k chybe: ${err.message || String(err)}`,
      outfit_images: [],
    });
  }
});

// ======================================
// 2) Čistiaca funkcia – zlé imageUrl
// ======================================

exports.cleanBadImageUrls = functions.https.onRequest(async (req, res) => {
  try {
    let cleanedUserWardrobe = 0;
    let cleanedPublicWardrobe = 0;

    const usersSnap = await db.collection("users").get();
    for (const userDoc of usersSnap.docs) {
      const wardrobeSnap = await userDoc.ref.collection("wardrobe").get();
      for (const itemDoc of wardrobeSnap.docs) {
        const data = itemDoc.data() || {};
        const imageUrl = data.imageUrl;
        if (typeof imageUrl === "string" && imageUrl.includes("example.com")) {
          console.log(
            `Čistím users/${userDoc.id}/wardrobe/${itemDoc.id} – imageUrl=${imageUrl}`
          );
          await itemDoc.ref.update({ imageUrl: "" });
          cleanedUserWardrobe++;
        }
      }
    }

    const publicSnap = await db.collection("public_wardrobe").get();
    for (const itemDoc of publicSnap.docs) {
      const data = itemDoc.data() || {};
      const imageUrl = data.imageUrl;
      if (typeof imageUrl === "string" && imageUrl.includes("example.com")) {
        console.log(
          `Čistím public_wardrobe/${itemDoc.id} – imageUrl=${imageUrl}`
        );
        await itemDoc.ref.update({ imageUrl: "" });
        cleanedPublicWardrobe++;
      }
    }

    const result = {
      cleanedUserWardrobe,
      cleanedPublicWardrobe,
      message:
        "Hotovo – zlé imageUrl obsahujúce example.com boli nastavené na prázdny string.",
    };

    console.log("Výsledok cleanBadImageUrls:", result);

    return res.status(200).json(result);
  } catch (err) {
    console.error("Chyba v cleanBadImageUrls:", err);
    return res.status(500).json({
      message: "Na serveri došlo k chybe pri čistení imageUrl.",
      error: String(err),
    });
  }
});

// ======================================
// 3) analyzeClothingImage – jednoduché “AI”
// ======================================

exports.analyzeClothingImage = functions.https.onRequest(async (req, res) => {
  try {
    if (req.method !== "POST") {
      return res.status(405).json({
        message: "Použi POST metódu.",
      });
    }

    const body = req.body || {};
    const imageUrl = body.imageUrl || "";

    console.log("➡️ analyzeClothingImage – imageUrl:", imageUrl);

    const aiData = {
      brand: "",
      category: "Tričká",
      color: ["Neznáma"],
      style: ["Casual"],
      pattern: ["Jednofarebné"],
      season: ["Celoročné"],
    };

    return res.status(200).json(aiData);
  } catch (err) {
    console.error("Chyba v analyzeClothingImage:", err);
    return res.status(500).json({
      message: "Na serveri došlo k chybe pri analýze obrázka.",
      error: String(err),
    });
  }
});
