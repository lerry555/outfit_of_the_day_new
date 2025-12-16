// functions/index.js (GEN1 - Node 20)
// - Storage trigger: removeBackgroundOnUpload (ClipDrop)
// - Firestore trigger: attachCleanImageOnWardrobeWrite (doplní cleanImageUrl po uložení)
// - HTTPS: analyzeClothingImage (OpenAI Vision)
// - HTTPS: chatWithStylist (OpenAI text)

const functions = require("firebase-functions");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");
const crypto = require("crypto");

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();
const storage = admin.storage();

// ------------------------------
// Helpers: config keys (GEN1 safe)
// ------------------------------
function getConfigValue(pathArray) {
  try {
    const cfg = functions.config() || {};
    let cur = cfg;
    for (const p of pathArray) {
      if (!cur || typeof cur !== "object") return undefined;
      cur = cur[p];
    }
    return cur;
  } catch (_) {
    return undefined;
  }
}

function getOpenAiKey() {
  return process.env.OPENAI_API_KEY || getConfigValue(["openai", "api_key"]) || getConfigValue(["openai", "key"]);
}

function getOpenWeatherKey() {
  return process.env.OPENWEATHER_API_KEY || getConfigValue(["openweather", "api_key"]) || getConfigValue(["openweather", "key"]);
}

function getClipdropKey() {
  return process.env.CLIPDROP_API_KEY || getConfigValue(["clipdrop", "api_key"]) || getConfigValue(["clipdrop", "key"]);
}

// ------------------------------
// Helper: Weather (OpenWeather)
// ------------------------------
async function fetchWeatherFromOpenWeather(location, existingWeather) {
  if (existingWeather && typeof existingWeather === "object" && Object.keys(existingWeather).length > 0) {
    return existingWeather;
  }

  const apiKey = getOpenWeatherKey();
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

    return {
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
  } catch (error) {
    logger.error("Chyba pri načítaní počasia z OpenWeather:", error);
    return existingWeather || null;
  }
}

