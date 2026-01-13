// functions/index.js (GEN1 - Node 20)
// - Storage trigger: removeBackgroundOnUpload (ClipDrop)
// - Storage trigger: createProductPhotoOnCleanUpload (Sharp - E-shop look)
// - Firestore trigger: attachCleanImageOnWardrobeWrite (doplní cleanImageUrl + cutoutImageUrl)
// - HTTPS: analyzeClothingImage (OpenAI Vision)
// - HTTPS: chatWithStylist (OpenAI text)

const functions = require("firebase-functions");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");
const crypto = require("crypto");
const sharp = require("sharp");

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
  return (
    process.env.OPENAI_API_KEY ||
    getConfigValue(["openai", "api_key"]) ||
    getConfigValue(["openai", "key"])
  );
}

function getOpenWeatherKey() {
  return (
    process.env.OPENWEATHER_API_KEY ||
    getConfigValue(["openweather", "api_key"]) ||
    getConfigValue(["openweather", "key"])
  );
}

function getClipdropKey() {
  return (
    process.env.CLIPDROP_API_KEY ||
    getConfigValue(["clipdrop", "api_key"]) ||
    getConfigValue(["clipdrop", "key"])
  );
}

// ------------------------------
// Helper: Weather (OpenWeather)
// ------------------------------
async function fetchWeatherFromOpenWeather(location, existingWeather) {
  if (
    existingWeather &&
    typeof existingWeather === "object" &&
    Object.keys(existingWeather).length > 0
  ) {
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

  const item = wardrobe.find(
    (piece) => piece && (piece.imageUrl === url || piece.imageUrl === String(url))
  );

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
    if (filePath.startsWith("wardrobe_product/")) return null;

    const parts = filePath.split("/");
    if (parts.length < 3) return null;
    const uid = parts[1];

    const clipApiKey = getClipdropKey();
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

      // 4) mapping (pre prípad, že user uloží do DB skôr)
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
          const existingProduct = doc.data()?.processing?.product;
          await doc.ref.set(
            {
              cleanImageUrl,
              cleanStoragePath: cleanPath,
              cleanUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
              isClean: true,

              // pre UI: cutout image = clean image
              cutoutImageUrl: cleanImageUrl,

              processing: {
                cutout: "done",
                // ak už mal hodnotu, nechaj; inak nastav queued (lebo produkt pipeline existuje)
                product: existingProduct || "queued",
              },
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
// ✅ GEN1 Storage Trigger: createProductPhotoOnCleanUpload (E-shop look)
// - vezme wardrobe_clean/{uid}/xxx.png
// - vyrobí 1024x1024 PNG s bielym pozadím + tieňom do wardrobe_product/{uid}/xxx.png
// - dopíše productImageUrl + processing.product="done" do Firestore
// ---------------------------------------------------------------------------
exports.createProductPhotoOnCleanUpload = functions
  .region("us-central1")
  .storage.object()
  .onFinalize(async (object) => {
    const filePath = object.name || "";
    const contentType = object.contentType || "";
    const bucketName = object.bucket;

    if (!contentType.startsWith("image/")) return null;
    if (!filePath.startsWith("wardrobe_clean/")) return null;
    if (filePath.startsWith("wardrobe_product/")) return null;

    const parts = filePath.split("/");
    if (parts.length < 3) return null;
    const uid = parts[1];

    const bucket = storage.bucket(bucketName);

    // ---- nastavenia “eshop looku” ----
    const CANVAS = 1024;
    const ITEM_MAX = 780; // zníž ešte viac (napr. 720), ak chceš viac “paddingu”
    const BG = "#FFFFFF";
    const SHADOW_DY = 26;
    const SHADOW_BLUR = 18;
    const SHADOW_OPACITY = 0.22;

    try {
      // 1) stiahni clean PNG
      const [inputBuf] = await bucket.file(filePath).download();

      // 2) orež transparentné okraje + zmenši (aby bol padding)
      const trimmed = await sharp(inputBuf)
        .ensureAlpha()
        .trim()
        .png()
        .toBuffer();

      const resizedItem = await sharp(trimmed)
        .resize(ITEM_MAX, ITEM_MAX, { fit: "inside" })
        .png()
        .toBuffer();

      // 3) SVG render: biele pozadie + drop shadow + item v strede
      const b64 = resizedItem.toString("base64");
      const x = Math.floor((CANVAS - ITEM_MAX) / 2);
      const y = Math.floor((CANVAS - ITEM_MAX) / 2);

      const svg = `
<svg xmlns="http://www.w3.org/2000/svg" width="${CANVAS}" height="${CANVAS}">
  <defs>
    <filter id="ds" x="-30%" y="-30%" width="160%" height="160%">
      <feDropShadow dx="0" dy="${SHADOW_DY}" stdDeviation="${SHADOW_BLUR}"
        flood-color="black" flood-opacity="${SHADOW_OPACITY}" />
    </filter>
  </defs>
  <rect width="100%" height="100%" fill="${BG}" />
  <image
    href="data:image/png;base64,${b64}"
    x="${x}"
    y="${y}"
    width="${ITEM_MAX}"
    height="${ITEM_MAX}"
    filter="url(#ds)"
    preserveAspectRatio="xMidYMid meet"
  />
</svg>`.trim();

      const productBuf = await sharp(Buffer.from(svg))
        .png({ compressionLevel: 9 })
        .toBuffer();

      // 4) ulož do wardrobe_product/{uid}/...
      const baseName = filePath.split("/").pop().replace(/\.[^/.]+$/, "");
      const productPath = `wardrobe_product/${uid}/${baseName}.png`;

      const token = crypto.randomUUID();
      await bucket.file(productPath).save(productBuf, {
        contentType: "image/png",
        metadata: {
          metadata: {
            firebaseStorageDownloadTokens: token,
          },
        },
      });

      const encoded = encodeURIComponent(productPath);
      const productImageUrl =
        `https://firebasestorage.googleapis.com/v0/b/${bucketName}/o/${encoded}?alt=media&token=${token}`;

      // 5) update Firestore wardrobe doc (podľa cleanStoragePath)
      const snap = await db
        .collection("users")
        .doc(uid)
        .collection("wardrobe")
        .where("cleanStoragePath", "==", filePath)
        .get();

      if (!snap.empty) {
        for (const doc of snap.docs) {
          await doc.ref.set(
            {
              productImageUrl,
              productStoragePath: productPath,
              productUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
              processing: { product: "done" },
            },
            { merge: true }
          );
        }
      }

      logger.info("createProductPhotoOnCleanUpload OK", { filePath, productPath, updatedDocs: snap.size });
      return null;
    } catch (e) {
      logger.error("createProductPhotoOnCleanUpload ERROR", { filePath, e });

      // nastav error, aby UI nečakalo donekonečna
      try {
        const snap = await db
          .collection("users")
          .doc(uid)
          .collection("wardrobe")
          .where("cleanStoragePath", "==", filePath)
          .get();

        for (const doc of snap.docs) {
          await doc.ref.set(
            {
              processing: { product: "error" },
              productImageUrl: null,
              productUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            { merge: true }
          );
        }
      } catch (_) {}

      return null;
    }
  });

// ---------------------------------------------------------------------------
// ✅ Firestore Trigger: keď sa uloží wardrobe item, doplň cleanImageUrl + cutoutImageUrl
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

    const hasClean = !!(after.cleanImageUrl && String(after.cleanImageUrl).length > 0);
    const hasCutout = !!(after.cutoutImageUrl && String(after.cutoutImageUrl).length > 0);

    // ak už je clean aj cutout, nič nerob
    if (hasClean && hasCutout) return null;

    // ak clean existuje, ale cutout chýba -> doplň cutout rovno z clean
    if (hasClean && !hasCutout) {
      await change.after.ref.set(
        {
          cutoutImageUrl: String(after.cleanImageUrl),
          processing: {
            cutout: "done",
            product: after?.processing?.product || "queued",
          },
        },
        { merge: true }
      );

      logger.info("attachCleanImageOnWardrobeWrite: filled cutoutImageUrl from existing cleanImageUrl", { uid });
      return null;
    }

    // inak hľadaj mapping
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

          cutoutImageUrl: cleanImageUrl,
          processing: {
            cutout: "done",
            product: after?.processing?.product || "queued",
          },
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
 // ✅ requestTryOn – GEN1 HTTPS (Callable)
 // - vstup: baseImageUrl (voliteľné), garmentImageUrl, slot, sessionId (voliteľné)
 // - výstup: resultUrl (hotový obrázok "figurína + oblečenie")
 // ---------------------------------------------------------------------------
 exports.requestTryOn = functions
   .region("us-central1")
   .https.onCall(async (data, context) => {
     // auth
     if (!context.auth || !context.auth.uid) {
       throw new functions.https.HttpsError("unauthenticated", "Musíš byť prihlásený.");
     }

     const uid = context.auth.uid;

     const garmentImageUrl = String(data?.garmentImageUrl || "").trim();
     const baseImageUrl = String(data?.baseImageUrl || "").trim(); // môže byť prázdne
     const slot = String(data?.slot || "").trim(); // head/neck/torsoMid...
     const sessionId = String(data?.sessionId || "").trim() || "default";

     if (!garmentImageUrl) {
       throw new functions.https.HttpsError("invalid-argument", "Chýba garmentImageUrl.");
     }
     if (!slot) {
       throw new functions.https.HttpsError("invalid-argument", "Chýba slot.");
     }

     const bucket = storage.bucket();
     const bucketName = bucket.name;

     try {
       // 1) base obrázok:
       // - ak baseImageUrl nie je, použijeme manekýna uloženého v Storage:
       //   gs://.../mannequins/male.png  (ty si ho tam dáš raz)
       let baseBuf;
       if (baseImageUrl) {
         baseBuf = await downloadUrlToBuffer(baseImageUrl);
       } else {
         // 👉 TU je “fixný” default manekýn pre MVP
         // Uploadni do Storage súbor: mannequins/male.png
         const mannequinPath = "mannequins/male.png";
         const [b] = await bucket.file(mannequinPath).download();
         baseBuf = b;
       }

       // 2) garment (tvoj cutout/product image)
       const garmentBuf = await downloadUrlToBuffer(garmentImageUrl);

       // 3) zlož obrázok
       const outBuf = await composeTryOn({ baseBuf, garmentBuf, slot });

       // 4) ulož do Storage
       const token = crypto.randomUUID();
       const outPath = `tryon/${uid}/${sessionId}/${Date.now()}_${slot}.png`;

       await bucket.file(outPath).save(outBuf, {
         contentType: "image/png",
         metadata: { metadata: { firebaseStorageDownloadTokens: token } },
       });

       const resultUrl = buildStorageDownloadUrl(bucketName, outPath, token);

       return { resultUrl, outPath };
     } catch (e) {
       logger.error("requestTryOn error:", e);
       throw new functions.https.HttpsError(
         "internal",
         "Try-on sa nepodaril: " + (e?.message || String(e))
       );
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
- "cizmy_clenkove": siahajú po členok alebo len trochu nad členok (typické šnurovacie work/turistické topánky, "hiking boots", "work boots" sú TAKMER VŽDY členkové).
- "cizmy_vysoke": siahajú jasne do polovice lýtka alebo vyššie. Nestačí, že sú len "boot" alebo že majú kožušinu – musí byť viditeľný vyšší sárok (časť nad členkom) výrazne nad úroveň členku.
- "cizmy_nad_kolena": zjavne presahujú koleno.
- Ak je fotka odfotená tak, že NEVIDNO celé lýtko alebo je to záber hlavne na chodidlo/topánku, NIKDY nevoľ "cizmy_vysoke" – v takom prípade preferuj "cizmy_clenkove".
- Ak si nie si istý medzi členkové a vysoké, preferuj členkové.
Pravidlo pre "obuv_turisticka":
- Ak ide o šnurovacie outdoor/work/hiking topánky s hrubou trakčnou podrážkou a polstrovaným okrajom, preferuj "obuv_turisticka" pred "cizmy_clenkove".


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
- Ak je na oblečení viditeľný nápis/logo značky, MUSÍŠ ho vrátiť v "brand".
- Ak nie je čitateľný, vráť "".

────────────────────────────────────────────────────────
VÝSTUP
────────────────────────────────────────────────────────
VALIDÁCIA VÝSTUPU (povinné):
- Vráť len čistý JSON.
- "colors" pole len z povolených farieb.
- "style" pole len z povolených.
- "season" pole len z ["jar","leto","jeseň","zima","celoročne"].
- "patterns" pole len z povolených.
- Okrem povinných polí vráť aj:
  - "confidence": 0.0 až 1.0
  - "debug_reason": 1-2 vety

JSON formát:
{
  "type": "Mikina s kapucňou",
  "canonical_type": "mikina_s_kapucnou",
  "colors": ["čierna"],
  "style": ["casual"],
  "season": ["celoročne"],
  "patterns": ["textová potlač"],
  "brand": "Nike",
  "confidence": 0.78,
  "debug_reason": "Viditeľná kapucňa a strih mikiny."
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

        if (raw.startsWith("```")) {
          const firstNl = raw.indexOf("\n");
          if (firstNl !== -1) raw = raw.substring(firstNl + 1);
        }
        if (raw.endsWith("```")) {
          raw = raw.substring(0, raw.lastIndexOf("```")).trim();
        }

        const jsonResponse = JSON.parse(raw);

        // ✅ BACKEND override (ponechané)
        if (jsonResponse?.canonical_type === "bunda_prechodna") {
          const brand = String(jsonResponse.brand || "").toUpperCase();
          const colors = Array.isArray(jsonResponse.colors) ? jsonResponse.colors.map(String) : [];
          const patterns = Array.isArray(jsonResponse.patterns) ? jsonResponse.patterns.map(String) : [];
          const seasonArr = Array.isArray(jsonResponse.season) ? jsonResponse.season.map(String) : [];

          const hasHoodHint =
            /kapuc/i.test(String(jsonResponse.debug_reason || "")) ||
            /hood/i.test(String(jsonResponse.debug_reason || ""));
          const isOutdoorBrand = ["HI-TEC", "COLUMBIA", "THE NORTH FACE", "NORTH FACE", "SALOMON"].some((b) =>
            brand.includes(b)
          );
          const isDark = colors.includes("čierna") || colors.includes("tmavomodrá") || colors.includes("hnedá");
          const isSolid = patterns.includes("jednofarebné");

          let score = 0;
          if (hasHoodHint) score++;
          if (isOutdoorBrand) score++;
          if (isDark && isSolid) score++;
          const onlySpringAutumn =
            seasonArr.length > 0 && seasonArr.every((s) => s === "jar" || s === "jeseň");
          if (onlySpringAutumn) score++;

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

  // ---------------------------------------------------------------------------
  // ✅ TRY-ON helpers (GEN1, Node20)
  // - stiahne PNG/JPG z URL (Firebase download URL s tokenom)
  // - zloží "base image" + "garment" cez sharp a uloží do Storage
  // ---------------------------------------------------------------------------
  async function downloadUrlToBuffer(url) {
    const r = await fetch(url);
    if (!r.ok) {
      const t = await r.text().catch(() => "");
      throw new Error(`downloadUrlToBuffer failed ${r.status}: ${t}`);
    }
    const ab = await r.arrayBuffer();
    return Buffer.from(ab);
  }

  function getTryOnBox(slot) {
    // Boxy sú v percentách z rozmeru obrázka (0..1)
    // (je to len "v0 compositor", neskôr tu nebude treba nič meniť)
    switch (slot) {
      case "head":
        return { x: 0.39, y: 0.06, w: 0.22, h: 0.22 };
      case "neck":
        return { x: 0.34, y: 0.16, w: 0.32, h: 0.22 };
      case "torsoBase":
        return { x: 0.26, y: 0.22, w: 0.48, h: 0.44 };
      case "torsoMid":
        return { x: 0.22, y: 0.20, w: 0.56, h: 0.50 };
      case "torsoOuter":
        return { x: 0.18, y: 0.18, w: 0.64, h: 0.58 };
      case "legsBase":
        return { x: 0.30, y: 0.56, w: 0.40, h: 0.36 };
      case "legsMid":
        return { x: 0.22, y: 0.52, w: 0.56, h: 0.48 };
      case "legsOuter":
        return { x: 0.20, y: 0.50, w: 0.60, h: 0.46 };
      case "shoes":
        return { x: 0.24, y: 0.82, w: 0.52, h: 0.18 };
      default:
        return { x: 0.22, y: 0.20, w: 0.56, h: 0.50 };
    }
  }

  async function composeTryOn({ baseBuf, garmentBuf, slot }) {
    // Base -> zistíme rozmery
    const baseMeta = await sharp(baseBuf).metadata();
    const W = baseMeta.width || 1024;
    const H = baseMeta.height || 1024;

    const box = getTryOnBox(slot);
    const left = Math.round(box.x * W);
    const top = Math.round(box.y * H);
    const bw = Math.round(box.w * W);
    const bh = Math.round(box.h * H);

    // garment: orež transparentný okraj, zmenši do boxu
    const gTrim = await sharp(garmentBuf)
      .ensureAlpha()
      .trim()
      .png()
      .toBuffer();

    const gResized = await sharp(gTrim)
      .resize(bw, bh, { fit: "inside" })
      .png()
      .toBuffer();

    // trochu “prirodzenejšie” = jemný tieň
    const shadow = await sharp(gResized)
      .clone()
      .blur(6)
      .modulate({ brightness: 0.25 })
      .png()
      .toBuffer();

    const out = await sharp(baseBuf)
      .ensureAlpha()
      .composite([
        { input: shadow, left: left + 6, top: top + 10, blend: "over", opacity: 0.30 },
        { input: gResized, left, top, blend: "over" },
      ])
      .png()
      .toBuffer();

    return out;
  }

  function buildStorageDownloadUrl(bucketName, path, token) {
    const encoded = encodeURIComponent(path);
    return `https://firebasestorage.googleapis.com/v0/b/${bucketName}/o/${encoded}?alt=media&token=${token}`;
  }

