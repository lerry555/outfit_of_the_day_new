// functions/index.js

// Načítanie .env zo súboru functions/.env
require("dotenv").config();

// Firebase Functions a Admin SDK
const functions = require("firebase-functions");
const admin = require("firebase-admin");

if (!admin.apps.length) {
  admin.initializeApp();
}

// Node 18 na Firebase má globálne `fetch`. Ak by ti lokálne hádzalo chybu,
// môžeš odkomentovať tento riadok a nainštalovať node-fetch:
// const fetch = require("node-fetch");

// API kľúče z .env
const OPENWEATHER_API_KEY = process.env.OPENWEATHER_API_KEY;
const OPENAI_API_KEY = process.env.OPENAI_API_KEY;

function log(...args) {
  console.log("[planTripPackingList]", ...args);
}

// yyyy-MM-dd → timestamp (sekundy, UTC poludnie, aby to sedelo na dni)
function parseDateToTimestamp(dateStr) {
  try {
    const [year, month, day] = dateStr.split("-").map((v) => parseInt(v, 10));
    const date = new Date(Date.UTC(year, month - 1, day, 12, 0, 0));
    return Math.floor(date.getTime() / 1000);
  } catch (e) {
    return null;
  }
}

// Geocoding: názov mesta → lat/lon (OpenWeather geocoding)
async function geocodeDestination(destinationName) {
  const url = `http://api.openweathermap.org/geo/1.0/direct?q=${encodeURIComponent(
    destinationName
  )}&limit=1&appid=${OPENWEATHER_API_KEY}`;

  log("Geocoding URL:", url);

  const res = await fetch(url);
  if (!res.ok) {
    throw new Error(`Geocoding error: HTTP ${res.status}`);
  }

  const data = await res.json();
  if (!Array.isArray(data) || data.length === 0) {
    throw new Error("Geocoding: žiadny výsledok pre danú destináciu");
  }

  const place = data[0];
  return {
    lat: place.lat,
    lon: place.lon,
    name: place.name,
    country: place.country,
  };
}

// Počasie: One Call 3.0 daily forecast
async function getWeatherForecast(lat, lon) {
  const url = `https://api.openweathermap.org/data/3.0/onecall?lat=${lat}&lon=${lon}&exclude=minutely,hourly,alerts&units=metric&appid=${OPENWEATHER_API_KEY}`;

  log("Weather URL:", url);

  const res = await fetch(url);
  if (!res.ok) {
    throw new Error(`Weather error: HTTP ${res.status}`);
  }

  const data = await res.json();
  if (!data.daily || !Array.isArray(data.daily)) {
    throw new Error("Weather error: daily forecast chýba");
  }

  return data.daily;
}

// Filtrovanie dní podľa obdobia cesty
function filterDailyByTrip(daily, startTs, endTs) {
  if (!startTs || !endTs) return daily;

  return daily.filter((day) => {
    const dt = day.dt;
    return dt >= startTs - 12 * 3600 && dt <= endTs + 12 * 3600;
  });
}