// ------------------------------
// Outfit images ordering helper
// ------------------------------
function classifyWardrobeItem(url, wardrobe) {
  if (!Array.isArray(wardrobe)) return { slot: "accessory", order: 8 };

  const item = wardrobe.find((piece) => piece && (piece.imageUrl === url || piece.imageUrl === String(url)));

  const text = [
    item?.mainGroup || "",
    item?.mainGroupLabel || "",
    item?.categoryKey || "",
    item?.categoryLabel || "",
    item?.subCategoryKey || "",
    item?.subCategoryLabel || "",
    item?.type || "",
    item?.name || "",
  ]
    .join(" ")
    .toLowerCase();

  let slot = "accessory";
  let order = 8;

  if (text.includes("čiap") || text.includes("cap") || text.includes("hat")) {
    slot = "hat"; order = 1;
  } else if (text.includes("šál") || text.includes("scarf")) {
    slot = "scarf"; order = 2;
  } else if (text.includes("bunda") || text.includes("kabát") || text.includes("coat") || text.includes("jacket")) {
    slot = "jacket"; order = 3;
  } else if (text.includes("mikina") || text.includes("sveter") || text.includes("hoodie") || text.includes("sweater")) {
    slot = "hoodie"; order = 4;
  } else if (
    text.includes("tričko") || text.includes("tricko") ||
    text.includes("košeľa") || text.includes("kosela") ||
    text.includes("shirt") || text.includes("t-shirt")
  ) {
    slot = "shirt"; order = 5;
  } else if (
    text.includes("rifle") || text.includes("nohavice") ||
    text.includes("tepláky") || text.includes("teplaky") ||
    text.includes("jeans") || text.includes("pants") ||
    text.includes("legíny") || text.includes("leginy") ||
    text.includes("shorts")
  ) {
    slot = "pants"; order = 6;
  } else if (
    text.includes("topánky") || text.includes("topanky") ||
    text.includes("tenisky") || text.includes("sneakers") ||
    text.includes("boty") || text.includes("obuv") ||
    text.includes("shoes") || text.includes("boots") ||
    text.includes("čižmy") || text.includes("cizmy")
  ) {
    slot = "shoes"; order = 7;
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

  items.sort((a, b) => (a.order === b.order ? a.originalIndex - b.originalIndex : a.order - b.order));

  const usedSlots = new Set();
  const result = [];

  for (const item of items) {
    if (item.slot === "shoes" && usedSlots.has("shoes")) continue;
    result.push(item.url);
    usedSlots.add(item.slot);
  }

  return result;
}

// ---------------------------------------------------------------------------
// ✅ GEN1 Storage Trigger: removeBackgroundOnUpload – ClipDrop
// ---------------------------------------------------------------------------
exports.removeBackgroundOnUpload = functions
  .region("us-central1")
  .storage.object()
  .onFinalize(async (object) => {
    const filePath = object.name || "";
    const contentType = object.contentType || "";
    const bucketName = object.bucket;

    if (!contentType.startsWith("image/")) return null;
    if (!filePath.startsWith("wardrobe/")) return null;
    if (filePath.startsWith("wardrobe_clean/")) return null;

    const parts = filePath.split("/");
    if (parts.length < 3) return null;
    const uid = parts[1];

    const clipApiKey =
      process.env.CLIPDROP_API_KEY ||
      functions.config()?.clipdrop?.api_key;
    if (!clipApiKey) {
      logger.error("Chýba CLIPDROP_API_KEY (process.env alebo functions.config().clipdrop.api_key)");
      return null;
    }

    try {
      const bucket = storage.bucket(bucketName);

      // 1) download originál
      const [buf] = await bucket.file(filePath).download();

      // 2) ClipDrop remove background
      const form = new FormData();
      const blob = new Blob([buf], { type: contentType || "image/jpeg" });
      form.append("image_file", blob, "input.jpg");

      const clipResponse = await fetch("https://clipdrop-api.co/remove-background/v1", {
        method: "POST",
        headers: { "x-api-key": clipApiKey },
        body: form,
      });

      if (!clipResponse.ok) {
        const errorTxt = await clipResponse.text();
        logger.error("Clipdrop error:", clipResponse.status, errorTxt);
        return null;
      }

      const cleanBuffer = Buffer.from(await clipResponse.arrayBuffer());

      // 3) save PNG do wardrobe_clean/{uid}/...
      const baseName = filePath.split("/").pop().replace(/\.[^/.]+$/, "");
      const cleanPath = `wardrobe_clean/${uid}/${baseName}.png`;

      const token = crypto.randomUUID();
      await bucket.file(cleanPath).save(cleanBuffer, {
        contentType: "image/png",
        metadata: {
          metadata: {
            firebaseStorageDownloadTokens: token,
          },
        },
      });

      const encoded = encodeURIComponent(cleanPath);
      const cleanImageUrl =
        `https://firebasestorage.googleapis.com/v0/b/${bucketName}/o/${encoded}?alt=media&token=${token}`;

      // 4) zapíš mapovanie (aby Firestore trigger vedel doplniť cleanImageUrl aj keď user uloží skôr)
      const mapId = Buffer.from(`${uid}|${filePath}`).toString("base64").replace(/[/+=]/g, "_");
      await db.collection("storage_clean_map").doc(mapId).set(
        {
          uid,
          originalPath: filePath,
          cleanPath,
          cleanImageUrl,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );

      // 5) update Firestore wardrobe doc (ak už existuje)
      const wardrobeRef = db.collection("users").doc(uid).collection("wardrobe");
      const snap = await wardrobeRef.where("storagePath", "==", filePath).get();

      let updated = 0;

      if (!snap.empty) {
        for (const doc of snap.docs) {
          await doc.ref.set(
            {
              cleanImageUrl,
              cleanStoragePath: cleanPath,
              cleanUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
              isClean: true, // ✅ pridaj toto
            },
            { merge: true }
          );

          updated++;
        }
      }

      logger.info("removeBackgroundOnUpload OK", { filePath, cleanPath, updated });
      return null;
    } catch (err) {
      logger.error("removeBackgroundOnUpload error:", err);
      return null;
    }
  });

// ---------------------------------------------------------------------------
// ✅ Firestore Trigger: keď sa uloží wardrobe item, doplň cleanImageUrl ak existuje mapping
// (rieši prípad: user klikne Uložiť skôr, než sa background trigger stihne)
// ---------------------------------------------------------------------------
exports.attachCleanImageOnWardrobeWrite = functions
  .region("us-central1")
  .firestore.document("users/{uid}/wardrobe/{itemId}")
  .onWrite(async (change, context) => {
    const after = change.after.exists ? change.after.data() : null;
    if (!after) return null;

    const uid = context.params.uid;
    const storagePath = String(after.storagePath || "");
    if (!storagePath.startsWith("wardrobe/")) return null;

    // už je doplnené? nič nerob
    if (after.cleanImageUrl && String(after.cleanImageUrl).length > 0) return null;

    try {
      const mapId = Buffer.from(`${uid}|${storagePath}`).toString("base64").replace(/[/+=]/g, "_");
      const mapSnap = await db.collection("storage_clean_map").doc(mapId).get();
      if (!mapSnap.exists) return null;

      const mapData = mapSnap.data() || {};
      const cleanImageUrl = String(mapData.cleanImageUrl || "");
      const cleanStoragePath = String(mapData.cleanPath || "");

      if (!cleanImageUrl) return null;

      await change.after.ref.set(
        {
          cleanImageUrl,
          cleanStoragePath,
          cleanUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );

      logger.info("attachCleanImageOnWardrobeWrite OK", { uid, storagePath });
      return null;
    } catch (e) {
      logger.error("attachCleanImageOnWardrobeWrite error:", e);
      return null;
    }
  });

// ---------------------------------------------------------------------------
// 1) analyzeClothingImage – GEN1 HTTPS (OpenAI Vision)
// ---------------------------------------------------------------------------
exports.analyzeClothingImage = functions
  .region("us-east1")
  .https.onRequest(async (req, res) => {
    if (req.method !== "POST") {
      return res.status(405).send("Metóda nie je povolená. Použite POST.");
    }

    const { imageUrl } = req.body || {};
    if (!imageUrl) {
      return res.status(400).send("Chýba imageUrl v tele požiadavky.");
    }

    const apiKey = getOpenAiKey();
    if (!apiKey) {
      logger.error("Chýba OPENAI_API_KEY (process.env alebo functions.config().openai.api_key)");
      return res.status(500).send("Server nemá nastavený OPENAI_API_KEY.");
    }

    try {
      const systemPrompt = `
Si profesionálny módny stylista a expert na rozpoznávanie oblečenia z fotiek pre mobilnú aplikáciu.
Výstup musí byť STRICTNE vo forme JSON objektu. Nepíš žiadny iný text.

Používaš 2 dôležité polia:
- "type": pekný názov pre používateľa v slovenčine (napr. "Mikina s kapucňou")
- "canonical_type": technický kľúč z nasledujúceho zoznamu

POVOLENÉ canonical_type HODNOTY (ID -> názov pre používateľa):

TRIČKÁ & TOPY
- tricko -> "Tričko s krátkym rukávom"
- tricko_dlhy_rukav -> "Tričko s dlhým rukávom"
- tielko -> "Tielko"
- crop_top -> "Crop top"
- polo_tricko -> "Polo tričko"
- body -> "Body"
- korzet_top -> "Korzet (top)"

KOŠELE
- kosela_klasicka -> "Klasická košeľa"
- kosela_oversize -> "Oversize košeľa"
- kosela_flanelova -> "Flanelová košeľa"

MIKINY
- mikina_klasicka -> "Mikina"
- mikina_na_zips -> "Mikina na zips"
- mikina_s_kapucnou -> "Mikina s kapucňou"
- mikina_oversize -> "Oversize mikina"

Pravidlá pre mikiny:
- Ak je jasne viditeľná kapucňa (aj keď je zložená), uprednostni "mikina_s_kapucnou".
- Ak je to mikina bez kapucne, ale so zipsom po celej dĺžke, použi "mikina_na_zips".
- Ak je to mikina bez kapucne a bez dlhého zipsu, použi "mikina_klasicka".
- Ak je strih zjavne voľný, môžeš použiť "mikina_oversize".

SVETRE
- sveter_klasicky -> "Sveter"
- sveter_rolak -> "Rolák"
- sveter_kardigan -> "Kardigan"
- sveter_pleteny -> "Pletený sveter"

BUNDY & KABÁTY
- bunda_riflova -> "Rifľová bunda"
- bunda_kozena -> "Kožená bunda"
- bunda_bomber -> "Bomber bunda"
- bunda_prechodna -> "Prechodná bunda"
- bunda_zimna -> "Zimná bunda"
- kabat -> "Kabát"
- trenchcoat -> "Trenchcoat"
- sako -> "Sako / blejzer"
- vesta -> "Vesta"
- prsiplast -> "Pršiplášť"
- flisova_bunda -> "Flísová bunda"

ŠPORT – OBLEČENIE
- sport_tricko -> "Športové tričko"
- sport_mikina -> "Funkčná mikina"
- sport_leginy -> "Športové legíny"
- sport_sortky -> "Športové kraťasy"
- sport_suprava -> "Tepláková súprava"
- softshell_bunda -> "Softshell bunda"
- sport_podprsenka -> "Športová podprsenka"

PRÍSNE pravidlo pre softshell_bunda:
- "softshell_bunda" použi LEN ak je bunda očividne technický SOFTSHELL: tenká (bez výplne), športový/outdoor strih,
  typické technické zipsy/lemovanie, materiál pôsobí ako softshell.
- Ak si nie si istý, NIKDY nepouži "softshell_bunda".
  Vtedy rozhoduj:
  - hrubá/nafúknutá/zateplená/ski/puffer/parka -> "bunda_zimna"
  - ľahšia bez hrubej výplne -> "bunda_prechodna"

PRÍSNE pravidlo pre zimnú bundu:
- Ak má bunda kapucňu + pôsobí hrubo/zateplene (zimná outdoor/ski), vždy zvoľ "bunda_zimna".
- Ak si medzi "bunda_prechodna" a "bunda_zimna" nie si istý, uprednostni "bunda_zimna".

DÔLEŽITÉ pravidlo (technický materiál):
- "technický materiál" (outdoor látka) SÁM O SEBE nikdy neznamená "bunda_prechodna".
- Technický materiál majú často aj zimné bundy (ski/outdoor).
- Rozhoduj hlavne podľa hrúbky a zateplenia:
  - ak bunda pôsobí hrubá/zateplená/nafúknutá (puffer, zimná outdoor/ski) -> "bunda_zimna"
  - iba ak pôsobí tenká bez výplne -> "bunda_prechodna"
- Ak si nie si istý medzi "bunda_prechodna" a "bunda_zimna", vyber "bunda_zimna".

NOHAVICE & RIFLE
- rifle -> "Rifle"
- rifle_skinny -> "Skinny rifle"
- rifle_wide_leg -> "Rifle wide leg"
- rifle_mom -> "Mom jeans"
- nohavice_chino -> "Chino nohavice"
- nohavice_teplakove -> "Teplákové nohavice"
- nohavice_joggery -> "Joggery"
- nohavice_elegantne -> "Elegantné nohavice"
- nohavice_cargo -> "Cargo nohavice"

ŠORTKY & SUKNE
- sortky -> "Šortky"
- sortky_sportove -> "Športové šortky"
- sukna_mini -> "Mini sukňa"
- sukna_midi -> "Midi sukňa"
- sukna_maxi -> "Maxi sukňa"

ŠATY & OVERALY
- saty_kratke -> "Krátke šaty"
- saty_midi -> "Midi šaty"
- saty_maxi -> "Maxi šaty"
- saty_koselove -> "Košeľové šaty"
- saty_bodycon -> "Bodycon šaty"
- overal -> "Overal"

OBUV – TENISKY
- tenisky_fashion -> "Fashion tenisky"
- tenisky_sportove -> "Športové tenisky"
- tenisky_bezecke -> "Bežecké tenisky"

OBUV – ELEGANTNÁ
- lodicky -> "Lodičky"
- sandale_opatok -> "Sandále na opätku"
- balerinky -> "Balerínky"
- mokasiny -> "Mokasíny"
- poltopanky -> "Poltopánky"
- obuv_platforma -> "Obuv na platforme"

OBUV – ČIŽMY
- cizmy_clenkove -> "Členkové čižmy"
- cizmy_vysoke -> "Vysoké čižmy"
- cizmy_nad_kolena -> "Čižmy nad kolená"
- gumaky -> "Gumáky"
- snehule -> "Snehule"

Pravidlá pre čižmy:
- "cizmy_clenkove": siahajú po členok alebo len trochu nad členok.
- "cizmy_vysoke": siahajú do polovice lýtka alebo vyššie, ale nie nad koleno.
- "cizmy_nad_kolena": zjavne presahujú koleno.
- Ak si nie si istý medzi členkové a vysoké, preferuj členkové.

OBUV – LETNÁ
- sandale -> "Sandále"
- slapky -> "Šľapky"
- zabky -> "Žabky"
- espadrilky -> "Espadrilky"

DOPLNKY – HLAVA
- ciapka -> "Čiapka"
- siltovka -> "Šiltovka"
- bucket_hat -> "Bucket hat"

DOPLNKY – ŠÁLY, RUKAVICE
- sal -> "Šál"
- satka -> "Šatka"
- rukavice -> "Rukavice"

DOPLNKY – TAŠKY
- kabelka -> "Kabelka"
- taska_crossbody -> "Crossbody taška"
- ruksak -> "Ruksak"
- kabelka_listova -> "Listová kabelka"
- ladvinka -> "Ľadvinka"

DOPLNKY – OSTATNÉ
- slnecne_okuliare -> "Slnečné okuliare"
- opasok -> "Opasok"
- penazenka -> "Peňaženka"
- hodinky -> "Hodinky"
- sperky -> "Šperky"

ŠPORT – OBUV + DOPLNKY
- obuv_treningova -> "Tréningová obuv"
- obuv_turisticka -> "Turistická obuv"
- sport_taska -> "Športová taška"
- potitka -> "Potítka"

────────────────────────────────────────────────────────
FARBY
────────────────────────────────────────────────────────
Používaj iba tieto farby v poli "colors":
["biela","čierna","sivá","béžová","hnedá","modrá","tmavomodrá","svetlomodrá","červená","bordová","ružová","fialová","zelená","khaki","žltá","oranžová","zlatá","strieborná"].
Farbu určuj podľa látky. Ignoruj farbu loga, šnúrok a zipsov.

────────────────────────────────────────────────────────
ŠTÝL
────────────────────────────────────────────────────────
Používaj iba: ["casual","streetwear","sport","elegant","smart casual"]

ŠTÝL – PRAVIDLO PRE BUNDY:
- Bežné zimné/prechodné bundy dávaj skôr ako "casual", aj keď ide o outdoor značku.
- "sport" použi len ak je to očividne športový funkčný kus (tréning/outdoor funkčné oblečenie).

────────────────────────────────────────────────────────
VZOR (patterns)
────────────────────────────────────────────────────────
- úplne jednofarebný -> "jednofarebné"
- text alebo logo -> "textová potlač"
- iná grafika -> "grafická potlač"
- pruhy -> "pruhované"
- káro -> "kockované"
- maskáč -> "kamufláž"

────────────────────────────────────────────────────────
SEZÓNA (season)
────────────────────────────────────────────────────────
- zimná bunda, snehule, čižmy so zjavnou kožušinkou alebo hrubou výplňou -> ["zima"]
- tenké tričko, tielko, žabky, sandále -> ["jar","leto","jeseň"]
- rifle, väčšina nohavíc, bežné mikiny bez hrubej výplne -> ["celoročne"]
- bunda_prechodna, rifľová bunda, bomber, softshell_bunda -> ["jar","jeseň"]

SEASON – POVINNÝ FORMÁT:
- "season" musí byť vždy pole stringov, napr. ["jar","jeseň"] alebo ["zima"] alebo ["celoročne"]
- NIKDY nedávaj "jar, jeseň" ako jednu položku.

────────────────────────────────────────────────────────
ZNAČKA (brand)
────────────────────────────────────────────────────────
PRAVIDLÁ PRE BRAND (dôležité):
- Ak je na oblečení viditeľný nápis/logo značky (napr. "HI-TEC", "Nike", "Adidas"), MUSÍŠ ho vrátiť v "brand".
- Skús prečítať brand aj keď je malý (pozri hrudník, rukáv, jazyk topánky).
- Zachovaj presné písanie (napr. "HI-TEC").
- Ak nie je čitateľný, vráť "".

────────────────────────────────────────────────────────
VÝSTUP
────────────────────────────────────────────────────────
VALIDÁCIA VÝSTUPU (povinné):
- Vráť len čistý JSON (žiadne code bloky, žiadne komentáre).
- "colors" musí byť pole len z povolených farieb.
- "style" musí byť pole len z: ["casual","streetwear","sport","elegant","smart casual"]
- "season" musí byť pole len z: ["jar","leto","jeseň","zima","celoročne"] (nie "jar, jeseň" ako jedna položka).
- "patterns" musí byť pole len z: ["jednofarebné","textová potlač","grafická potlač","pruhované","kockované","kamufláž"].
- Ak je kúsok jednofarebný, použi presne "jednofarebné" (nie "jednofarebný").
Okrem povinných polí vráť aj:
- "confidence": číslo 0.0 až 1.0
- "debug_reason": krátky dôvod (1-2 vety) prečo si vybral canonical_type

JSON formát:
{
  {
    "type": "Mikina s kapucňou",
    "canonical_type": "mikina_s_kapucnou",
    "colors": ["čierna"],
    "style": ["casual"],
    "season": ["celoročne"],
    "patterns": ["textová potlač"],
    "brand": "Nike",
    "confidence": 0.78,
    "debug_reason": "Viditeľná kapucňa a strih mikiny, bez znakov bundy alebo kabátu."
  }

}
`.trim();

      const openAiBody = {
        model: "gpt-4o-mini",
        temperature: 0.1,
        messages: [
          { role: "system", content: systemPrompt },
          {
            role: "user",
            content: [
              { type: "text", text: "Analyzuj tento jeden kus oblečenia na fotke a vráť JSON podľa inštrukcií." },
              { type: "image_url", image_url: { url: imageUrl } },
            ],
          },
        ],
      };

      const response = await fetch("https://api.openai.com/v1/chat/completions", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: "Bearer " + apiKey,
        },
        body: JSON.stringify(openAiBody),
      });

      if (!response.ok) {
        const errorText = await response.text();
        logger.error("OpenAI analyzeClothingImage error:", response.status, errorText);
        return res.status(500).send(`OpenAI analyzeClothingImage error ${response.status}: ${errorText}`);
      }

            const data = await response.json();
            const text = data?.choices?.[0]?.message?.content;

            if (!text) throw new Error("OpenAI nevrátil text (analyzeClothingImage).");

            try {
              let raw = String(text).trim();

              // ak by model náhodou vrátil ```json ... ``` tak to upraceme
              if (raw.startsWith("```")) {
                const firstNl = raw.indexOf("\n");
                if (firstNl !== -1) raw = raw.substring(firstNl + 1);
              }
              if (raw.endsWith("```")) {
                raw = raw.substring(0, raw.lastIndexOf("```")).trim();
              }

              const jsonResponse = JSON.parse(raw);

              // -----------------------------
              // ✅ BACKEND “override” (zimná vs prechodná)
              // spúšťaj LEN keď AI tvrdí, že je to prechodná bunda
              // -----------------------------
              if (jsonResponse?.canonical_type === "bunda_prechodna") {
                const brand = String(jsonResponse.brand || "").toUpperCase();
                const colors = Array.isArray(jsonResponse.colors) ? jsonResponse.colors.map(String) : [];
                const patterns = Array.isArray(jsonResponse.patterns) ? jsonResponse.patterns.map(String) : [];
                const seasonArr = Array.isArray(jsonResponse.season) ? jsonResponse.season.map(String) : [];

                const hasHoodHint = /kapuc/i.test(String(jsonResponse.debug_reason || "")) || /hood/i.test(String(jsonResponse.debug_reason || ""));
                const isOutdoorBrand = ["HI-TEC", "COLUMBIA", "THE NORTH FACE", "NORTH FACE", "SALOMON"].some(b => brand.includes(b));
                const isDark = colors.includes("čierna") || colors.includes("tmavomodrá") || colors.includes("hnedá");
                const isSolid = patterns.includes("jednofarebné");

                let score = 0;
                if (hasHoodHint) score++;
                if (isOutdoorBrand) score++;
                if (isDark && isSolid) score++;
                // “podozrivé”: ak je to bunda a sezóna je len jar/jeseň
                const onlySpringAutumn = seasonArr.length > 0 && seasonArr.every(s => s === "jar" || s === "jeseň");
                if (onlySpringAutumn) score++;

                // ✅ odporúčam 3 (nie 2), aby to nepreklápalo ľahké bundy
                if (score >= 3) {
                  jsonResponse.canonical_type = "bunda_zimna";
                  jsonResponse.type = "Zimná bunda";
                  jsonResponse.season = ["zima"];
                  jsonResponse.debug_reason =
                    (String(jsonResponse.debug_reason || "") + " | BACKEND override: score>=3 => bunda_zimna").trim();
                }
              }

              return res.status(200).send(jsonResponse);
            } catch (e) {
              logger.error("analyzeClothingImage – neplatný JSON, raw:", text);
              return res.status(200).send({ rawText: text });
            }
          } catch (error) {
            logger.error("Chyba pri analyzeClothingImage:", error);
            return res
              .status(500)
              .send("Chyba servera pri analýze obrázka: " + (error.message || String(error)));
          }
        });


// ---------------------------------------------------------------------------
// 2) chatWithStylist – GEN1 HTTPS
// ---------------------------------------------------------------------------
async function callOpenAiChat(systemPrompt, userPrompt) {
  const apiKey = getOpenAiKey();
  if (!apiKey) {
    logger.error("Chýba OPENAI_API_KEY v prostredí!");
    throw new Error("Server nemá nastavený OPENAI_API_KEY.");
  }

  const body = {
    model: "gpt-4o-mini",
    messages: [
      { role: "system", content: systemPrompt },
      { role: "user", content: userPrompt },
    ],
    temperature: 0.7,
  };

  const response = await fetch("https://api.openai.com/v1/chat/completions", {
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
    throw new Error(`OpenAI API vrátilo chybu ${response.status}: ${errorText}`);
  }

  const data = await response.json();
  const text = data?.choices?.[0]?.message?.content;
  if (!text) throw new Error("OpenAI nevrátilo text.");

  return text;
}

exports.chatWithStylist = functions
  .region("us-east1")
  .https.onRequest(async (req, res) => {
    if (req.method !== "POST") return res.status(405).send("Metóda nie je povolená. Použite POST.");

    const { wardrobe, userPreferences, location, weather, focusItem } = req.body || {};
    const finalWeather = await fetchWeatherFromOpenWeather(location, weather);

    const userQuery = req.body.userQuery || req.body.userMessage;
    if (!userQuery) {
      return res.status(400).send("Chýba používateľská požiadavka (userQuery alebo userMessage).");
    }

    try {
      const systemPrompt =
`Si profesionálny módny stylista v mobilnej aplikácii.

Tvoje správanie:
- Buď profesionálny, ale veľmi priateľský a ľudský.
- Reaguj na emócie používateľa.
- Nepredpokladaj nič, čo používateľ nepovedal.

Počasie:
- Informácie o počasí máš v objekte weather v kontexte.
- Ak weather existuje a nie je prázdny objekt, ber to tak, že počasie poznáš a nepytaš sa naň.

Logika outfitov:
- Nepoužívaj duplikované kúsky (rovnaká imageUrl nesmie byť dvakrát).
- V jednom outfite vyber maximálne jedny topánky.
- Používaj výhradne kúsky z wardrobe, nevymýšľaj nové.
- outfit_images musí obsahovať URL práve tých kúskov, o ktorých píšeš v texte.

Formát:
- Odpovedaj LEN v JSON:
{
  "text": "odpoveď v slovenčine",
  "outfit_images": ["url1", "url2"]
}`.trim();

      const context =
`Používateľov šatník:
${JSON.stringify(wardrobe ?? [], null, 2)}

Preferencie:
${JSON.stringify(userPreferences ?? {}, null, 2)}

Lokalita a počasie:
${JSON.stringify({ location, weather: finalWeather }, null, 2)}

Focus item:
${JSON.stringify(focusItem ?? {}, null, 2)}
`;

      const userPrompt =
`KONTEXT:
${context}

SPRÁVA POUŽÍVATEĽA:
${userQuery}

Vráť odpoveď výhradne v JSON formáte:
{
  "text": "odpoveď v slovenčine",
  "outfit_images": ["url1", "url2"]
}`.trim();

      const text = await callOpenAiChat(systemPrompt, userPrompt);

      try {
        const jsonResponse = JSON.parse(text);
        const replyText = jsonResponse.text || "Stylista nemá momentálne žiadnu konkrétnu odpoveď.";
        const rawOutfitImages = Array.isArray(jsonResponse.outfit_images) ? jsonResponse.outfit_images : [];
        const outfitImages = normalizeOutfitImages(rawOutfitImages, wardrobe);

        return res.status(200).send({ replyText, imageUrls: outfitImages });
      } catch (e) {
        logger.error("OpenAI nevrátil platný JSON:", text);
        return res.status(200).send({ replyText: text, imageUrls: [] });
      }
    } catch (error) {
      logger.error("Chyba pri volaní OpenAI API:", error);
      return res.status(500).send("Chyba servera pri AI stylistovi: " + (error.message || String(error)));
    }
  });
