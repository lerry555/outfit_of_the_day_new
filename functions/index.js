// functions/index.js (GEN1 - Node 20)
// - Storage trigger: removeBackgroundOnUpload (rembg Cloud Run)
// - Storage trigger: createProductPhotoOnCleanUpload (Sharp - E-shop look)
// - Firestore trigger: attachCleanImageOnWardrobeWrite
// - Firestore trigger: attachCleanImageOnMapWrite
// - Firestore trigger: attachProductImageOnMapWrite
// - HTTPS: analyzeClothingImage (OpenAI Vision)
// - HTTPS: chatWithStylist (OpenAI text)
// - Callable: requestTryOn
// - Callable: requestTryOnJob

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

// sem si neskôr môžeš dať config, ak by si menil URL servera
function getRemBgServerUrl() {
  return (
    process.env.REMBG_SERVER_URL ||
    getConfigValue(["rembg", "server_url"]) ||
    "https://rembg-server-221686818701.us-central1.run.app"
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

  items.sort((a, b) =>
    a.order === b.order ? a.originalIndex - b.originalIndex : a.order - b.order
  );

  const usedSlots = new Set();
  const result = [];

  for (const item of items) {
    if (item.slot === "shoes" && usedSlots.has("shoes")) continue;
    result.push(item.url);
    usedSlots.add(item.slot);
  }

  return result;
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

function isRetryableHttpStatus(status) {
  return status === 429 || (status >= 500 && status <= 599);
}

// ---------------------------------------------------------------------------
// ✅ rembg Cloud Run helpers
// ---------------------------------------------------------------------------
async function removeBackgroundCallOnce({ buf, contentType }) {
  const serverUrl = getRemBgServerUrl();

  const form = new FormData();
  form.append(
    "image",
    new Blob([buf], { type: contentType || "image/jpeg" }),
    "input.jpg"
  );

  const res = await fetch(`${serverUrl}/remove-bg`, {
    method: "POST",
    body: form,
  });

  if (!res.ok) {
    const body = await res.text().catch(() => "");
    const err = new Error(`rembg failed ${res.status}`);
    err.status = res.status;
    err.body = body;
    throw err;
  }

  const out = Buffer.from(await res.arrayBuffer());

  logger.info("rembg background removal OK", {
    outputBytes: out.length,
  });

  return out;
}

async function removeBackgroundWithRetry({ buf, contentType }) {
  const delays = [0, 1200, 3000];
  let lastErr = null;

  for (let attempt = 0; attempt < delays.length; attempt++) {
    if (delays[attempt] > 0) await sleep(delays[attempt]);

    try {
      return await removeBackgroundCallOnce({ buf, contentType });
    } catch (e) {
      lastErr = e;

      const status = Number(e?.status || 0);
      const retryable = status === 0 || isRetryableHttpStatus(status);

      logger.warn("rembg attempt failed", {
        attempt: attempt + 1,
        status,
        retryable,
        msg: e?.message || "",
        body: e?.body || null,
      });

      if (!retryable) throw e;
    }
  }

  throw lastErr || new Error("rembg failed (unknown)");
}

async function markCutoutError(uid, originalStoragePath, message) {
  try {
    const wardrobeRef = db.collection("users").doc(uid).collection("wardrobe");
    const snap = await wardrobeRef.where("storagePath", "==", originalStoragePath).get();

    if (snap.empty) return;

    for (const doc of snap.docs) {
      const existingProduct = doc.data()?.processing?.product;
      await doc.ref.set(
        {
          processing: {
            cutout: "error",
            product: existingProduct || "queued",
          },
          cutoutErrorMessage: String(message || "background removal error"),
          cutoutImageUrl: null,
          cleanImageUrl: null,
          cleanStoragePath: null,
          cleanUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    }
  } catch (e) {
    logger.error("markCutoutError failed:", e);
  }
}

// ---------------------------------------------------------------------------
// ✅ GEN1 Storage Trigger: removeBackgroundOnUpload – rembg Cloud Run
// ---------------------------------------------------------------------------
exports.removeBackgroundOnUpload = functions
  .region("us-central1")
  .runWith({
    memory: "1GB",
    timeoutSeconds: 540,
    maxInstances: 2,
  })
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

    try {
      const bucket = storage.bucket(bucketName);

      // 1) download originál
      const [buf] = await bucket.file(filePath).download();

      // 2) rembg remove background (+ retry)
      const cleanBuffer = await removeBackgroundWithRetry({ buf, contentType });

      // 3) save PNG do wardrobe_clean/{uid}/...
      const baseName = (filePath.split("/").pop() || "item").replace(/\.[^/.]+$/, "");
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

      // 4) mapping
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

      // 5) update Firestore wardrobe doc
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
              cutoutImageUrl: cleanImageUrl,
              processing: {
                cutout: "done",
                product: existingProduct || "queued",
              },
            },
            { merge: true }
          );

          updated++;
        }
      }

      logger.info("removeBackgroundOnUpload (rembg) OK", {
        filePath,
        cleanPath,
        updated,
      });

      return null;
    } catch (err) {
      logger.error("removeBackgroundOnUpload error:", {
        filePath,
        message: err?.message || String(err),
        status: err?.status || null,
        body: err?.body || null,
      });

      await markCutoutError(uid, filePath, err?.body || err?.message || "rembg_error");
      return null;
    }
  });