// Zhrnutie počasia do pekného textu
function summarizeWeather(daily) {
  if (!daily || daily.length === 0) {
    return {
      summaryText:
        "Nepodarilo sa načítať konkrétne počasie. Rátaj skôr s neutrálnymi podmienkami (okolo 15–20 °C).",
      avgDay: 18,
      avgNight: 10,
      minTemp: 15,
      maxTemp: 21,
      possibleRain: false,
      possibleHeat: false,
      possibleCold: false,
    };
  }

  let sumDay = 0;
  let sumNight = 0;
  let minTemp = Infinity;
  let maxTemp = -Infinity;
  let rainDays = 0;

  daily.forEach((d) => {
    const day = d.temp?.day ?? 0;
    const night = d.temp?.night ?? 0;
    sumDay += day;
    sumNight += night;
    if (d.temp?.min < minTemp) minTemp = d.temp.min;
    if (d.temp?.max > maxTemp) maxTemp = d.temp.max;

    const weatherMain = d.weather && d.weather[0] && d.weather[0].main;
    if (weatherMain === "Rain" || weatherMain === "Drizzle" || d.pop > 0.3) {
      rainDays++;
    }
  });

  const avgDay = sumDay / daily.length;
  const avgNight = sumNight / daily.length;

  const possibleRain = rainDays > 0;
  const possibleHeat = maxTemp >= 27;
  const possibleCold = minTemp <= 5;

  let summaryParts = [];

  summaryParts.push(
    `Priemerná denná teplota okolo ${avgDay.toFixed(
      1
    )} °C, nočná okolo ${avgNight.toFixed(1)} °C.`
  );
  summaryParts.push(
    `Teploty sa budú pohybovať približne medzi ${minTemp.toFixed(
      1
    )} °C a ${maxTemp.toFixed(1)} °C.`
  );

  if (possibleRain) {
    summaryParts.push("Je šanca dažďa aspoň v niektorých dňoch.");
  } else {
    summaryParts.push("Dažďa by nemalo byť veľa.");
  }

  if (possibleHeat) {
    summaryParts.push("Môže byť veľmi teplo (27 °C a viac).");
  }
  if (possibleCold) {
    summaryParts.push("Môže byť chladno (5 °C a menej), najmä večer/noc.");
  }

  return {
    summaryText: summaryParts.join(" "),
    avgDay,
    avgNight,
    minTemp,
    maxTemp,
    possibleRain,
    possibleHeat,
    possibleCold,
  };
}

// Zhrnutie šatníka – aby AI vedela, čo máš
function summarizeWardrobe(wardrobe) {
  if (!Array.isArray(wardrobe) || wardrobe.length === 0) {
    return "Používateľ zatiaľ nemá v šatníku žiadne uložené kúsky.";
  }

  const lines = wardrobe.map((item, index) => {
    const cat = item.category || item.categoryName || "neznáma kategória";
    const sub = item.subcategory || item.subCategory || "bez podkategórie";
    const colors = Array.isArray(item.color)
      ? item.color.join(", ")
      : item.color || "neznáme farby";
    const styles = Array.isArray(item.style)
      ? item.style.join(", ")
      : item.style || "neznámy štýl";
    const seasons = Array.isArray(item.season)
      ? item.season.join(", ")
      : item.season || "nezadané sezóny";

    return `${index + 1}) ${cat} – ${sub}, farby: ${colors}, štýl: ${styles}, sezóny: ${seasons}`;
  });

  return `Používateľov šatník (kúsky, ktoré reálne má oblečené k dispozícii):\n${lines.join(
    "\n"
  )}`;
}

// Volanie OpenAI – generuje checklist
async function generatePackingSuggestion({
  destinationText,
  tripType,
  travelMode,
  dateRangeText,
  weatherSummary,
  wardrobeSummary,
}) {
  if (!OPENAI_API_KEY) {
    throw new Error("Chýba OPENAI_API_KEY v .env.");
  }

  const systemPrompt = `
Si osobný AI fashion stylista a cestovný poradca.
Tvojou úlohou je navrhnúť KONKRÉTNY zoznam vecí, čo si zbaliť na cestu,
ktorý:
- rešpektuje šatník používateľa (preferuj veci, ktoré už má),
- zohľadňuje počasie (teploty, dážď, teplo/chlad),
- zohľadňuje typ cesty (dovolenka vs. pracovná cesta),
- zohľadňuje spôsob cestovania (lietadlo / auto / vlak / autobus).

Výstup musí byť:
- v slovenčine,
- krátky, prehľadný,
- formou odrážok (• alebo -),
- rozdelený do logických blokov (napr. Oblečenie hore, Spodok, Obuv, Doplnky, Hygiena, Dokumenty...),
- nie román, ale praktický checklist.
`;

  const userPrompt = `
Informácie o ceste:
- Destinácia: ${destinationText}
- Typ cesty: ${tripType}
- Spôsob cestovania: ${travelMode}
- Termín: ${dateRangeText}

Počasie (predpoveď):
${weatherSummary.summaryText}

Šatník používateľa:
${wardrobeSummary}

Prosím, navrhni konkrétny zoznam položiek, čo si má používateľ zbaliť.
Preferuj vrstvenie oblečenia (napr. tričko + mikina + ľahká bunda),
odporuč počet kusov (napr. 3x tričko, 2x nohavice) podľa dĺžky pobytu.
Nespomínaj, že si AI, ani nevysvetľuj postup – vráť iba hotový checklist.
`;

  const body = {
    model: "gpt-4.1-mini", // môžeš zmeniť na iný model
    messages: [
      { role: "system", content: systemPrompt.trim() },
      { role: "user", content: userPrompt.trim() },
    ],
    temperature: 0.7,
  };

  const response = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${OPENAI_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });

  if (!response.ok) {
    const text = await response.text();
    log("OpenAI error body:", text);
    throw new Error(`OpenAI HTTP ${response.status}`);
  }

  const data = await response.json();
  const choice = data.choices && data.choices[0];
  const content = choice && choice.message && choice.message.content;

  if (!content) {
    throw new Error("OpenAI nevrátil žiadny text.");
  }

  return content.trim();
}

// Hlavná HTTPS funkcia – tú volá Flutter
exports.planTripPackingList = functions.https.onRequest(async (req, res) => {
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Headers", "Content-Type, Authorization");
  res.set("Access-Control-Allow-Methods", "POST, OPTIONS");

  if (req.method === "OPTIONS") {
    return res.status(204).send("");
  }

  if (req.method !== "POST") {
    return res.status(405).json({ error: "Použi POST." });
  }

  try {
    if (!OPENWEATHER_API_KEY) {
      throw new Error("Chýba OPENWEATHER_API_KEY v .env.");
    }

    const body = req.body || {};
    const userId = body.userId;
    const trip = body.trip || {};
    const wardrobe = body.wardrobe || [];

    if (!userId) {
      return res.status(400).json({ error: "Chýba userId v tele požiadavky." });
    }

    const destinationName =
      trip.destinationName || trip.destination || "Neznáma destinácia";
    const tripType = trip.tripType || "dovolenka";
    const travelMode = trip.travelMode || "lietadlo";

    const startDateStr = trip.startDate; // "yyyy-MM-dd"
    const endDateStr = trip.endDate; // "yyyy-MM-dd"

    const startTs = startDateStr ? parseDateToTimestamp(startDateStr) : null;
    const endTs = endDateStr ? parseDateToTimestamp(endDateStr) : null;

    const dateRangeText =
      startDateStr && endDateStr
        ? `${startDateStr} – ${endDateStr}`
        : "dátum nie je presne zadaný";

    log("Incoming trip:", trip);
    log("Wardrobe length:", wardrobe.length);

    // 1) Geo súradnice
    const geo = await geocodeDestination(destinationName);
    log("Geocoded destination:", geo);

    // 2) Počasie
    const daily = await getWeatherForecast(geo.lat, geo.lon);

    // 3) Len dni v rozsahu cesty (ak zadané)
    const relevantDaily = filterDailyByTrip(daily, startTs, endTs);
    log("Daily count:", daily.length, "relevant:", relevantDaily.length);

    // 4) Zhrnutie počasia
    const weatherSummary = summarizeWeather(
      relevantDaily.length > 0 ? relevantDaily : daily
    );

    // 5) Zhrnutie šatníka
    const wardrobeSummary = summarizeWardrobe(wardrobe);

    // 6) OpenAI → checklist
    const packingSuggestion = await generatePackingSuggestion({
      destinationText: `${destinationName} (${geo.country})`,
      tripType,
      travelMode,
      dateRangeText,
      weatherSummary,
      wardrobeSummary,
    });

    // 7) Odpoveď pre Flutter
    return res.json({
      packingSuggestion,
      meta: {
        destination: destinationName,
        country: geo.country,
        tripType,
        travelMode,
        dateRange: dateRangeText,
      },
    });
  } catch (error) {
    console.error("Chyba vo funkcii planTripPackingList:", error);
    return res.status(500).json({
      error: error.message || "Neznáma chyba na serveri.",
    });
  }
});