// ---------------------------------------------------------------------------
// ✅ GEN1 Storage Trigger: createProductPhotoOnCleanUpload (E-shop look)
// ---------------------------------------------------------------------------
exports.createProductPhotoOnCleanUpload = functions
  .region("us-central1")
  .runWith({
    memory: "2GB",
    timeoutSeconds: 120,
    maxInstances: 2,
  })
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

    const CANVAS = 1024;
    const ITEM_MAX = 780;
    const BG = "#FFFFFF";
    const SHADOW_DY = 26;
    const SHADOW_BLUR = 18;
    const SHADOW_OPACITY = 0.22;

    try {
      const [inputBuf] = await bucket.file(filePath).download();

      const trimmed = await sharp(inputBuf)
        .ensureAlpha()
        .trim()
        .png()
        .toBuffer();

      const resizedItem = await sharp(trimmed)
        .resize(ITEM_MAX, ITEM_MAX, { fit: "inside" })
        .png()
        .toBuffer();

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

      const prodMapId = Buffer.from(`${uid}|${filePath}`).toString("base64").replace(/[/+=]/g, "_");
      await db.collection("storage_product_map").doc(prodMapId).set(
        {
          uid,
          cleanPath: filePath,
          productPath,
          productImageUrl,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );

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

      logger.info("createProductPhotoOnCleanUpload OK", {
        filePath,
        productPath,
        updatedDocs: snap.size,
      });

      return null;
    } catch (e) {
      logger.error("createProductPhotoOnCleanUpload ERROR", { filePath, e });

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
// + produkt image ak už map existuje
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

    const cleanStoragePath = String(after.cleanStoragePath || "");
    const hasClean = !!(after.cleanImageUrl && String(after.cleanImageUrl).length > 0);
    const hasCutout = !!(after.cutoutImageUrl && String(after.cutoutImageUrl).length > 0);
    const hasProduct = !!(after.productImageUrl && String(after.productImageUrl).length > 0);

    async function tryAttachProductFromMap(cleanPath) {
      try {
        if (!cleanPath || hasProduct) return;

        const prodMapId = Buffer.from(`${uid}|${cleanPath}`)
          .toString("base64")
          .replace(/[/+=]/g, "_");

        const prodSnap = await db.collection("storage_product_map").doc(prodMapId).get();
        if (!prodSnap.exists) return;

        const prod = prodSnap.data() || {};
        const productImageUrl = String(prod.productImageUrl || "");
        const productPath = String(prod.productPath || "");

        if (!productImageUrl) return;

        await change.after.ref.set(
          {
            productImageUrl,
            productStoragePath: productPath || null,
            productUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
            processing: { product: "done" },
          },
          { merge: true }
        );

        logger.info("attachCleanImageOnWardrobeWrite: attached productImageUrl from storage_product_map", {
          uid,
          cleanPath,
        });
      } catch (e) {
        logger.warn("tryAttachProductFromMap failed", { uid, cleanPath, e: String(e) });
      }
    }

    if (hasClean && !hasCutout) {
      await change.after.ref.set(
        {
          cutoutImageUrl: String(after.cleanImageUrl),
          processing: {
            cutout: "done",
            product: after?.processing?.product || (hasProduct ? "done" : "queued"),
          },
        },
        { merge: true }
      );

      await tryAttachProductFromMap(cleanStoragePath);

      logger.info("attachCleanImageOnWardrobeWrite: filled cutoutImageUrl from existing cleanImageUrl", { uid });
      return null;
    }

    if (hasClean && hasCutout) {
      await tryAttachProductFromMap(cleanStoragePath);
      return null;
    }

    try {
      const mapId = Buffer.from(`${uid}|${storagePath}`).toString("base64").replace(/[/+=]/g, "_");
      const mapSnap = await db.collection("storage_clean_map").doc(mapId).get();
      if (!mapSnap.exists) return null;

      const mapData = mapSnap.data() || {};
      const cleanImageUrl = String(mapData.cleanImageUrl || "");
      const cleanPath = String(mapData.cleanPath || "");

      if (!cleanImageUrl || !cleanPath) return null;

      await change.after.ref.set(
        {
          cleanImageUrl,
          cleanStoragePath: cleanPath,
          cleanUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
          cutoutImageUrl: cleanImageUrl,
          processing: {
            cutout: "done",
            product: after?.processing?.product || (hasProduct ? "done" : "queued"),
          },
        },
        { merge: true }
      );

      await tryAttachProductFromMap(cleanPath);

      logger.info("attachCleanImageOnWardrobeWrite OK", { uid, storagePath });
      return null;
    } catch (e) {
      logger.error("attachCleanImageOnWardrobeWrite error:", e);
      return null;
    }
  });
  // ---------------------------------------------------------------------------
  // ✅ Firestore Trigger: keď sa vytvorí storage_clean_map -> doplň wardrobe
  // ---------------------------------------------------------------------------
  exports.attachCleanImageOnMapWrite = functions
    .region("us-central1")
    .firestore.document("storage_clean_map/{mapId}")
    .onCreate(async (snap, context) => {
      const data = snap.data() || {};

      const uid = String(data.uid || "");
      const originalPath = String(data.originalPath || data.storagePath || "");
      const cleanImageUrl = String(data.cleanImageUrl || "");
      const cleanStoragePath = String(data.cleanPath || data.cleanStoragePath || "");

      if (!uid || !originalPath || !cleanImageUrl || !cleanStoragePath) {
        logger.warn("attachCleanImageOnMapWrite: missing fields", {
          uid,
          originalPath,
          hasClean: !!cleanImageUrl,
          hasCleanPath: !!cleanStoragePath,
        });
        return null;
      }

      const q = await db
        .collection("users")
        .doc(uid)
        .collection("wardrobe")
        .where("storagePath", "==", originalPath)
        .limit(10)
        .get();

      if (q.empty) {
        logger.warn("attachCleanImageOnMapWrite: no wardrobe item found", { uid, originalPath });
        return null;
      }

      const batch = db.batch();

      q.docs.forEach((doc) => {
        const after = doc.data() || {};
        const hasCutout = !!(after.cutoutImageUrl && String(after.cutoutImageUrl).length > 0);
        const hasClean = !!(after.cleanImageUrl && String(after.cleanImageUrl).length > 0);

        if (hasClean && hasCutout) return;

        batch.set(
          doc.ref,
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
      });

      await batch.commit();

      logger.info("attachCleanImageOnMapWrite OK", { uid, originalPath, docs: q.size });
      return null;
    });

  // ---------------------------------------------------------------------------
  // ✅ Firestore Trigger: keď sa vytvorí storage_product_map -> doplň wardrobe
  // ---------------------------------------------------------------------------
  exports.attachProductImageOnMapWrite = functions
    .region("us-central1")
    .firestore.document("storage_product_map/{mapId}")
    .onCreate(async (snap, context) => {
      const data = snap.data() || {};

      const uid = String(data.uid || "");
      const cleanPath = String(data.cleanPath || "");
      const productImageUrl = String(data.productImageUrl || "");
      const productPath = String(data.productPath || "");

      if (!uid || !cleanPath || !productImageUrl) {
        logger.warn("attachProductImageOnMapWrite: missing fields", {
          uid,
          cleanPath,
          hasProduct: !!productImageUrl,
        });
        return null;
      }

      let q = await db
        .collection("users")
        .doc(uid)
        .collection("wardrobe")
        .where("cleanStoragePath", "==", cleanPath)
        .limit(10)
        .get();

      if (q.empty) {
        try {
          const mapQ = await db
            .collection("storage_clean_map")
            .where("uid", "==", uid)
            .where("cleanPath", "==", cleanPath)
            .limit(1)
            .get();

          if (!mapQ.empty) {
            const originalPath = String(mapQ.docs[0].data()?.originalPath || "");
            if (originalPath) {
              q = await db
                .collection("users")
                .doc(uid)
                .collection("wardrobe")
                .where("storagePath", "==", originalPath)
                .limit(10)
                .get();
            }
          }
        } catch (e) {
          logger.warn("attachProductImageOnMapWrite fallback failed", { uid, cleanPath, e: String(e) });
        }
      }

      if (q.empty) {
        logger.warn("attachProductImageOnMapWrite: no wardrobe item found (even after fallback)", { uid, cleanPath });
        return null;
      }

      const batch = db.batch();

      q.docs.forEach((doc) => {
        batch.set(
          doc.ref,
          {
            productImageUrl,
            productStoragePath: productPath || null,
            productUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
            processing: { product: "done" },
          },
          { merge: true }
        );
      });

      await batch.commit();

      logger.info("attachProductImageOnMapWrite OK", { uid, cleanPath, docs: q.size });
      return null;
    });

  // ---------------------------------------------------------------------------
  // ✅ requestTryOn – GEN1 HTTPS (Callable)
  // ---------------------------------------------------------------------------
  exports.requestTryOn = functions
    .region("us-central1")
    .https.onCall(async (data, context) => {
      if (!context.auth || !context.auth.uid) {
        throw new functions.https.HttpsError("unauthenticated", "Musíš byť prihlásený.");
      }

      const uid = context.auth.uid;

      const garmentImageUrl = String(data?.garmentImageUrl || "").trim();
      const baseImageUrl = String(data?.baseImageUrl || "").trim();
      const slot = String(data?.slot || "").trim();
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
        let baseBuf;
        if (baseImageUrl) {
          baseBuf = await downloadUrlToBuffer(baseImageUrl);
        } else {
          const mannequinPath = "mannequins/male.png";
          const [b] = await bucket.file(mannequinPath).download();
          baseBuf = b;
        }

        const garmentBuf = await downloadUrlToBuffer(garmentImageUrl);
        const outBuf = await composeTryOn({ baseBuf, garmentBuf, slot });

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
        logger.error("Chýba OPENAI_API_KEY (env alebo functions.config().openai.key)");
        return res.status(500).send("Server nemá nastavený OPENAI_API_KEY.");
      }

      const ALLOWED_SEASONS = ["jar", "leto", "jeseň", "zima", "celoročne"];
      const ALLOWED_PATTERNS = [
        "jednofarebné",
        "pruhované",
        "kockované",
        "bodkované",
        "kvetované",
        "maskáčové",
        "animal print",
        "grafické",
        "iný vzor",
      ];
      const ALLOWED_STYLES = [
        "elegantný",
        "casual",
        "streetwear",
        "športový",
        "business",
        "outdoor",
        "basic",
        "party",
      ];
      const ALLOWED_COLORS = [
        "čierna",
        "biela",
        "sivá",
        "tmavomodrá",
        "modrá",
        "svetlomodrá",
        "zelená",
        "olivová",
        "khaki",
        "hnedá",
        "béžová",
        "červená",
        "bordová",
        "žltá",
        "oranžová",
        "ružová",
        "fialová",
      ];

      const COLOR_MAP = {
        navy: "tmavomodrá",
        "dark blue": "tmavomodrá",
        midnight: "tmavomodrá",
        blue: "modrá",
        "light blue": "svetlomodrá",
        black: "čierna",
        white: "biela",
        grey: "sivá",
        gray: "sivá",
        beige: "béžová",
        brown: "hnedá",
        tan: "hnedá",
        olive: "olivová",
        khaki: "khaki",
        green: "zelená",
        red: "červená",
        burgundy: "bordová",
        maroon: "bordová",
        yellow: "žltá",
        orange: "oranžová",
        pink: "ružová",
        purple: "fialová",
      };

      const STYLE_MAP = {
        elegant: "elegantný",
        formal: "elegantný",
        smart: "business",
        business: "business",
        casual: "casual",
        street: "streetwear",
        streetwear: "streetwear",
        sport: "športový",
        sports: "športový",
        athletic: "športový",
        outdoor: "outdoor",
        basic: "basic",
        party: "party",
      };

      const PATTERN_MAP = {
        solid: "jednofarebné",
        plain: "jednofarebné",
        striped: "pruhované",
        stripes: "pruhované",
        checked: "kockované",
        plaid: "kockované",
        dots: "bodkované",
        polka: "bodkované",
        floral: "kvetované",
        camo: "maskáčové",
        camouflage: "maskáčové",
        animal: "animal print",
        graphic: "grafické",
      };

      const SEASON_MAP = {
        spring: "jar",
        summer: "leto",
        autumn: "jeseň",
        fall: "jeseň",
        winter: "zima",
        all: "celoročne",
        "all season": "celoročne",
        year: "celoročne",
      };

      function toStringArray(x) {
        if (!x) return [];
        if (Array.isArray(x)) return x.map((v) => String(v).trim()).filter(Boolean);
        return [String(x).trim()].filter(Boolean);
      }

      function normalizeToAllowed(value, allowed, map) {
        const raw = String(value || "").toLowerCase().trim();
        if (!raw) return null;

        const exact = allowed.find((a) => a.toLowerCase() === raw);
        if (exact) return exact;

        if (map[raw] && allowed.includes(map[raw])) return map[raw];

        for (const k of Object.keys(map)) {
          if (raw.includes(k)) {
            const m = map[k];
            if (allowed.includes(m)) return m;
          }
        }
        return null;
      }

      function stripCodeFences(text) {
        let raw = String(text || "").trim();
        if (raw.startsWith("```")) {
          const firstNl = raw.indexOf("\n");
          if (firstNl !== -1) raw = raw.substring(firstNl + 1);
        }
        if (raw.endsWith("```")) {
          raw = raw.substring(0, raw.lastIndexOf("```")).trim();
        }
        return raw.trim();
      }

      try {
        const systemPrompt = `
  Si profesionálny módny stylista a expert na rozpoznávanie oblečenia z fotiek pre mobilnú aplikáciu.
  Vráť STRICTNE jeden JSON objekt. Nepíš žiadny iný text. Žiadny markdown. Žiadne \`\`\`.

  MUSÍŠ vrátiť VŽDY všetky tieto kľúče (aj keď sú prázdne):
  {
    "type": "krátky názov v slovenčine (napr. \\"Nohavice\\")",
    "type_pretty": "detailnejší názov v slovenčine (napr. \\"Chino nohavice\\")",
    "canonical_type": "technický kľúč v angličtine (napr. pants, jeans, t_shirt, hoodie...)",
    "brand": "značka alebo prázdny string",
    "colors": ["zoznam farieb v slovenčine"],
    "styles": ["zoznam štýlov v slovenčine"],
    "patterns": ["max 1 vzor v slovenčine"],
    "seasons": ["zoznam sezón v slovenčine"],
    "debug_reason": "stručný dôvod rozhodnutí (1 veta)"
  }

  Použi LEN tieto povolené hodnoty:
  FARBY (colors): ${JSON.stringify(ALLOWED_COLORS)}
  ŠTÝLY (styles): ${JSON.stringify(ALLOWED_STYLES)}
  VZORY (patterns): ${JSON.stringify(ALLOWED_PATTERNS)}
  SEZÓNY (seasons): ${JSON.stringify(ALLOWED_SEASONS)}

  Pravidlá:
  - Ak si nie si istý farbou/štýlom/vzorom/sezónou, radšej vráť prázdne pole alebo "jednofarebné" pri vzore.
  - patterns: vráť buď [] alebo [jedna_hodnota]
  - seasons: ak je vhodné celoročne, vráť ["celoročne"].
  - type_pretty má byť prirodzený názov pre človeka, ale bez zdvojení typu.
        `.trim();

        const openAiBody = {
          model: "gpt-4o-mini",
          temperature: 0.1,
          messages: [
            { role: "system", content: systemPrompt },
            {
              role: "user",
              content: [
                {
                  type: "text",
                  text: "Analyzuj tento jeden kus oblečenia na fotke a vráť JSON podľa inštrukcií.",
                },
                { type: "image_url", image_url: { url: imageUrl } },
              ],
            },
          ],
        };

        const response = await fetch("https://api.openai.com/v1/chat/completions", {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${apiKey}`,
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

        const raw = stripCodeFences(text);
        logger.info("AI RAW TEXT:", raw);

        let parsed = null;
        try {
          parsed = JSON.parse(raw);
        } catch (e) {
          logger.error("JSON.parse failed:", e);
        }

        const p = parsed && typeof parsed === "object" ? parsed : {};

        const out = {
          type: String(p.type || ""),
          type_pretty: String(p.type_pretty || ""),
          canonical_type: String(p.canonical_type || ""),
          brand: String(p.brand || ""),
          colors: toStringArray(p.colors),
          styles: toStringArray(p.styles),
          patterns: toStringArray(p.patterns),
          seasons: toStringArray(p.seasons),
          debug_reason: String(p.debug_reason || ""),
        };

        const colors = [];
        for (const c of out.colors) {
          const mapped = normalizeToAllowed(c, ALLOWED_COLORS, COLOR_MAP);
          if (mapped && !colors.includes(mapped)) colors.push(mapped);
        }

        const styles = [];
        for (const s of out.styles) {
          const mapped = normalizeToAllowed(s, ALLOWED_STYLES, STYLE_MAP);
          if (mapped && !styles.includes(mapped)) styles.push(mapped);
        }

        let patterns = [];
        for (const pat of out.patterns) {
          const mapped = normalizeToAllowed(pat, ALLOWED_PATTERNS, PATTERN_MAP);
          if (mapped) {
            patterns = [mapped];
            break;
          }
        }

        let seasons = [];
        for (const sea of out.seasons) {
          const mapped = normalizeToAllowed(sea, ALLOWED_SEASONS, SEASON_MAP);
          if (mapped && !seasons.includes(mapped)) seasons.push(mapped);
        }

        const hasAllFour = ["jar", "leto", "jeseň", "zima"].every((x) => seasons.includes(x));
        if (seasons.includes("celoročne") || hasAllFour) seasons = ["celoročne"];

        const normalized = {
          type: out.type || out.type_pretty || "",
          type_pretty: out.type_pretty || out.type || "",
          canonical_type: out.canonical_type,
          brand: out.brand,
          colors,
          styles,
          patterns,
          seasons,
          debug_reason: out.debug_reason,
        };

        if (!normalized.patterns || normalized.patterns.length === 0) {
          normalized.patterns = ["jednofarebné"];
        }

        logger.info("AI NORMALIZED OUT:", normalized);
        return res.status(200).send(normalized);
      } catch (error) {
        logger.error("Chyba pri analyzeClothingImage:", error);
        return res.status(500).send(
          "Chyba servera pri analýze obrázka: " + (error.message || String(error))
        );
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
      if (req.method !== "POST") {
        return res.status(405).send("Metóda nie je povolená. Použite POST.");
      }

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
          const rawOutfitImages = Array.isArray(jsonResponse.outfit_images)
            ? jsonResponse.outfit_images
            : [];
          const outfitImages = normalizeOutfitImages(rawOutfitImages, wardrobe);

          return res.status(200).send({ replyText, imageUrls: outfitImages });
        } catch (e) {
          logger.error("OpenAI nevrátil platný JSON:", text);
          return res.status(200).send({ replyText: text, imageUrls: [] });
        }
      } catch (error) {
        logger.error("Chyba pri volaní OpenAI API:", error);
        return res.status(500).send(
          "Chyba servera pri AI stylistovi: " + (error.message || String(error))
        );
      }
    });

  // ---------------------------------------------------------------------------
  // ✅ TRY-ON helpers (GEN1, Node20)
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
    const baseMeta = await sharp(baseBuf).metadata();
    const W = baseMeta.width || 1024;
    const H = baseMeta.height || 1024;

    const box = getTryOnBox(slot);
    const left = Math.round(box.x * W);
    const top = Math.round(box.y * H);
    const bw = Math.round(box.w * W);
    const bh = Math.round(box.h * H);

    const gTrim = await sharp(garmentBuf)
      .ensureAlpha()
      .trim()
      .png()
      .toBuffer();

    const gResized = await sharp(gTrim)
      .resize(bw, bh, { fit: "inside" })
      .png()
      .toBuffer();

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

  // ===========================================================================
  // ✅ requestTryOnJob
  // ===========================================================================
  exports.requestTryOnJob = functions
    .region("us-central1")
    .https.onCall(async (data, context) => {
      if (!context.auth || !context.auth.uid) {
        throw new functions.https.HttpsError("unauthenticated", "Musíš byť prihlásený.");
      }

      const uid = context.auth.uid;

      const garmentImageUrl = String(data?.garmentImageUrl || "").trim();
      const slot = String(data?.slot || "").trim();
      const sessionId = String(data?.sessionId || "").trim();
      const mannequinGender = String(data?.mannequinGender || "male").trim();

      if (!garmentImageUrl) {
        throw new functions.https.HttpsError("invalid-argument", "Chýba garmentImageUrl.");
      }
      if (!slot) {
        throw new functions.https.HttpsError("invalid-argument", "Chýba slot.");
      }
      if (!sessionId) {
        throw new functions.https.HttpsError("invalid-argument", "Chýba sessionId.");
      }

      const bucket = storage.bucket();
      const bucketName = bucket.name;

      const jobRef = db.collection("users").doc(uid).collection("tryon_jobs").doc();
      const jobId = jobRef.id;
      const now = admin.firestore.FieldValue.serverTimestamp();

      await jobRef.set(
        {
          status: "queued",
          createdAt: now,
          updatedAt: now,
          params: { garmentImageUrl, slot, sessionId, mannequinGender },
        },
        { merge: true }
      );

      try {
        await jobRef.set({ status: "processing", updatedAt: now }, { merge: true });

        const garmentBuf = await downloadUrlToBuffer(garmentImageUrl);

        const resultPath = `tryon_results/${uid}/${jobId}.png`;
        const token = crypto.randomUUID();

        await bucket.file(resultPath).save(garmentBuf, {
          contentType: "image/png",
          metadata: { metadata: { firebaseStorageDownloadTokens: token } },
        });

        const resultUrl = buildStorageDownloadUrl(bucketName, resultPath, token);

        await jobRef.set(
          { status: "done", updatedAt: now, resultPath, resultUrl },
          { merge: true }
        );

        return { jobId };
      } catch (e) {
        logger.error("requestTryOnJob error:", e);

        await jobRef.set(
          { status: "error", updatedAt: now, errorMessage: e?.message || String(e) },
          { merge: true }
        );

        throw new functions.https.HttpsError(
          "internal",
          "Try-on job sa nepodaril: " + (e?.message || String(e))
        );
      }
    });

// ---------------------------------------------------------------------------
// ✅ analyzeWardrobeSmart – GEN1 Callable (compact wardrobe structure analysis)
// ---------------------------------------------------------------------------
// Flutter example:
// final callable = FirebaseFunctions.instance.httpsCallable('analyzeWardrobeSmart');
// final result = await callable.call();
// final json = Map<String, dynamic>.from(result.data as Map);
// print(json['strengths']);
exports.analyzeWardrobeSmart = functions
  .region("us-east1")
  .runWith({ timeoutSeconds: 60, memory: "512MB" })
  .https.onCall(async (data, context) => {
    const uid = context?.auth?.uid;
    if (!uid) {
      throw new functions.https.HttpsError("unauthenticated", "Musíš byť prihlásený.");
    }

    const requestId =
      context?.rawRequest?.headers?.["x-cloud-trace-context"] ||
      context?.rawRequest?.headers?.["x-request-id"] ||
      null;

    const fallback = {
      strengths: [
        "Máš dobrý základ šatníka, ktorý sa dá ďalej zlepšovať.",
        "Z tvojich kúskov sa dá poskladať viac kombinácií, keď upravíme pár pomerov.",
        "S malými doplneniami vieš výrazne zvýšiť počet outfitov.",
      ],
      weaknesses: [
        "Niektoré kategórie môžu byť nevyvážené (napr. veľa vrchov vs. málo spodkov).",
        "Môže chýbať pár univerzálnych neutrálnych kúskov na jednoduché kombinovanie.",
        "Sezónnosť a vrstvenie sa dá posilniť pár praktickými voľbami.",
      ],
      buyNext: [
        "Zváž doplnenie 1–2 univerzálnych neutrálnych kúskov, ktoré pasujú k väčšine šatníka.",
        "Ak ti chýbajú spodné diely, doplň aspoň jeden ľahko kombinovateľný variant.",
        "Pridaj jednu vrstvu na vrstvenie (napr. kardigán alebo ľahkú bundu) pre viac možností.",
      ],
      outfitPotential: [
        "Skús stavať outfity okolo neutrálnych základov a jeden výrazný prvok nech je iba doplnok.",
        "Zvyš počet kombinácií tým, že budeš striedať topy so spodkami v podobnej farebnej palete.",
        "Vytvor si 2–3 jednoduché kapsulové „sety“ (top + spodok + vrstva) pre rýchle obliekanie.",
      ],
    };

    function normalizeKey(v) {
      const s = String(v || "").trim();
      if (!s) return null;
      return s.toLowerCase();
    }

    function toStringArray(x) {
      if (!x) return [];
      if (Array.isArray(x)) return x.map((v) => String(v).trim()).filter(Boolean);
      return [String(x).trim()].filter(Boolean);
    }

    function inc(map, key) {
      if (!key) return;
      map[key] = (map[key] || 0) + 1;
    }

    function extractFirstJsonObject(text) {
      const raw = String(text || "").trim();
      if (!raw) return null;

      // strip code fences if present
      let t = raw;
      if (t.startsWith("```")) {
        const firstNl = t.indexOf("\n");
        if (firstNl !== -1) t = t.substring(firstNl + 1);
      }
      if (t.endsWith("```")) {
        t = t.substring(0, t.lastIndexOf("```")).trim();
      }

      // Try direct parse first.
      try {
        const parsed = JSON.parse(t);
        return parsed && typeof parsed === "object" ? parsed : null;
      } catch (_) {}

      // Fallback: find first {...} block.
      const start = t.indexOf("{");
      if (start === -1) return null;
      let depth = 0;
      for (let i = start; i < t.length; i++) {
        const ch = t[i];
        if (ch === "{") depth++;
        if (ch === "}") depth--;
        if (depth === 0) {
          const candidate = t.slice(start, i + 1);
          try {
            const parsed = JSON.parse(candidate);
            return parsed && typeof parsed === "object" ? parsed : null;
          } catch (_) {
            return null;
          }
        }
      }
      return null;
    }

    function asResultShape(obj) {
      const o = obj && typeof obj === "object" ? obj : {};

      const pickArray = (k) =>
        Array.isArray(o[k]) ? o[k].map((x) => String(x).trim()).filter(Boolean) : [];

      const out = {
        strengths: pickArray("strengths").slice(0, 5),
        weaknesses: pickArray("weaknesses").slice(0, 5),
        buyNext: pickArray("buyNext").slice(0, 5),
        outfitPotential: pickArray("outfitPotential").slice(0, 5),
      };

      const ensureLen = (arr) => (arr.length >= 3 ? arr : null);
      if (
        ensureLen(out.strengths) &&
        ensureLen(out.weaknesses) &&
        ensureLen(out.buyNext) &&
        ensureLen(out.outfitPotential)
      ) {
        return out;
      }

      return null;
    }

    logger.info("analyzeWardrobeSmart: start", {
      uid,
      requestId,
    });

    try {
      const apiKey = getOpenAiKey();
      if (!apiKey) {
        logger.error("analyzeWardrobeSmart: missing OPENAI_API_KEY", { uid, requestId });
        return fallback;
      }

      const snap = await db.collection("users").doc(uid).collection("wardrobe").get();
      const totalItems = snap.size;

      const countByMainGroup = Object.create(null);
      const countByColor = Object.create(null);
      const countByStyle = Object.create(null);
      const countBySeason = Object.create(null);

      for (const doc of snap.docs) {
        const it = doc.data() || {};

        // Extract ONLY lightweight fields (do not log them).
        const mainGroup = normalizeKey(it.mainGroup);
        const categoryKey = normalizeKey(it.categoryKey); // currently unused in summary, intentionally not sent
        const colors = toStringArray(it.colors).map(normalizeKey).filter(Boolean);
        const styles = toStringArray(it.styles).map(normalizeKey).filter(Boolean);
        const seasons = toStringArray(it.seasons).map(normalizeKey).filter(Boolean);
        const brand = String(it.brand || "").trim(); // intentionally unused in summary
        const name = String(it.name || "").trim(); // intentionally unused in summary

        // Keep linter happy about intentionally-unused lightweight fields.
        void categoryKey;
        void brand;
        void name;

        inc(countByMainGroup, mainGroup || "unknown");
        for (const c of colors) inc(countByColor, c);
        for (const s of styles) inc(countByStyle, s);
        for (const se of seasons) inc(countBySeason, se);
      }

      const summary = {
        totalItems,
        countByMainGroup,
        countByColor,
        countByStyle,
        countBySeason,
      };

      logger.info("analyzeWardrobeSmart: summary built", {
        uid,
        requestId,
        totalItems,
        mainGroups: Object.keys(countByMainGroup).length,
        colors: Object.keys(countByColor).length,
        styles: Object.keys(countByStyle).length,
        seasons: Object.keys(countBySeason).length,
      });

      const systemPrompt =
        `You are a friendly professional personal wardrobe stylist inside a mobile fashion app.\n\n` +
        `Your goal is NOT to talk about global fashion trends.\n` +
        `Your goal is to analyze the user's wardrobe structure and give practical advice.\n\n` +
        `Focus on:\n` +
        `- balance between clothing categories\n` +
        `- neutral vs statement pieces\n` +
        `- outfit combinability\n` +
        `- layering potential\n` +
        `- missing universal items\n` +
        `- increasing number of possible outfits\n\n` +
        `Write short, practical, friendly bullet points in Slovak language.\n\n` +
        `Return STRICT JSON with structure:\n\n` +
        `{\n` +
        `  "strengths": [],\n` +
        `  "weaknesses": [],\n` +
        `  "buyNext": [],\n` +
        `  "outfitPotential": []\n` +
        `}\n\n` +
        `Each array should contain 3–5 short sentences.`;

      const userPrompt =
        `Wardrobe summary (counts only): ${JSON.stringify(summary)}\n` +
        `Return ONLY the strict JSON object. No markdown.`;

      const body = {
        model: "gpt-4o-mini",
        temperature: 0.4,
        max_tokens: 500,
        messages: [
          { role: "system", content: systemPrompt },
          { role: "user", content: userPrompt },
        ],
      };

      const startedAt = Date.now();
      const response = await fetch("https://api.openai.com/v1/chat/completions", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${apiKey}`,
        },
        body: JSON.stringify(body),
      });

      const elapsedMs = Date.now() - startedAt;
      if (!response.ok) {
        const errorText = await response.text().catch(() => "");
        logger.error("analyzeWardrobeSmart: OpenAI error", {
          uid,
          requestId,
          status: response.status,
          elapsedMs,
          errorText: String(errorText || "").slice(0, 800),
        });
        return fallback;
      }

      const json = await response.json();
      const text = json?.choices?.[0]?.message?.content || "";

      logger.info("analyzeWardrobeSmart: OpenAI response received", {
        uid,
        requestId,
        elapsedMs,
        contentLength: String(text).length,
      });

      const parsed = extractFirstJsonObject(text);
      const shaped = asResultShape(parsed);
      if (!shaped) {
        logger.warn("analyzeWardrobeSmart: invalid AI JSON shape, returning fallback", {
          uid,
          requestId,
        });
        return fallback;
      }

      return shaped;
    } catch (e) {
      logger.error("analyzeWardrobeSmart: unhandled error, returning fallback", {
        uid,
        requestId,
        message: e?.message || String(e),
      });
      return fallback;
    }
  });