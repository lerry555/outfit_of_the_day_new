// functions/index.js (GEN1 - Node 20)
// - Storage trigger: removeBackgroundOnUpload (rembg Cloud Run)
// - Storage trigger: createProductPhotoOnCleanUpload (Sharp - E-shop look)
// - Firestore trigger: attachCleanImageOnWardrobeWrite
// - Firestore trigger: attachCleanImageOnMapWrite
// - Firestore trigger: attachProductImageOnMapWrite
// - Firestore trigger: processWardrobeProductLinkImage (users/{uid}/wardrobe/{itemId})
// - HTTPS: analyzeClothingImage (OpenAI Vision)
// - Callable: analyzeClothingProductUrl (product link metadata + OpenAI)
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
      const productBuf = await buildProductPhotoBuffer(inputBuf, {
        canvas: CANVAS,
        itemMax: ITEM_MAX,
        bg: BG,
        shadowDy: SHADOW_DY,
        shadowBlur: SHADOW_BLUR,
        shadowOpacity: SHADOW_OPACITY,
      });

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
  // ✅ Product-link wardrobe: deferred image improvement (after save)
  // ---------------------------------------------------------------------------
  function seedUrlLooksLikeModelPhoto(imageUrl, sourceUrl = "", title = "") {
    const u = String(imageUrl || "").toLowerCase();
    if (!u) return false;
    if (urlHasStrongPersonHints(imageUrl)) return true;
    if (imageMetadataSuggestsPerson(imageUrl, `${title} ${sourceUrl}`.trim())) return true;
    if (
      u.includes("static.nike.com") &&
      (u.includes("/w_") || u.includes(",w_") || u.includes("c_limit") || u.includes("f_auto"))
    ) {
      return true;
    }
    return false;
  }

  function seedUrlLooksLikeCleanPackshot(imageUrl, sourceUrl = "") {
    const url = String(imageUrl || "").trim();
    if (!url || !isValidHttpUrl(url)) return false;
    if (seedUrlLooksLikeModelPhoto(url, sourceUrl)) return false;
    const score = scoreCleanupImageCandidate(url, {});
    return score >= CLEANUP_PACKSHOT_MIN_SCORE;
  }

  async function runWardrobeProductLinkBackgroundJob(uid, itemId, data) {
    const ref = db.collection("users").doc(uid).collection("wardrobe").doc(itemId);
    const sourceUrl = String(data.sourceUrl || "").trim();
    const seedImage = String(
      data.productLinkSeedImageUrl || data.imageUrl || data.productImageUrl || ""
    ).trim();
    const title = String(data.name || "").trim();
    const brand = String(data.brand || "").trim();
    const sku =
      String(data.productLinkSku || "").trim() ||
      extractProductSkuFromText(`${title} ${brand}`, sourceUrl);
    const colors = Array.isArray(data.colors) ? data.colors : [];
    const subCategoryKey = String(
      data.subCategoryKey || data.subCategory || ""
    ).trim();
    let hostname = "";
    try {
      hostname = new URL(sourceUrl).hostname || "";
    } catch (_) {}

    const isAdidasSource = isAdidasProductSourceUrl(sourceUrl);
    const seedValid = seedImage && isValidHttpUrl(seedImage);
    const seedLooksModel = seedUrlLooksLikeModelPhoto(seedImage, sourceUrl, title);
    const seedIsCleanPackshot = seedUrlLooksLikeCleanPackshot(seedImage, sourceUrl);

    if (isAdidasSource && seedValid) {
      console.log("[WARDROBE_IMAGE_PROCESS][adidas_source_seed_only]");
      logger.info("[WARDROBE_IMAGE_PROCESS][adidas_source_seed_only]", {
        seed: seedImage.slice(0, 200),
      });

      const pageOutcome = await runSourcePageOnlyImageSearch({
        uid,
        itemId,
        sourceUrl,
        seedImage,
        sku,
        brand,
        title,
        subCategoryKey,
      });

      if (pageOutcome.found && pageOutcome.productImageUrl) {
        const downloadUrl = String(pageOutcome.productImageUrl);
        const winnerCandidate = String(
          pageOutcome.sourceCandidateUrl || downloadUrl
        ).trim();
        const colorPatch = mergeWardrobeColorPatch(
          {},
          winnerCandidate,
          { subCategoryKey, title }
        );
        if (colorPatch) {
          console.log(
            "[WARDROBE_IMAGE_PROCESS][color_from_winner_url]",
            colorPatch.colors
          );
          logger.info("[WARDROBE_IMAGE_PROCESS][color_from_winner_url]", {
            colors: colorPatch.colors,
            url: winnerCandidate.slice(0, 240),
          });
        }
        await ref.set(
          {
            productImageUrl: downloadUrl,
            imageUrl: downloadUrl,
            cleanImageUrl: pageOutcome.cleanImageUrl || downloadUrl,
            cutoutImageUrl: pageOutcome.cutoutImageUrl || downloadUrl,
            productLinkSeedImageUrl: seedImage,
            imageProcessingStatus: "done",
            imageProcessingReason: "source_page_better_image",
            imageProcessingJobQueued: false,
            imageProcessingUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
            ...(colorPatch || {}),
          },
          { merge: true }
        );
        if (colorPatch) {
          console.log("[WARDROBE_IMAGE_PROCESS][updated_color_fields]");
          logger.info("[WARDROBE_IMAGE_PROCESS][updated_color_fields]", {
            colors: colorPatch.colors,
            name: colorPatch.name || null,
          });
        }
        return;
      }

      if (seedIsCleanPackshot) {
        await ref.set(
          {
            imageProcessingStatus: "done",
            imageProcessingReason: "already_product_asset",
            imageProcessingJobQueued: false,
            imageProcessingUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
        return;
      }

      const apiKey = getOpenAiKey() || null;
      const prepared = await runPrepareProductLinkImagePipeline({
        uid,
        itemId,
        url: sourceUrl,
        imageUrl: seedImage,
        hostname,
        pageTitle: title,
        apiKey,
      });
      if (prepared.cleanupSucceeded && prepared.productImageUrl) {
        const downloadUrl = String(prepared.productImageUrl);
        await ref.set(
          {
            productImageUrl: downloadUrl,
            imageUrl: downloadUrl,
            cleanImageUrl: prepared.cleanImageUrl || downloadUrl,
            cutoutImageUrl: prepared.cutoutImageUrl || downloadUrl,
            productLinkSeedImageUrl: seedImage,
            imageProcessingStatus: "done",
            imageProcessingReason: "source_seed_cleanup",
            imageProcessingJobQueued: false,
            imageProcessingUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
      } else {
        await ref.set(
          {
            imageProcessingStatus: "done",
            imageProcessingReason: "kept_source_seed",
            imageProcessingJobQueued: false,
            imageProcessingUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
      }
      return;
    }

    if (seedLooksModel) {
      console.log("[PRODUCT_IMAGE][person_detected]");
      console.log("[PRODUCT_IMAGE][search_required]");
      logger.info("[PRODUCT_IMAGE][person_detected]", { seed: seedImage.slice(0, 200) });
    } else if (seedIsCleanPackshot) {
      console.log("[PRODUCT_IMAGE][clean_packshot]");
      console.log("[PRODUCT_IMAGE][skip_search]");
      logger.info("[PRODUCT_IMAGE][clean_packshot]", { seed: seedImage.slice(0, 200) });
      await ref.set(
        {
          imageProcessingStatus: "done",
          imageProcessingReason: "already_product_asset",
          imageProcessingJobQueued: false,
          imageProcessingUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
      return;
    } else {
      console.log("[PRODUCT_IMAGE][search_required]");
    }

    console.log("[WARDROBE_IMAGE_PROCESS][queued]", { uid, itemId, sku });
    logger.info("[WARDROBE_IMAGE_PROCESS][queued]", {
      uid,
      itemId,
      sourceUrl: sourceUrl.slice(0, 140),
      sku,
    });

    await ref.set(
      {
        imageProcessingReason: "searching_better_image",
        imageProcessingUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    logger.info("[WARDROBE_IMAGE_PROCESS][status_processing]", { itemId });

    console.log("[WARDROBE_IMAGE_PROCESS][product_search_enter]");
    console.log("[WARDROBE_IMAGE_PROCESS][serper_background_start]");
    logger.info("[WARDROBE_IMAGE_PROCESS][serper_background_start]", { itemId });
    logProductSearchSerperStartup();

    const searchResult = await runProductImageWebSearch({
      uid,
      itemId,
      sourceUrl,
      seedImage,
      sku,
      brand,
      title,
      colors,
      subCategoryKey,
    });

    if (searchResult.found && searchResult.productImageUrl) {
      const sourceCandidateUrl =
        String(searchResult.sourceCandidateUrl || searchResult.productImageUrl).trim();
      const cleaned = await finalizeSerperSelectedWardrobeImage({
        uid,
        itemId,
        imageUrl: sourceCandidateUrl,
        title,
        brand,
      });
      const downloadUrl = String(cleaned.productImageUrl);
      const cleanUrl = String(cleaned.cleanImageUrl || downloadUrl);
      const cutoutUrl = String(cleaned.cutoutImageUrl || cleanUrl);
      const selectedReason = "better_image_found";
      const colorPatch = mergeWardrobeColorPatch(
        {},
        sourceCandidateUrl,
        { subCategoryKey, title }
      );
      if (colorPatch) {
        console.log(
          "[WARDROBE_IMAGE_PROCESS][color_from_winner_url]",
          colorPatch.colors
        );
        logger.info("[WARDROBE_IMAGE_PROCESS][color_from_winner_url]", {
          colors: colorPatch.colors,
          url: sourceCandidateUrl.slice(0, 240),
        });
      }
      console.log("[WARDROBE_IMAGE_PROCESS][download_url]", downloadUrl);
      console.log("[WARDROBE_IMAGE_PROCESS][selected_url]", downloadUrl);
      console.log("[WARDROBE_IMAGE_PROCESS][selected_reason]", selectedReason);
      console.log(
        `[WARDROBE_IMAGE_PROCESS][updated_fields] productImageUrl=${downloadUrl}`
      );
      logger.info("[WARDROBE_IMAGE_PROCESS][selected_url]", { url: downloadUrl.slice(0, 240) });
      logger.info("[WARDROBE_IMAGE_PROCESS][selected_reason]", { reason: selectedReason });
      await ref.set(
        {
          productImageUrl: downloadUrl,
          imageUrl: downloadUrl,
          cleanImageUrl: cleanUrl,
          cutoutImageUrl: cutoutUrl,
          productLinkSeedImageUrl: seedImage || sourceCandidateUrl,
          imageProcessingStatus: "done",
          imageProcessingReason: selectedReason,
          imageProcessingJobQueued: false,
          imageProcessingUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
          ...(searchResult.sku ? { productLinkSku: searchResult.sku } : {}),
          ...(colorPatch || {}),
        },
        { merge: true }
      );
      if (colorPatch) {
        console.log("[WARDROBE_IMAGE_PROCESS][updated_color_fields]");
        logger.info("[WARDROBE_IMAGE_PROCESS][updated_color_fields]", {
          colors: colorPatch.colors,
          name: colorPatch.name || null,
        });
      }
      console.log(
        `[WARDROBE_IMAGE_PROCESS][status_done] uid=${uid} itemId=${itemId} queued=false`
      );
      logger.info("[PRODUCT_SEARCH][status]", { phase: "done" });
      return;
    }

    if (!searchResult.found && searchResult.hadCandidateInspection === true) {
      logger.warn("[WARDROBE_IMAGE_PROCESS][search_no_acceptable_packshot]", {
        itemId,
        reason: "kept_seed_no_better_packshot",
      });
      await ref.set(
        {
          imageProcessingStatus: "done",
          imageProcessingReason: "kept_seed_no_better_packshot",
          imageProcessingJobQueued: false,
          imageProcessingUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
      return;
    }

    logger.info("[WARDROBE_IMAGE_PROCESS][cleanup_start]", { itemId });
    const apiKey = getOpenAiKey() || null;
    const prepared = await runPrepareProductLinkImagePipeline({
      uid,
      itemId,
      url: sourceUrl || `https://${hostname || "example.com"}`,
      imageUrl: seedImage,
      hostname,
      pageTitle: title,
      apiKey,
    });

    logger.info("[WARDROBE_IMAGE_PROCESS][cleanup_done]", {
      succeeded: prepared.cleanupSucceeded === true,
      skipped: prepared.cleanupSkipped === true,
    });

    if (prepared.cleanupSucceeded) {
      const doneReason = prepared.cleanupSkipped ? "no_better_image" : "cleanup_complete";
      const patch = {
        imageProcessingStatus: "done",
        imageProcessingReason: doneReason,
        imageProcessingJobQueued: false,
        imageProcessingUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };
      if (prepared.cleanImageUrl && prepared.productImageUrl) {
        const downloadUrl = String(prepared.productImageUrl);
        patch.productImageUrl = downloadUrl;
        patch.imageUrl = downloadUrl;
        patch.cleanImageUrl = prepared.cleanImageUrl;
        patch.cutoutImageUrl = prepared.cleanImageUrl;
        console.log("[WARDROBE_IMAGE_PROCESS][download_url]", downloadUrl);
        console.log("[WARDROBE_IMAGE_PROCESS][selected_url]", downloadUrl);
        console.log("[WARDROBE_IMAGE_PROCESS][selected_reason]", doneReason);
        console.log(
          `[WARDROBE_IMAGE_PROCESS][updated_fields] productImageUrl=${downloadUrl}`
        );
      }
      await ref.set(patch, { merge: true });
      console.log(
        `[WARDROBE_IMAGE_PROCESS][status_done] uid=${uid} itemId=${itemId} queued=false reason=${doneReason}`
      );
      return;
    }

    const failReason = prepared.failureReason || "cleanup_failed";
    logger.info("[WARDROBE_IMAGE_PROCESS][status_failed]", { reason: failReason });
    await ref.set(
      {
        imageProcessingStatus: "failed",
        imageProcessingReason: failReason,
        imageProcessingJobQueued: false,
        imageProcessingUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
  }

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

  async function callOpenAiChatMessages(messages) {
    const apiKey = getOpenAiKey();
    if (!apiKey) {
      logger.error("Chýba OPENAI_API_KEY v prostredí!");
      throw new Error("Server nemá nastavený OPENAI_API_KEY.");
    }

    const body = {
      model: "gpt-4o-mini",
      messages,
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

  exports.stylistChat = functions
    .region("us-east1")
    .https.onCall(async (data, context) => {
      const uid = context.auth?.uid || null;
      const message = String(data?.message || "").trim();
      const weatherContext =
        data?.weatherContext && typeof data.weatherContext === "object" ?
          data.weatherContext :
          null;
      const rawHistory = Array.isArray(data?.history) ? data.history : [];
      const historyFromClient = rawHistory
        .slice(-8)
        .map((item) => {
          const role = item && (item.role === "user" || item.role === "assistant") ?
            item.role :
            null;
          const content = String(item?.content || "").trim();
          if (!role || !content) return null;
          return {role, content};
        })
        .filter(Boolean);
      let wardrobeSummaryLines = [];
      let wardrobeItemsForSuggestions = [];

      if (uid) {
        try {
          const snap = await db.collection("users").doc(uid).collection("wardrobe").limit(60).get();
          const wardrobeDocs = snap.docs
            .map((doc) => ({id: doc.id, ...(doc.data() || {})}));
          wardrobeItemsForSuggestions = wardrobeDocs.map((item) => {
            const imageUrl = String(
              item.productImageUrl ||
              item.cutoutImageUrl ||
              item.cleanImageUrl ||
              item.imageUrl ||
              ""
            ).trim();
            return {
              id: String(item.id || "").trim(),
              name: String(item.name || item.typePretty || item.type || "Neznámy kúsok").trim(),
              category: String(item.category || item.categoryKey || "").trim(),
              colors: Array.isArray(item.colors) ?
                item.colors.map((v) => String(v).trim()).filter(Boolean) :
                [],
              productImageUrl: String(item.productImageUrl || "").trim(),
              cutoutImageUrl: String(item.cutoutImageUrl || "").trim(),
              cleanImageUrl: String(item.cleanImageUrl || "").trim(),
              imageUrl,
            };
          });

          wardrobeSummaryLines = wardrobeDocs
            .map((item) => {
              const name = String(item.name || item.typePretty || item.type || "").trim();
              const category = String(item.category || item.categoryKey || "").trim();
              const subCategory = String(item.subCategory || item.subCategoryKey || "").trim();
              const mainGroup = String(item.mainGroup || item.mainGroupKey || "").trim();
              const brand = String(item.brand || "").trim();
              const imageUrl = String(
                item.productImageUrl ||
                item.cutoutImageUrl ||
                item.cleanImageUrl ||
                item.imageUrl ||
                ""
              ).trim();
              const colors = Array.isArray(item.colors) ?
                item.colors.map((v) => String(v).trim()).filter(Boolean) :
                [];
              const styles = Array.isArray(item.styles) ?
                item.styles.map((v) => String(v).trim()).filter(Boolean) :
                [];
              const seasons = Array.isArray(item.seasons) ?
                item.seasons.map((v) => String(v).trim()).filter(Boolean) :
                [];

              const details = [];
              if (category) details.push(`kategória: ${category}`);
              if (subCategory) details.push(`subkategória: ${subCategory}`);
              if (mainGroup) details.push(`skupina: ${mainGroup}`);
              if (colors.length) details.push(`farby: ${colors.join(", ")}`);
              if (styles.length) details.push(`štýl: ${styles.join(", ")}`);
              if (seasons.length) details.push(`sezóny: ${seasons.join(", ")}`);
              if (brand) details.push(`značka: ${brand}`);
              if (item.id) details.push(`id: ${item.id}`);
              if (imageUrl) details.push(`imageUrl: ${imageUrl}`);

              const label = name || "Neznámy kúsok";
              return details.length ? `- ${label} | ${details.join(" | ")}` : `- ${label}`;
            });
        } catch (err) {
          logger.warn("stylistChat: wardrobe load failed", {uid, error: err?.message || String(err)});
          wardrobeSummaryLines = [];
        }
      }

      if (!message) {
        return { reply: "Tomu úplne nerozumiem 😄 Skús mi napísať, čo riešiš s outfitom." };
      }

      const systemPrompt =
        `Si osobný stylist, ktorý komunikuje prirodzene ako kamarát.\n` +
        `You are not just a stylist. You are evaluating outfits.\n` +
        `Always answer the user's latest message directly. Do not ignore the question.\n` +
        `Odpovedaj stručne, ľudsky a prakticky.\n` +
        `For every outfit suggestion from user:\n` +
        `- you MUST decide: GOOD or BAD\n` +
        `- you MUST say your verdict clearly\n` +
        `- you MUST NOT stay neutral\n` +
        `If BAD:\n` +
        `- say it clearly (honest + playful)\n` +
        `- explain briefly why\n` +
        `- suggest fix\n` +
        `If GOOD:\n` +
        `- say why it works\n` +
        `Do NOT always validate the user's idea.\n` +
        `If the outfit combination is objectively bad, say it clearly.\n` +
        `Do NOT try to "make it work" at all costs.\n` +
        `Buď úprimný najprv, až potom nápomocný.\n` +
        `Nikdy neklam len preto, aby si bol milý.\n` +
        `Pri zlých outfitoch je humor povinný.\n` +
        `Nikdy neurážaj používateľa osobne.\n` +
        `Ak používateľ navrhne zlú kombináciu (napr. blazer + shorts + crocs, shirt + sweatpants v zlom kontexte, suit + sneakers nesprávne), MUSÍŠ:\n` +
        `1) zareagovať prekvapením alebo humorom,\n` +
        `2) jasne povedať, že to nefunguje dobre,\n` +
        `3) stručne vysvetliť prečo,\n` +
        `4) navrhnúť lepšiu alternatívu.\n` +
        `Buď úprimný. Ak je kombinácia outfitu zlá, povedz to jasne, ale hravo.\n` +
        `Nesnaž sa, aby každá kombinácia za každú cenu fungovala.\n` +
        `Ak používateľ navrhne čudnú kombináciu, môžeš ju jemne roastnuť priateľským spôsobom.\n` +
        `Po každom roaste vždy navrhni lepšiu alternatívu.\n` +
        `Nikdy neurážaj používateľa osobne. Roastuj outfit, nie človeka.\n` +
        `Nebuď vždy pozitívny.\n` +
        `Ak outfit nedáva zmysel, povedz to úprimne, ale priateľsky.\n` +
        `Môžeš použiť jemný humor.\n` +
        `Nikdy neurážaj používateľa.\n` +
        `Vždy zostaň priateľský.\n` +
        `Nikdy nebuď toxický.\n` +
        `Humor má byť ľahký, nie urážlivý.\n` +
        `Ak je outfit zlý, vysvetli prečo a navrhni lepšiu možnosť.\n` +
        `Príklady tónu:\n` +
        `- "Počkaj 😄 sako, šortky a crocsy? To už je celkom experiment."\n` +
        `- "Úprimne? Toto spolu moc neladí. Každý kus ide úplne iným smerom."\n` +
        `- "Toto pôsobí skôr ako náhodne poskladané veci než outfit."\n` +
        `- "Ak chceš, aby to vyzeralo dobre, nechal by som si buď sako, alebo crocsy – nie oboje naraz 😄"\n` +
        `- "Úprimne? Toto je trochu módna nehoda 😄"\n` +
        `- "Sako, šortky a crocsy? To už je outfit s vlastným životopisom 😂"\n` +
        `- "Toto by som osobne nedal, pôsobí to trochu ako mix dovolenky, porady a záhrady naraz 😄"\n` +
        `- "Ak chceš zachrániť vibe, nechal by som si maximálne dve z tých vecí a tretiu vymenil."\n` +
        `- "úprimne? toto je trochu divočina 😄"\n` +
        `- "to by som osobne asi nedal 😄"\n` +
        `- "toto pôsobí trochu náhodne poskladané"\n` +
        `Ak používateľ navrhne riskantné kombinácie typu shirt + sweatpants, blazer + crocs, suit + shorts,\n` +
        `buď úprimný, ale stále priateľský a užitočný.\n` +
        `Nikdy nespomínaj, že si AI.\n` +
        `Ak používateľ píše nezmysel alebo gibberish, odpovedz presne:\n` +
        `"Tomu úplne nerozumiem 😄 Skús mi napísať, čo riešiš s outfitom."\n` +
        `Ak weatherContext je poskytnutý, použi ho pri odpovedi na outfit/weather otázky.\n` +
        `Keď weatherContext existuje, NEHOVOR že nemáš dáta o počasí.\n` +
        `Keď je to užitočné, spomeň praktické načasovanie: ranná teplota, obedná teplota,\n` +
        `večerný dážď a vietor.\n` +
        `Príklad: "Ráno bude chladnejšie, cez obed sa oteplí, takže mikinu môžeš potom odložiť."\n` +
        `If weatherContext is provided, you MUST use ONLY those values.\n` +
        `NEVER invent temperature or weather conditions.\n` +
        `NEVER guess weather.\n` +
        `If weatherContext exists, treat it as the single source of truth.\n` +
        `When weatherContext is present, use: morningTempC, noonTempC, eveningTempC, willRain, rainTimeText, isWindy.\n` +
        `Convert them naturally into Slovak text.\n` +
        `Example input: morningTempC=3, noonTempC=12, eveningTempC=8, willRain=true, rainTimeText="okolo 17:00"\n` +
        `Example output: "Ráno bude okolo 3 °C, cez obed približne 12 °C. Večer sa ochladí na asi 8 °C a okolo 17:00 môže pršať."\n` +
        `Do NOT say "približne" or "asi" unless converting the given numbers.\n` +
        `Do NOT create new numbers.\n` +
        `Do NOT override provided data.\n` +
        `If weatherContext is missing, fallback to generic weather text.\n` +
        `Ak weatherContext nie je poskytnutý a používateľ sa pýta na počasie,\n` +
        `jasne povedz, že nemáš live počasie, ale aj tak daj všeobecnú praktickú outfit radu.\n` +
        `\nCRITICAL RULES:\n` +
        `- NEVER say that a bad outfit is "great", "skvelé", or "super".\n` +
        `- NEVER pretend a bad combination works just to be nice.\n` +
        `- If the outfit is bad, you MUST say it clearly.\n` +
        `\nWhen user suggests a bad outfit:\n` +
        `You MUST follow this structure:\n` +
        `1. Short reaction (surprise / humor)\n` +
        `2. Honest verdict (it does not work)\n` +
        `3. Short reason\n` +
        `4. Better suggestion\n` +
        `\nExamples:\n` +
        `- "Počkaj 😄 sako, šortky a crocsy? To už je celkom experiment."\n` +
        `- "Úprimne? Toto spolu vôbec neladí."\n` +
        `- "Každý kus ide úplne iným smerom, preto to nefunguje."\n` +
        `- "Ak chceš, aby to vyzeralo dobre, nechal by som sako a dal k nemu nohavice alebo tenisky."\n` +
        `\nNEGATIVE EXAMPLES (what NOT to do):\n` +
        `- "to znie skvelo"\n` +
        `- "určite sa budeš cítiť dobre"\n` +
        `- "je to super kombinácia"\n` +
        `\nTone:\n` +
        `- honest first\n` +
        `- then helpful\n` +
        `- humor allowed\n` +
        `- never insult the user personally\n` +
        `\nSTRICT EVALUATION RULES:\n` +
        `- NEVER say "to znie skvelo" automatically\n` +
        `- NEVER approve every idea\n` +
        `- If unsure -> lean towards critical evaluation\n` +
        `- honesty over politeness\n` +
        `- never fake positivity\n` +
        `- roast lightly if needed\n` +
        `\nWhen user suggests outfit:\n` +
        `1. reaction (short, human)\n` +
        `2. verdict (good / bad)\n` +
        `3. reason\n` +
        `4. suggestion\n` +
        `When useful, mention concrete wardrobe items by name. Do not invent items. ` +
        `If the wardrobe does not contain a suitable item, say that clearly.\n` +
        `When suggesting an outfit, always choose real items from the user's wardrobe.\n` +
        `Return 2-4 specific items.\n` +
        `Do NOT invent items.\n` +
        `Always include their IDs.\n` +
        `Return strict JSON only in this structure:\n` +
        `{\n` +
        `  "reply": "...text...",\n` +
        `  "suggestedItemIds": ["id1", "id2"]\n` +
        `}\n` +
        `\nExamples to follow:\n` +
        `BAD:\n` +
        `"Počkaj 😄 sako, šortky a crocsy? To už je módny experiment. Úprimne? Neladí to – každý kus ide iným smerom. Skús buď sako + nohavice, alebo šortky + tričko."\n` +
        `GOOD:\n` +
        `"To je celkom clean kombinácia 👌 Jednoduché, ladí to a nič sa tam nebije."`;

      const wardrobeContext =
        wardrobeSummaryLines.length > 0 ?
          wardrobeSummaryLines.slice(0, 60).join("\n") :
          "- (šatník nie je dostupný alebo je prázdny)";

      const messages = [
        {role: "system", content: systemPrompt},
        ...historyFromClient,
        {
          role: "user",
          content:
            `Najnovšia správa používateľa:\n${message}\n\n` +
            `Current weather context:\n${JSON.stringify(weatherContext)}\n\n` +
            `User wardrobe:\n${wardrobeContext}`,
        },
      ];

      try {
        const raw = await callOpenAiChatMessages(messages);
        let parsed = null;
        try {
          parsed = JSON.parse(String(raw || "").trim());
        } catch (_) {
          parsed = null;
        }

        const reply = String(parsed?.reply || raw || "").trim();
        const suggestedIdsRaw = Array.isArray(parsed?.suggestedItemIds) ?
          parsed.suggestedItemIds :
          [];
        const suggestedIds = suggestedIdsRaw
          .map((id) => String(id || "").trim())
          .filter(Boolean)
          .slice(0, 4);
        const idSet = new Set(suggestedIds);
        const suggestedItems = wardrobeItemsForSuggestions
          .filter((item) => idSet.has(String(item.id || "")))
          .slice(0, 4);

        return {reply, suggestedItems};
      } catch (error) {
        logger.error("stylistChat error:", error);
        throw new functions.https.HttpsError(
          "internal",
          "Stylist chat momentálne nie je dostupný."
        );
      }
    });

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
        const systemPrompt = `
Si osobný stylist, ktorý komunikuje ako kamarát.

Tvoj štýl:
- si uvoľnený, prirodzený a priateľský
- občas použiješ emoji 😄👌🔥
- nie si robot, nikdy nespomínaj AI
- odpovedáš ako človek, nie ako asistent

Tvoje správanie:
- reaguješ prirodzene na všetko, nielen na módu
- vieš byť jemne vtipný
- keď niečo nedáva zmysel, povieš to normálne (napr. „čo to píšeš 😄“)

Móda:
- dávaš praktické rady, nie teóriu
- hovoríš jednoducho, nie prehnane odborne
- keď môžeš, využívaj user's wardrobe

Príklady tónu:
- „toto by som osobne nedal 😄“
- „to je celkom safe kombinácia, nič nepokazíš“
- „tu by som trochu ubral, je toho veľa naraz“

Dôležité:
- nikdy nepíš dlhé nudné odstavce
- buď konkrétny
- radšej kratšie, prirodzené odpovede

Premium:
- Premium spomeň len keď to dáva zmysel
- nikdy netlač na predaj
- používaj jemné formulácie ako:
  „ak chceš, viem to rozobrať viac“
  „to už riešime viac do detailu v Premium“

Nikdy:
- nepoužívaj frázy typu „ako AI model“
- nebuď príliš formálny
- nepíš ako zákaznícka podpora

Tvoj cieľ:
aby user mal pocit, že si píše s reálnym stylistom.
`;

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

// ---------------------------------------------------------------------------
// analyzeClothingProductUrl – GEN1 Callable (product page metadata + OpenAI)
// ---------------------------------------------------------------------------
const WARDROBE_MAIN_GROUP_KEYS = ["oblecenie", "obuv", "doplnky"];

const WARDROBE_CATEGORY_KEYS = [
  "tricka_topy",
  "kosele",
  "mikiny",
  "svetre",
  "bundy_kabaty",
  "nohavice_rifle",
  "sortky_sukne",
  "saty_overaly",
  "sport_oblecenie",
  "tenisky",
  "elegantna_obuv",
  "cizmy",
  "letna_obuv",
  "sport_obuv_doplnky",
  "dopl_hlava",
  "dopl_saly_rukavice",
  "dopl_tasky",
  "dopl_ostatne",
];

const WARDROBE_SUB_CATEGORY_KEYS = [
  "tricko",
  "tricko_dlhy_rukav",
  "tielko",
  "undershirt",
  "top_basic",
  "crop_top",
  "polo_tricko",
  "body",
  "korzet_top",
  "bluzka",
  "kosela_klasicka",
  "kosela_oversize",
  "kosela_flanelova",
  "mikina_klasicka",
  "mikina_na_zips",
  "mikina_s_kapucnou",
  "mikina_oversize",
  "sveter_klasicky",
  "sveter_rolak",
  "sveter_kardigan",
  "sveter_pleteny",
  "bunda_riflova",
  "bunda_kozena",
  "bunda_bomber",
  "bunda_prechodna",
  "bunda_zimna",
  "kabat",
  "trenchcoat",
  "sako",
  "vesta",
  "prsiplast",
  "flisova_bunda",
  "rifle",
  "rifle_skinny",
  "rifle_wide_leg",
  "rifle_mom",
  "nohavice_klasicke",
  "nohavice_chino",
  "nohavice_teplakove",
  "nohavice_joggery",
  "nohavice_elegantne",
  "nohavice_cargo",
  "leginy",
  "sortky",
  "sortky_sportove",
  "sukna",
  "sukna_mini",
  "sukna_midi",
  "sukna_maxi",
  "saty",
  "saty_kratke",
  "saty_midi",
  "saty_maxi",
  "saty_koselove",
  "saty_bodycon",
  "overal",
  "tenisky_fashion",
  "tenisky_sportove",
  "tenisky_bezecke",
  "lodicky",
  "sandale_opatok",
  "balerinky",
  "mokasiny",
  "poltopanky",
  "obuv_platforma",
  "cizmy_clenkove",
  "cizmy_vysoke",
  "cizmy_nad_kolena",
  "gumaky",
  "snehule",
  "sandale",
  "slapky",
  "zabky",
  "espadrilky",
  "ciapka",
  "siltovka",
  "bucket_hat",
  "sal",
  "satka",
  "rukavice",
  "kabelka",
  "taska_crossbody",
  "ruksak",
  "kabelka_listova",
  "ladvinka",
  "slnecne_okuliare",
  "opasok",
  "penazenka",
  "hodinky",
  "sperky",
  "sport_tricko",
  "sport_mikina",
  "sport_leginy",
  "sport_sortky",
  "sport_suprava",
  "softshell_bunda",
  "sport_podprsenka",
  "obuv_treningova",
  "obuv_turisticka",
  "sport_taska",
  "potitka",
];

function stripCodeFencesGlobal(text) {
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

function extractFirstJsonObjectGlobal(text) {
  const raw = stripCodeFencesGlobal(text);
  if (!raw) return null;
  try {
    const parsed = JSON.parse(raw);
    return parsed && typeof parsed === "object" ? parsed : null;
  } catch (_) {}
  const start = raw.indexOf("{");
  if (start === -1) return null;
  let depth = 0;
  for (let i = start; i < raw.length; i++) {
    const ch = raw[i];
    if (ch === "{") depth++;
    if (ch === "}") depth--;
    if (depth === 0) {
      try {
        return JSON.parse(raw.slice(start, i + 1));
      } catch (_) {
        return null;
      }
    }
  }
  return null;
}

function isValidHttpUrl(raw) {
  try {
    const u = new URL(raw);
    return (u.protocol === "http:" || u.protocol === "https:") && !!u.hostname;
  } catch (_) {
    return false;
  }
}

function decodeHtmlEntities(s) {
  return String(s || "")
    .replace(/&amp;/g, "&")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">");
}

const DOMAIN_BRAND_MAP = [
  { hosts: ["zara.com"], brand: "Zara" },
  { hosts: ["aboutyou.", "about-you."], brand: "About You" },
  { hosts: ["hm.com", "h&m", "h-m."], brand: "H&M" },
  { hosts: ["zalando."], brand: "Zalando" },
  { hosts: ["reserved.com", "reserved."], brand: "Reserved" },
  { hosts: ["mango.com"], brand: "Mango" },
  { hosts: ["bershka."], brand: "Bershka" },
  { hosts: ["pullandbear.", "pull-bear."], brand: "Pull&Bear" },
  { hosts: ["stradivarius."], brand: "Stradivarius" },
  { hosts: ["nike.com"], brand: "Nike" },
  { hosts: ["adidas."], brand: "Adidas" },
];

/** Slug / text rules — keys must match Flutter wardrobe schema. */
const SLUG_CLOTHING_RULES = [
  { keys: ["mikina-ul", "hoodie", "hooded", "kapuc", "kapucnou"], main: "oblecenie", cat: "mikiny", sub: "mikina_s_kapucnou", canon: "hoodie", name: "Mikina s kapucňou" },
  { keys: ["mikina", "sweatshirt", "sweat"], main: "oblecenie", cat: "mikiny", sub: "mikina_klasicka", canon: "sweatshirt", name: "Mikina" },
  { keys: ["zip-hoodie", "zip-hooded", "mikina-na-zips"], main: "oblecenie", cat: "mikiny", sub: "mikina_na_zips", canon: "hoodie", name: "Mikina na zips" },
  { keys: ["t-shirt", "tshirt", "tee", "tricko", "shirt"], main: "oblecenie", cat: "tricka_topy", sub: "tricko", canon: "t_shirt", name: "Tričko" },
  { keys: ["longsleeve", "long-sleeve", "dlhy-rukav"], main: "oblecenie", cat: "tricka_topy", sub: "tricko_dlhy_rukav", canon: "long_sleeve", name: "Tričko s dlhým rukávom" },
  { keys: ["tank", "tielko"], main: "oblecenie", cat: "tricka_topy", sub: "tielko", canon: "tank_top", name: "Tielko" },
  { keys: ["polo"], main: "oblecenie", cat: "tricka_topy", sub: "polo_tricko", canon: "polo", name: "Polo tričko" },
  { keys: ["bluzka", "blouse"], main: "oblecenie", cat: "tricka_topy", sub: "bluzka", canon: "blouse", name: "Blúzka" },
  { keys: ["kosela", "košela", "button-down"], main: "oblecenie", cat: "kosele", sub: "kosela_klasicka", canon: "shirt", name: "Košeľa" },
  { keys: ["sveter", "sweater", "pullover", "rolak", "rolák"], main: "oblecenie", cat: "svetre", sub: "sveter_klasicky", canon: "sweater", name: "Sveter" },
  { keys: ["kardigan", "cardigan"], main: "oblecenie", cat: "svetre", sub: "sveter_kardigan", canon: "cardigan", name: "Kardigan" },
  { keys: ["bunda", "jacket", "bomber"], main: "oblecenie", cat: "bundy_kabaty", sub: "bunda_prechodna", canon: "jacket", name: "Bunda" },
  { keys: ["kabat", "kabát", "coat", "trench"], main: "oblecenie", cat: "bundy_kabaty", sub: "kabat", canon: "coat", name: "Kabát" },
  { keys: ["dzinsy", "dzinzy", "džínsy", "rifle", "jeans", "denim"], main: "oblecenie", cat: "nohavice_rifle", sub: "rifle", canon: "jeans", name: "Džínsy" },
  { keys: ["zabky", "flipflops", "flip-flops", "flipflop"], main: "obuv", cat: "letna_obuv", sub: "zabky", canon: "flip_flops", name: "Žabky" },
  { keys: ["nohavice", "pants", "trousers", "chino"], main: "oblecenie", cat: "nohavice_rifle", sub: "nohavice_klasicke", canon: "pants", name: "Nohavice" },
  { keys: ["leginy", "leggings"], main: "oblecenie", cat: "nohavice_rifle", sub: "leginy", canon: "leggings", name: "Legíny" },
  { keys: ["swim-shorts", "swimshorts", "swim_shorts", "plavecke-sortky", "plavecky-sortky", "plavecké-sortky"], main: "oblecenie", cat: "plavky", sub: "plavecke_sortky", canon: "swim_shorts", name: "Plavecké šortky" },
  { keys: ["sortky", "shorts", "kratasy", "kraťasy"], main: "oblecenie", cat: "sortky_sukne", sub: "sortky", canon: "shorts", name: "Šortky" },
  { keys: ["sukna", "sukňa", "skirt"], main: "oblecenie", cat: "sortky_sukne", sub: "sukna", canon: "skirt", name: "Sukňa" },
  { keys: ["saty", "šaty", "dress"], main: "oblecenie", cat: "saty_overaly", sub: "saty", canon: "dress", name: "Šaty" },
  { keys: ["sneakers", "sneaker", "tenisky", "trainers"], main: "obuv", cat: "tenisky", sub: "tenisky_fashion", canon: "sneakers", name: "Tenisky" },
  { keys: ["boots", "cizmy", "čižmy"], main: "obuv", cat: "cizmy", sub: "cizmy_clenkove", canon: "boots", name: "Čižmy" },
  { keys: ["sandale", "sandals", "sandal"], main: "obuv", cat: "letna_obuv", sub: "sandale", canon: "sandals", name: "Sandále" },
  { keys: ["shoes", "obuv", "topanky", "topánky"], main: "obuv", cat: "tenisky", sub: "tenisky_fashion", canon: "shoes", name: "Obuv" },
  { keys: ["cap", "ciapka", "čiapka", "hat"], main: "doplnky", cat: "dopl_hlava", sub: "ciapka", canon: "cap", name: "Čiapka" },
  { keys: ["bag", "kabelka", "taska", "taška"], main: "doplnky", cat: "dopl_tasky", sub: "kabelka", canon: "bag", name: "Kabelka" },
];

const SLUG_COLOR_RULES = [
  { keys: ["cierna", "cierny", "black", "blk"], color: "čierna" },
  { keys: ["biela", "biely", "white", "wht"], color: "biela" },
  { keys: ["siva", "sivy", "grey", "gray"], color: "sivá" },
  { keys: ["modra", "modry", "blue", "navy"], color: "modrá" },
  { keys: ["tmavomodra", "navy"], color: "tmavomodrá" },
  { keys: ["zelena", "zeleny", "green", "olive"], color: "zelená" },
  { keys: ["hneda", "hnedy", "brown", "beige", "bezova", "béžová"], color: "hnedá" },
  { keys: ["cervena", "cerveny", "red"], color: "červená" },
  { keys: ["ruzova", "ruzovy", "pink"], color: "ružová" },
];

function extractMetaTag(html, key) {
  const patterns = [
    new RegExp(
      `<meta[^>]+(?:property|name)=["']${key}["'][^>]+content=["']([^"']+)["']`,
      "i"
    ),
    new RegExp(
      `<meta[^>]+content=["']([^"']+)["'][^>]+(?:property|name)=["']${key}["']`,
      "i"
    ),
  ];
  for (const re of patterns) {
    const m = html.match(re);
    if (m && m[1]) return decodeHtmlEntities(m[1]).trim();
  }
  return "";
}

function extractTitleTag(html) {
  const m = html.match(/<title[^>]*>([^<]+)<\/title>/i);
  return m ? decodeHtmlEntities(m[1]).trim() : "";
}

function extractJsonLdBlocks(html) {
  const out = [];
  const re = /<script[^>]+type=["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi;
  let m;
  while ((m = re.exec(html))) {
    try {
      const parsed = JSON.parse(m[1].trim());
      if (Array.isArray(parsed)) out.push(...parsed);
      else out.push(parsed);
    } catch (_) {}
  }
  return out;
}

function flattenJsonLd(nodes) {
  const flat = [];
  for (const n of nodes) {
    if (!n || typeof n !== "object") continue;
    flat.push(n);
    if (Array.isArray(n["@graph"])) {
      for (const g of n["@graph"]) flat.push(g);
    }
  }
  return flat;
}

function pickProductJsonLd(flat) {
  for (const it of flat) {
    const t = String(it["@type"] || "").toLowerCase();
    if (t.includes("product")) return it;
  }
  return flat[0] || null;
}

function extractStrategy1Metadata(html) {
  const meta = {
    ogTitle: extractMetaTag(html, "og:title"),
    ogDescription: extractMetaTag(html, "og:description"),
    ogImage: extractMetaTag(html, "og:image"),
    twitterTitle: extractMetaTag(html, "twitter:title"),
    twitterDescription: extractMetaTag(html, "twitter:description"),
    twitterImage: extractMetaTag(html, "twitter:image") || extractMetaTag(html, "twitter:image:src"),
    pageTitle: extractTitleTag(html),
  };
  return {
    title:
      meta.ogTitle ||
      meta.twitterTitle ||
      meta.pageTitle ||
      "",
    description:
      meta.ogDescription ||
      meta.twitterDescription ||
      extractMetaTag(html, "description") ||
      "",
    imageUrl: meta.ogImage || meta.twitterImage || "",
    raw: meta,
  };
}

const IMAGE_POSITIVE_HINTS = [
  "product",
  "packshot",
  "pack-shot",
  "main",
  "front",
  "still",
  "flat",
  "studio",
  "hero",
  "primary",
  "image",
];
const IMAGE_NEGATIVE_HINTS = [
  "model",
  "outfit",
  "lifestyle",
  "worn",
  "lookbook",
  "editorial",
  "campaign",
  "onbody",
  "on-body",
  "styling",
];

function scoreProductImageCandidate(url, context = {}) {
  const u = String(url || "").toLowerCase();
  if (!u || !isValidHttpUrl(url)) return -999;

  let score = 0;
  for (const hint of IMAGE_POSITIVE_HINTS) {
    if (u.includes(hint)) score += 10;
  }
  for (const hint of IMAGE_NEGATIVE_HINTS) {
    if (u.includes(hint)) score -= 28;
  }
  if (u.includes("white") || u.includes("biel") || u.includes("light")) score += 4;

  const source = String(context.source || "");
  if (source === "og") score += 18;
  if (source === "twitter") score += 14;
  if (source === "jsonld") score += 12;
  if (source === "gallery") score += 6;

  const idx = Number(context.index ?? 0);
  const isAboutYou = context.isAboutYou === true;
  const isAdidas = context.isAdidas === true || u.includes("adidas");

  // AboutYou: first gallery image is usually the clean packshot — explicit rule.
  if (isAboutYou && source === "gallery" && idx === 0) {
    score += 45;
  } else if (isAboutYou && source === "og" && idx === 0) {
    score += 35;
  }

  if (isAdidas && (source === "og" || source === "jsonld" || source === "twitter")) {
    score += 38;
  }
  if (isAdidas && source === "gallery" && idx === 0) {
    score += 42;
  }

  if (source === "gallery" && idx === 0 && !IMAGE_NEGATIVE_HINTS.some((h) => u.includes(h))) {
    score += 12;
  }

  if (IMAGE_NEGATIVE_HINTS.some((h) => u.includes(h))) {
    score -= 15;
  }

  return score;
}

const CLEANUP_PACKSHOT_MIN_SCORE = 16;
const CLEANUP_PACKSHOT_TRUST_SCORE = 32;
const CLEANUP_PERSON_URL_HINTS = [
  "model",
  "lifestyle",
  "worn",
  "lookbook",
  "onbody",
  "on-body",
  "editorial",
  "campaign",
  "athlete",
  "styling",
  "portrait",
  "hero",
];

function scoreCleanupImageCandidate(url, context = {}) {
  let score = scoreProductImageCandidate(url, context);
  const u = String(url || "").toLowerCase();
  for (const h of CLEANUP_PERSON_URL_HINTS) {
    if (u.includes(h)) score -= 32;
  }
  if (u.includes("face") || u.includes("head")) score -= 28;
  if (u.includes("packshot") || u.includes("pack-shot") || u.includes("flat")) {
    score += 28;
  }
  if (u.includes("product") && !u.includes("model")) score += 12;
  if (u.includes("static") && u.includes("nike")) score += 8;
  return score;
}

function urlHasStrongPersonHints(url) {
  const u = String(url || "").toLowerCase();
  return CLEANUP_PERSON_URL_HINTS.some((h) => u.includes(h));
}

function inferGarmentRegionHint(text) {
  const t = String(text || "").toLowerCase();
  if (
    /jacket|bunda|coat|kabát|blazer|vest|vesta|hoodie|mikina|top|tričko|shirt|košeľ|sweatshirt|pullover|cardigan/.test(
      t
    )
  ) {
    return "upper_garment";
  }
  if (/pants|nohavice|jeans|trouser|šortky|shorts|skirt|sukňa|leggings/.test(t)) {
    return "lower_garment";
  }
  return "garment";
}

function clampCropBox(box) {
  const top = Math.max(0, Math.min(0.85, Number(box?.top) || 0));
  const left = Math.max(0, Math.min(0.85, Number(box?.left) || 0));
  let width = Math.max(0.2, Math.min(1 - left, Number(box?.width) || 0.5));
  let height = Math.max(0.2, Math.min(1 - top, Number(box?.height) || 0.5));
  return { top, left, width, height };
}

function heuristicGarmentCropBox(garmentHint) {
  if (garmentHint === "lower_garment") {
    return { top: 0.4, left: 0.08, width: 0.84, height: 0.42 };
  }
  if (garmentHint === "upper_garment") {
    return { top: 0.14, left: 0.05, width: 0.9, height: 0.52 };
  }
  return { top: 0.18, left: 0.06, width: 0.88, height: 0.48 };
}

async function cropImageBufferNormalized(buf, box) {
  const meta = await sharp(buf).metadata();
  const w = meta.width || 1;
  const h = meta.height || 1;
  const b = clampCropBox(box);
  const left = Math.min(w - 2, Math.max(0, Math.floor(b.left * w)));
  const top = Math.min(h - 2, Math.max(0, Math.floor(b.top * h)));
  const width = Math.min(w - left, Math.max(2, Math.floor(b.width * w)));
  const height = Math.min(h - top, Math.max(2, Math.floor(b.height * h)));
  return sharp(buf).extract({ left, top, width, height }).toBuffer();
}

async function requestGarmentCropBoxFromVision({
  imageUrl,
  apiKey,
  garmentHint,
  productTitle,
}) {
  if (!apiKey || !imageUrl) return null;

  const regionHint =
    garmentHint === "upper_garment"
      ? "Crop ONLY the upper garment (jacket/top/hoodie). Below chin/neck, include torso and sleeves. Exclude head, face, hands, legs, pants, shoes."
      : garmentHint === "lower_garment"
        ? "Crop ONLY the lower garment (pants/skirt). Exclude head, torso, arms, shoes."
        : "Crop ONLY the main clothing product. Exclude visible face, head, hands, and body parts not part of the garment.";

  const prompt =
    `${regionHint}\nProduct: ${String(productTitle || "clothing").slice(0, 120)}\n` +
    'Return strict JSON only: {"top":0.0-1.0,"left":0.0-1.0,"width":0.0-1.0,"height":0.0-1.0} or {"error":"no_garment"}';

  try {
    const response = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        model: "gpt-4o-mini",
        temperature: 0,
        max_tokens: 80,
        messages: [
          {
            role: "user",
            content: [
              { type: "text", text: prompt },
              { type: "image_url", image_url: { url: imageUrl, detail: "low" } },
            ],
          },
        ],
      }),
    });

    if (!response.ok) return null;
    const aiJson = await response.json();
    const text = aiJson?.choices?.[0]?.message?.content || "";
    const parsed = extractFirstJsonObjectGlobal(text) || {};
    if (parsed.error) return null;
    if (
      parsed.top == null &&
      parsed.left == null &&
      parsed.width == null &&
      parsed.height == null
    ) {
      return null;
    }
    return clampCropBox(parsed);
  } catch (e) {
    logger.warn("[PREPARE_PRODUCT_IMAGE][garment_crop_vision_error]", {
      message: e?.message || String(e),
    });
    return null;
  }
}

/** After rembg: detect face/skin remnants in opaque cutout (upper region). */
async function cutoutContainsPersonRemnants(buf) {
  const { data, info } = await sharp(buf)
    .ensureAlpha()
    .resize(160, 160, { fit: "inside" })
    .raw()
    .toBuffer({ resolveWithObject: true });

  const w = info.width || 1;
  const h = info.height || 1;
  const channels = info.channels || 4;
  let opaqueUpper = 0;
  let skinUpper = 0;
  let opaqueTotal = 0;
  let skinTotal = 0;

  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const i = (y * w + x) * channels;
      const r = data[i];
      const g = data[i + 1];
      const b = data[i + 2];
      const a = channels >= 4 ? data[i + 3] : 255;
      if (a < 80) continue;
      opaqueTotal++;
      if (isSkinTonePixel(r, g, b)) skinTotal++;
      if (y < h * 0.38) {
        opaqueUpper++;
        if (isSkinTonePixel(r, g, b)) skinUpper++;
      }
    }
  }

  const skinUpperRatio = skinUpper / Math.max(opaqueUpper, 1);
  const skinTotalRatio = skinTotal / Math.max(opaqueTotal, 1);
  return skinUpperRatio > 0.07 || (skinTotalRatio > 0.11 && skinUpperRatio > 0.04);
}

async function findPackshotFromCandidates(scoredCandidates) {
  const sorted = [...scoredCandidates].sort(
    (a, b) => (b.cleanupScore ?? b.score) - (a.cleanupScore ?? a.score)
  );

  for (const c of sorted.slice(0, 6)) {
    const url = String(c.url || "").trim();
    if (!url || !isValidHttpUrl(url)) continue;
    const cs = c.cleanupScore ?? scoreCleanupImageCandidate(url, c);
    if (cs < CLEANUP_PACKSHOT_MIN_SCORE) continue;
    if (urlHasStrongPersonHints(url)) continue;

    try {
      const { buf } = await downloadProductImageBuffer(url);
      const visual = await analyzeVisualPersonHeuristics(buf);
      if (isLikelyFlatPackshot(visual)) {
        return {
          url,
          buf,
          reason: `packshot_visual_${c.source || "unknown"}_score_${cs}`,
        };
      }
    } catch (_) {}
  }

  const trusted = sorted.find((c) => {
    const url = String(c.url || "");
    const cs = c.cleanupScore ?? 0;
    return (
      cs >= CLEANUP_PACKSHOT_TRUST_SCORE &&
      !urlHasStrongPersonHints(url) &&
      isValidHttpUrl(url)
    );
  });
  if (trusted) {
    return {
      url: trusted.url,
      buf: null,
      reason: `packshot_score_${trusted.cleanupScore}_trusted`,
    };
  }

  return null;
}

function buildCleanupFailureResult(originalImageUrl, reason, containsPerson = true) {
  return {
    containsPerson,
    needsCleanup: containsPerson,
    cleanImageUrl: null,
    productImageUrl: originalImageUrl,
    originalImageUrl,
    analysisImageUrl: originalImageUrl,
    cleanupFailed: true,
    cleanupSucceeded: false,
    failureReason: reason,
  };
}

// ---------------------------------------------------------------------------
// Product image web search (SKU / brand+title) — before rembg fallback
// ---------------------------------------------------------------------------
const PRODUCT_SEARCH_GOOD_SCORE = 35;
const PRODUCT_SEARCH_ECOMMERCE_MIN_FILL = 0.35;
const PRODUCT_SEARCH_ECOMMERCE_MIN_CENTER = 0.45;
const PRODUCT_SEARCH_ECOMMERCE_MIN_WHITE_BG = 0.32;

/** Reject unrelated product categories in image search (SKU-only hits, wrong Serper pages). */
const PRODUCT_SEARCH_WRONG_TYPE_TERMS = [
  "suitcase",
  "luggage",
  "valise",
  "trolley",
  "backpack",
  "rucksack",
  "duffel",
  "duffle",
  "handbag",
  "purse",
  "wallet",
  "bag",
  "case",
  "shoe",
  "sneaker",
  "trainer",
  "boot",
  "cleat",
  "sandal",
  "flip-flop",
  "skirt",
  "dress",
  "gown",
  "top",
  "hoodie",
  "sweatshirt",
  "jacket",
  "coat",
  "blazer",
  "pants",
  "trouser",
  "jeans",
  "denim",
  "legging",
  "watch",
  "phone",
  "cap",
  "hat",
  "beanie",
  "workout",
  "kaiwa",
  "training",
  "gym",
  "running",
  "football",
  "soccer",
];

const PRODUCT_SEARCH_SUBCATEGORY_EXPECTATIONS = {
  plavecke_sortky: {
    positive: [
      "swim",
      "short",
      "shorts",
      "sortky",
      "plavky",
      "plaveck",
      "plavecke_sortky",
      "plavecke",
      "trunk",
      "boardshort",
      "board-short",
      "swimwear",
      "bathing",
      "swim short",
      "swimming short",
    ],
    negative: PRODUCT_SEARCH_WRONG_TYPE_TERMS,
    visual: "swim_shorts",
  },
  plavky_jednodielne: {
    positive: ["swim", "plavky", "swimsuit", "swimwear", "bathing"],
    negative: PRODUCT_SEARCH_WRONG_TYPE_TERMS,
    visual: "swimwear",
  },
  bikiny: {
    positive: ["bikini", "bikiny", "swim", "plavky"],
    negative: PRODUCT_SEARCH_WRONG_TYPE_TERMS,
    visual: "swimwear",
  },
};

function isAdidasProductSourceUrl(sourceUrl) {
  try {
    const host = new URL(sourceUrl).hostname.toLowerCase();
    return host.includes("adidas.");
  } catch (_) {
    return false;
  }
}

function buildProductSearchExpectation({
  sourceUrl = "",
  brand = "",
  title = "",
  subCategoryKey = "",
  sku = "",
}) {
  const sub = String(subCategoryKey || "").trim();
  const spec = PRODUCT_SEARCH_SUBCATEGORY_EXPECTATIONS[sub] || null;
  const sourceHost = productSearchSourceHost(sourceUrl);
  const expectation = {
    subCategoryKey: sub,
    brand: String(brand || "").trim(),
    title: String(title || "").trim(),
    sku: String(sku || "").trim().toUpperCase(),
    sourceUrl: String(sourceUrl || "").trim(),
    sourceHost,
    expectedTerms: spec?.positive || [],
    rejectTerms: spec?.negative || PRODUCT_SEARCH_WRONG_TYPE_TERMS,
    visualMode: spec?.visual || null,
    requireProductTypeMatch: !!spec,
    requireBrandForExternal: true,
  };
  console.log(
    `[PRODUCT_SEARCH][expected_subcategory] ${expectation.subCategoryKey || "(none)"} ` +
      `brand=${expectation.brand} sku=${expectation.sku}`
  );
  logger.info("[PRODUCT_SEARCH][expected_subcategory]", {
    subCategoryKey: expectation.subCategoryKey,
    brand: expectation.brand,
    sku: expectation.sku,
    sourceHost,
  });
  return expectation;
}

function productSearchCandidateTextBlob(url, candidate = {}, expected = {}) {
  const parts = [
    url,
    candidate.imageLink,
    candidate.serperSource,
    candidate.title,
    candidate.query,
    expected.title,
    expected.brand,
  ];
  return parts
    .filter(Boolean)
    .join(" ")
    .toLowerCase();
}

function productSearchHaystackHasTerm(hay, term) {
  const t = String(term || "").toLowerCase().trim();
  if (!t) return false;
  if (t.includes(" ")) return hay.includes(t);
  const re = new RegExp(`(?:^|[^a-z0-9])${t.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}(?:[^a-z0-9]|$)`);
  return re.test(hay);
}

function productSearchCandidateFromSourceShop(url, expected) {
  const host = productSearchSourceHost(url);
  const src = String(expected.sourceHost || "").toLowerCase();
  if (!host || !src) return false;
  if (host === src) return true;
  const srcRoot = src.replace(/^www\./, "").split(".")[0];
  const hostRoot = host.replace(/^www\./, "").split(".")[0];
  return srcRoot.length > 2 && host.includes(srcRoot);
}

function productSearchRejectsWrongProductType(url, candidate, expected) {
  const hay = productSearchCandidateTextBlob(url, candidate, expected);
  const title = String(candidate.serperSource || candidate.title || expected.title || "").trim();
  const urlSlice = String(url || "").slice(0, 280);

  console.log(`[PRODUCT_SEARCH][candidate_title] ${title.slice(0, 200)}`);
  console.log(`[PRODUCT_SEARCH][candidate_url] ${urlSlice}`);
  logger.info("[PRODUCT_SEARCH][candidate_title]", { title: title.slice(0, 200) });
  logger.info("[PRODUCT_SEARCH][candidate_url]", { url: urlSlice });

  if (!expected.requireProductTypeMatch) {
    return null;
  }

  for (const bad of expected.rejectTerms) {
    if (productSearchHaystackHasTerm(hay, bad)) {
      const reason = `wrong_term:${bad}`;
      console.log(
        `[PRODUCT_SEARCH][rejected_wrong_product_type] reason=${reason} url=${urlSlice}`
      );
      logger.info("[PRODUCT_SEARCH][rejected_wrong_product_type]", {
        reason,
        url: urlSlice,
        title: title.slice(0, 160),
      });
      return reason;
    }
  }

  const fromShop = productSearchCandidateFromSourceShop(url, expected);
  const hasPositive = expected.expectedTerms.some((t) => productSearchHaystackHasTerm(hay, t));
  const brandNorm = String(expected.brand || "").toLowerCase();
  const hasBrand =
    !brandNorm || hay.includes(brandNorm) || (brandNorm === "adidas" && hay.includes("adidas"));

  const skuInHay = expected.sku && hay.includes(expected.sku.toLowerCase());

  const host = productSearchSourceHost(url).toLowerCase();
  if (host.includes("adidas") && !fromShop && !hasPositive) {
    const reason = "adidas_unrelated_product";
    console.log(`[PRODUCT_SEARCH][rejected_wrong_product_type] reason=${reason} url=${urlSlice}`);
    logger.info("[PRODUCT_SEARCH][rejected_wrong_product_type]", { reason, url: urlSlice });
    return reason;
  }

  if (!fromShop) {
    if (skuInHay && !hasPositive) {
      const reason = "sku_only_no_product_type";
      console.log(`[PRODUCT_SEARCH][rejected_wrong_product_type] reason=${reason} url=${urlSlice}`);
      logger.info("[PRODUCT_SEARCH][rejected_wrong_product_type]", { reason, url: urlSlice });
      return reason;
    }
    if (!hasPositive) {
      const reason = "missing_expected_product_type";
      console.log(`[PRODUCT_SEARCH][rejected_wrong_product_type] reason=${reason} url=${urlSlice}`);
      logger.info("[PRODUCT_SEARCH][rejected_wrong_product_type]", { reason, url: urlSlice });
      return reason;
    }
    if (expected.requireBrandForExternal && !hasBrand) {
      const reason = "missing_expected_brand";
      console.log(`[PRODUCT_SEARCH][rejected_wrong_product_type] reason=${reason} url=${urlSlice}`);
      logger.info("[PRODUCT_SEARCH][rejected_wrong_product_type]", { reason, url: urlSlice });
      return reason;
    }
  } else if (!hasPositive && !skuInHay) {
    const reason = "source_shop_missing_product_type";
    console.log(`[PRODUCT_SEARCH][rejected_wrong_product_type] reason=${reason} url=${urlSlice}`);
    logger.info("[PRODUCT_SEARCH][rejected_wrong_product_type]", { reason, url: urlSlice });
    return reason;
  }

  return null;
}

function productSearchVisualMatchesSubCategory(visual, dimensions, expected) {
  if (!expected?.visualMode) return true;
  const fill = Number(visual?.productFillRatio ?? 0);
  const w = Number(dimensions?.width ?? 1);
  const h = Number(dimensions?.height ?? 1);
  const ar = w / Math.max(h, 1);

  if (fill < 0.18) return false;

  if (expected.visualMode === "swim_shorts") {
    if (ar < 0.55 && fill < 0.32) return false;
    if (fill < 0.22 && ar > 1.8) return false;
    return true;
  }

  if (expected.visualMode === "swimwear") {
    return fill >= 0.2;
  }

  return true;
}

const SERPER_IMAGES_RESULT_COUNT = 20;

/** site: queries run first (ecommerce before open web). */
const SERPER_PRIORITY_SITE_DOMAINS = [
  "aboutyou.sk",
  "zalando.sk",
  "nike.com",
  "footshop.sk",
  "aboutyou.com",
  "zalando.com",
  "adidas.com",
  "puma.com",
  "reserved.com",
  "cropp.com",
  "housebrand.com",
  "mohito.com",
  "sinsay.com",
  "answear.sk",
  "sizeer.sk",
  "a3sport.sk",
  "queens.sk",
  "jdsports",
  "footlocker",
  "urbanstore",
  "sportisimo.sk",
];

const PRODUCT_SEARCH_DOMAIN_SCORE_RULES = [
  { match: "aboutyou", score: 40, preferred: true },
  { match: "zalando", score: 35, preferred: true },
  { match: "nike", score: 35, preferred: true },
  { match: "footshop", score: 30, preferred: true },
  { match: "reserved", score: 25, preferred: true },
  { match: "mohito", score: 25, preferred: true },
  { match: "adidas", score: 28, preferred: true },
  { match: "puma", score: 28, preferred: true },
  { match: "cropp", score: 22, preferred: true },
  { match: "housebrand", score: 22, preferred: true },
  { match: "sinsay", score: 22, preferred: true },
  { match: "answear", score: 22, preferred: true },
  { match: "sizeer", score: 22, preferred: true },
  { match: "a3sport", score: 22, preferred: true },
  { match: "queens", score: 22, preferred: true },
  { match: "jdsports", score: 22, preferred: true },
  { match: "footlocker", score: 22, preferred: true },
  { match: "urbanstore", score: 20, preferred: true },
  { match: "sportisimo", score: 22, preferred: true },
  { match: "static.nike.com", score: 35, preferred: true },
  { match: "ebay", score: -40, preferred: false },
  { match: "pinterest", score: -80, preferred: false },
  { match: "instagram", score: -100, preferred: false },
  { match: "tiktok", score: -100, preferred: false },
];

const PRODUCT_SEARCH_PORTRAIT_URL_HINTS = [
  "headshot",
  "portrait",
  "lifestyle",
  "lookbook",
  "editorial",
  "street-style",
  "street_style",
  "streetwear",
  "campaign",
  "runway",
  "selfie",
  "outdoor",
  "beauty-shot",
  "beauty_shot",
];

/** Normalize host + path for CDN URL equality (drops query/hash). */
function normalizeComparableProductImageUrl(raw) {
  try {
    const u = new URL(String(raw || "").trim());
    u.hash = "";
    let path = decodeURIComponent(u.pathname.replace(/\/+/g, "/"));
    if (path.endsWith("/") && path.length > 1) path = path.slice(0, -1);
    return `${u.hostname.toLowerCase()}${path.toLowerCase()}`;
  } catch (_) {
    const base = String(raw || "").trim().split("?")[0].split("#")[0];
    try {
      return decodeURIComponent(base).toLowerCase();
    } catch (__) {
      return base.toLowerCase();
    }
  }
}

function productSearchUrlsMatchSeed(seedUrl, candidateUrl) {
  const s = normalizeComparableProductImageUrl(seedUrl);
  const c = normalizeComparableProductImageUrl(candidateUrl);
  return s.length > 0 && c.length > 0 && s === c;
}

async function imageBuffersNearDuplicateRgb(
  seedBuf,
  candBuf,
  rmseThreshold = 12
) {
  if (!seedBuf || !candBuf) return { nearDup: false, rmse: null };

  async function downs(buf) {
    const { data } = await sharp(buf)
      .resize(48, 48, { fit: "cover", position: "centre" })
      .removeAlpha()
      .raw()
      .toBuffer({ resolveWithObject: true });
    return Buffer.from(data);
  }

  try {
    const [aBuf, bBuf] = await Promise.all([downs(seedBuf), downs(candBuf)]);
    if (aBuf.length !== bBuf.length || !aBuf.length)
      return { nearDup: false, rmse: null };

    let sse = 0;
    const n = aBuf.length;
    for (let i = 0; i < n; i++) {
      const d = aBuf[i] - bBuf[i];
      sse += d * d;
    }
    const rmse = Math.sqrt(sse / n);
    return { nearDup: rmse < rmseThreshold, rmse: Number(rmse.toFixed(2)) };
  } catch (_) {
    return { nearDup: false, rmse: null };
  }
}

function productSearchUrlSuggestsPortraitOrLifestyle(url) {
  const u = String(url || "").toLowerCase();
  if (!u) return false;
  if (PRODUCT_SEARCH_PORTRAIT_URL_HINTS.some((h) => u.includes(h))) return true;
  if (u.includes("/face/") || u.includes("-face-") || u.endsWith("/face")) return true;
  return false;
}

function productSearchSourceDomainScore(url, pageLink = "") {
  const blob = `${url} ${pageLink} ${productSearchSourceHost(url)} ${productSearchSourceHost(pageLink)}`.toLowerCase();
  let score = 0;
  let label = "";
  let preferred = false;

  for (const rule of PRODUCT_SEARCH_DOMAIN_SCORE_RULES) {
    if (blob.includes(rule.match)) {
      if (Math.abs(rule.score) > Math.abs(score)) {
        score = rule.score;
        label = rule.match;
        preferred = rule.preferred === true;
      }
    }
  }

  return { score, label, preferred };
}

function productSearchRetailerBonus(url, visual) {
  const domain = productSearchSourceDomainScore(url);
  const breakdown = {};
  let bonus = domain.score;
  if (domain.label) breakdown[`domain_${domain.label}`] = domain.score;

  // Adidas packshots often use grey/off-white — do not require high whiteBackgroundRatio.
  const u = String(url || "").toLowerCase();
  if (!u.includes("assets.adidas.com") && visual?.whiteBackgroundRatio >= 0.38) {
    bonus += 20;
    breakdown.ecommerce_white_bg = 20;
  }

  return { bonus, breakdown, preferred: domain.preferred, domainLabel: domain.label };
}

function productSearchUrlHasAdidasProductTypeTerm(url, expected) {
  const hay = String(url || "").toLowerCase();
  const terms = [
    ...(expected?.expectedTerms || []),
    "plavecke_sortky",
    "plavecke",
    "plavky",
    "swim",
    "shorts",
    "short",
    "sortky",
  ];
  return terms.some((term) => {
    const t = String(term || "").toLowerCase().trim();
    if (!t) return false;
    if (t.includes(" ")) return hay.includes(t);
    return hay.includes(t);
  });
}

function productSearchIsAdidasLaydownPackshotUrl(url) {
  const u = String(url || "").toLowerCase();
  return (
    u.includes("laydown") ||
    u.includes("01_laydown") ||
    u.includes("hover") ||
    (u.includes("product") && u.includes("assets.adidas.com"))
  );
}

/** Official Adidas CDN packshot — grey bg OK; no high whiteBackgroundRatio required. */
function productSearchIsAdidasOfficialPackshot(url, visual, dimensions, expected) {
  if (!visual) return false;
  const u = String(url || "").toLowerCase();
  if (!u.includes("assets.adidas.com")) return false;

  const sku = String(expected?.sku || "").trim().toUpperCase();
  if (!sku || !u.includes(sku.toLowerCase())) return false;

  if (!productSearchUrlHasAdidasProductTypeTerm(url, expected)) return false;

  const faceRatio = Number(visual.skinFaceRatio ?? 0);
  if (faceRatio > 0.01) return false;

  if (dimensions?.portraitLike === true) return false;

  if (Number(visual.productFillRatio ?? 0) < 0.35) return false;

  return true;
}

function logProductSearchAcceptedAdidasLaydownPackshot({
  phaseLabel,
  url,
  visual,
  dimensions,
  candidateScore,
}) {
  const candUrlSlice = String(url || "").slice(0, 280);
  const line =
    `[PRODUCT_SEARCH][accepted_adidas_laydown_packshot] phase=${phaseLabel} ` +
    `score=${candidateScore ?? "?"} fill=${visual?.productFillRatio ?? "?"} ` +
    `white=${visual?.whiteBackgroundRatio ?? "?"} url=${candUrlSlice}`;
  console.log(line);
  logger.info("[PRODUCT_SEARCH][accepted_adidas_laydown_packshot]", {
    phase: phaseLabel,
    candidateScore,
    productFillRatio: visual?.productFillRatio,
    whiteBackgroundRatio: visual?.whiteBackgroundRatio,
    skinFaceRatio: visual?.skinFaceRatio,
    portraitLike: dimensions?.portraitLike,
    url: candUrlSlice,
  });
}

function productSearchIsEcommerceProductShot(visual) {
  if (!visual) return false;
  return (
    visual.productFillRatio >= PRODUCT_SEARCH_ECOMMERCE_MIN_FILL &&
    visual.centeredProductRatio >= PRODUCT_SEARCH_ECOMMERCE_MIN_CENTER &&
    visual.whiteBackgroundRatio >= PRODUCT_SEARCH_ECOMMERCE_MIN_WHITE_BG
  );
}

function productSearchCandidateHasModel(visual) {
  if (!visual) return false;
  return (
    visual.skinToneRatio >= 0.012 ||
    visual.fullStandingModel === true ||
    visual.skinFaceRatio >= 0.03
  );
}

/** Reject portrait/lifestyle only — not standard ecommerce model shots. */
function productSearchRejectsPortraitOrLifestyle(url, visual, dimensions) {
  if (!visual) return "no_visual_analysis";
  if (productSearchUrlSuggestsPortraitOrLifestyle(url)) return "url_portrait_or_lifestyle";

  if (visual.productFillRatio < PRODUCT_SEARCH_ECOMMERCE_MIN_FILL) {
    return "clothing_too_small";
  }

  if (visual.skinFaceRatio >= 0.12) return "face_dominates";
  if (visual.skinFaceRatio >= 0.08 && visual.productFillRatio < 0.32) {
    return "face_dominates";
  }

  if (
    dimensions?.portraitLike &&
    dimensions?.substantial &&
    visual.skinFaceRatio >= 0.06 &&
    visual.productFillRatio < 0.38
  ) {
    return "portrait_headshot";
  }

  if (
    visual.whiteBackgroundRatio < 0.2 &&
    visual.colorVarianceHigh &&
    visual.skinToneRatio > 0.03
  ) {
    return "lifestyle_scene";
  }

  if (visual.skinToneRatio >= 0.09 && visual.productFillRatio < 0.3) {
    return "multiple_people_or_busy_scene";
  }

  return null;
}

/** Accept flat packshot OR standard ecommerce shot (model on clean background OK). */
function productSearchIsAcceptableProductImage(url, visual, dimensions, expected) {
  if (!visual) return false;
  if (productSearchRejectsPortraitOrLifestyle(url, visual, dimensions)) return false;

  if (expected && productSearchIsAdidasOfficialPackshot(url, visual, dimensions, expected)) {
    return true;
  }

  if (isLikelyFlatPackshot(visual)) return true;
  if (productSearchIsEcommerceProductShot(visual)) return true;
  if (visual.ecommerceProductShot === true) return true;

  return false;
}

/** Score — retailer bonuses; soft model penalties; hard reject portrait cues only. */
function scoreProductSearchCandidate(url, visual, dimensions) {
  const breakdown = {};
  let score = 0;
  const u = String(url || "").toLowerCase();
  const ecommerce = productSearchIsEcommerceProductShot(visual);

  const retailer = productSearchRetailerBonus(url, visual);
  score += retailer.bonus;
  Object.assign(breakdown, retailer.breakdown);

  if (productSearchUrlSuggestsPortraitOrLifestyle(url)) {
    score -= 100;
    breakdown.portrait_url = -100;
  }
  if (u.includes("headshot") || (u.includes("portrait") && !ecommerce)) {
    score -= 100;
    breakdown.portrait = -100;
  }

  if (visual) {
    if (u.includes("assets.adidas.com") && u.includes("laydown")) {
      score += 40;
      breakdown.adidas_laydown_packshot = 40;
    }
    if (visual.productFillRatio >= PRODUCT_SEARCH_ECOMMERCE_MIN_FILL) {
      score += 60;
      breakdown.product_fill = 60;
    }
    if (visual.centeredProductRatio >= PRODUCT_SEARCH_ECOMMERCE_MIN_CENTER) {
      score += 20;
      breakdown.centered_object = 20;
    }
    if (visual.whiteBackgroundRatio >= PRODUCT_SEARCH_ECOMMERCE_MIN_WHITE_BG) {
      score += 30;
      breakdown.white_background = 30;
    }
    if (visual.isolatedProduct || visual.ecommerceProductShot) {
      score += 15;
      breakdown.ecommerce_shot = 15;
    }

    if (visual.skinFaceRatio >= 0.12) {
      score -= 100;
      breakdown.face_dominates = -100;
    } else if (visual.skinFaceRatio >= 0.08 && visual.productFillRatio < 0.32) {
      score -= 60;
      breakdown.face_dominates = -60;
    } else if (visual.skinFaceRatio >= 0.05 && !ecommerce) {
      score -= 25;
      breakdown.face_soft = -25;
    }

    if (ecommerce && productSearchCandidateHasModel(visual)) {
      score += 25;
      breakdown.model_white_bg_ecommerce = 25;
    } else if (productSearchCandidateHasModel(visual)) {
      score -= 15;
      breakdown.model_soft = -15;
    }

    if (visual.productFillRatio < PRODUCT_SEARCH_ECOMMERCE_MIN_FILL) {
      score -= 80;
      breakdown.clothing_small = -80;
    }
  }

  return { score, breakdown };
}

function logProductSearchRejectedPortrait({
  phaseLabel,
  reason,
  url,
  visual,
  dimensions,
  candidateScore,
}) {
  const candUrlSlice = String(url || "").slice(0, 280);
  const line =
    `[PRODUCT_SEARCH][rejected_portrait] phase=${phaseLabel} reason=${reason} ` +
    `score=${candidateScore ?? "?"} fill=${visual?.productFillRatio ?? "?"} ` +
    `face=${visual?.skinFaceRatio ?? "?"} url=${candUrlSlice}`;
  console.log(line);
  logger.info("[PRODUCT_SEARCH][rejected_portrait]", {
    phase: phaseLabel,
    reason,
    candidateScore,
    productFillRatio: visual?.productFillRatio,
    skinFaceRatio: visual?.skinFaceRatio,
    whiteBackgroundRatio: visual?.whiteBackgroundRatio,
    portraitLike: dimensions?.portraitLike,
    url: candUrlSlice,
  });
}

function logProductSearchAcceptedModelProduct({
  phaseLabel,
  url,
  score,
  visual,
  source,
  sourceHost,
}) {
  const candUrlSlice = String(url || "").slice(0, 280);
  const line =
    `[PRODUCT_SEARCH][accepted_model_product] phase=${phaseLabel} score=${score} ` +
    `fill=${visual?.productFillRatio ?? "?"} white=${visual?.whiteBackgroundRatio ?? "?"} ` +
    `url=${candUrlSlice}`;
  console.log(line);
  logger.info("[PRODUCT_SEARCH][accepted_model_product]", {
    phase: phaseLabel,
    score,
    source,
    sourceHost,
    productFillRatio: visual?.productFillRatio,
    centeredProductRatio: visual?.centeredProductRatio,
    whiteBackgroundRatio: visual?.whiteBackgroundRatio,
    url: candUrlSlice,
  });
}

function logProductSearchCandidateScore({ phaseLabel, url, scoreResult, visual }) {
  const line =
    `[PRODUCT_SEARCH][candidate_score] phase=${phaseLabel} total=${scoreResult.score} ` +
    `breakdown=${JSON.stringify(scoreResult.breakdown)} url=${String(url || "").slice(0, 200)}`;
  console.log(line);
  logger.info("[PRODUCT_SEARCH][candidate_score]", {
    phase: phaseLabel,
    total: scoreResult.score,
    breakdown: scoreResult.breakdown,
    productFill: visual?.productFillRatio,
    centered: visual?.centeredProductRatio,
    whiteBg: visual?.whiteBackgroundRatio,
    url: String(url || "").slice(0, 200),
  });
}

const SERPER_IMAGES_ENDPOINT = "https://google.serper.dev/images";

function getSerperApiConfig() {
  let configKey = "";
  try {
    const serperCfg = functions.config()?.serper;
    configKey = String(serperCfg?.api_key || "").trim();
  } catch (e) {
    logger.warn("[PRODUCT_SEARCH][serper_config_read_error]", {
      message: e?.message || String(e),
    });
  }

  const apiKey = String(process.env.SERPER_API_KEY || configKey || "").trim();
  return { apiKey, configKey };
}

/** Logs before Serper image search (never logs API key value). */
function logProductSearchSerperStartup() {
  const { apiKey, configKey } = getSerperApiConfig();

  console.log("[PRODUCT_SEARCH][serper_key_exists]", !!apiKey);
  console.log("[PRODUCT_SEARCH][serper_key_length]", apiKey?.length || 0);

  const keyFromEnv = Boolean(String(process.env.SERPER_API_KEY || "").trim());
  console.log("[PRODUCT_SEARCH][serper_key_from_env]", keyFromEnv);
  console.log("[PRODUCT_SEARCH][serper_key_from_functions_config]", !!configKey);

  logger.info("[PRODUCT_SEARCH][serper_startup]", {
    keyExists: !!apiKey,
    keyLength: apiKey?.length || 0,
    keyFromEnv,
    keyFromFunctionsConfig: !!configKey,
  });

  if (!apiKey) {
    console.log("[PRODUCT_SEARCH][serper_disabled]");
    logger.warn("[PRODUCT_SEARCH][serper_disabled]");
  }
}

function extractProductSkuFromText(text, sourceUrl = "") {
  const blob = `${text} ${sourceUrl}`.toUpperCase();
  const patterns = [
    /\b([A-Z]{2}[A-Z0-9]{4}-\d{3})\b/,
    /\b([A-Z]{2,4}\d{4,8}-\d{2,4})\b/,
    /\b([A-Z]{2}\d{4,6})\b/,
  ];
  for (const re of patterns) {
    const m = blob.match(re);
    if (m && m[1]) return m[1];
  }
  try {
    const parts = new URL(sourceUrl).pathname.split("/").filter(Boolean);
    for (let i = parts.length - 1; i >= 0; i--) {
      const seg = parts[i].toUpperCase().replace(/\.HTML$/i, "");
      const nike = seg.match(/^([A-Z]{2}[A-Z0-9]{4}-\d{3})$/);
      if (nike) return nike[1];
      const adidas = seg.match(/^([A-Z]{2}\d{4,6})$/);
      if (adidas) return adidas[1];
    }
  } catch (_) {}
  return "";
}

function productSearchSourceHost(url) {
  try {
    return new URL(String(url || "")).hostname.replace(/^www\./i, "");
  } catch (_) {
    return "";
  }
}

function shortenTitleForSkuSearchQuery(title) {
  const words = String(title || "")
    .trim()
    .split(/\s+/)
    .filter(Boolean);
  return words.slice(0, 4).join(" ");
}

/** Ecommerce site: queries first, then open-web SKU fallbacks (never SKU-only). */
function buildSerperImageSearchQueries({ sku, brand, title, subCategoryKey = "" }) {
  const s = String(sku || "").trim().toUpperCase();
  const b = String(brand || "").trim();
  const productName = shortenTitleForSkuSearchQuery(title);
  const queries = [];
  if (!s) return queries;

  const sub = String(subCategoryKey || "").trim();
  const spec = PRODUCT_SEARCH_SUBCATEGORY_EXPECTATIONS[sub];
  const typePhrase =
    sub === "plavecke_sortky"
      ? "swim shorts"
      : spec
        ? "swimwear"
        : productName || "product";

  const brandSkuType = b ? `${b} ${typePhrase} ${s}` : `${typePhrase} ${s}`;
  queries.push(brandSkuType);

  for (const site of SERPER_PRIORITY_SITE_DOMAINS) {
    queries.push(`${brandSkuType} site:${site}`);
  }

  if (b && productName) {
    queries.push(`${b} ${productName} ${s}`.slice(0, 140));
  }

  return [...new Set(queries.map((q) => q.trim()).filter(Boolean))];
}

function buildProductSearchQueries({ sku, brand, title, colors }) {
  const skuFirst = buildSerperImageSearchQueries({ sku, brand, title });
  if (skuFirst.length) return skuFirst;

  const queries = [];
  const s = String(sku || "").trim().toUpperCase();
  const b = String(brand || "").trim();
  const t = String(title || "").trim();
  const colorWord = Array.isArray(colors) && colors.length ? String(colors[0]) : "";

  if (s) {
    queries.push(s);
    if (b) queries.push(`${b} ${s}`);
  }
  if (b && t) {
    let q = `${b} ${t}`;
    if (colorWord) q += ` ${colorWord}`;
    queries.push(q.slice(0, 140));
  } else if (t) {
    queries.push(t.slice(0, 140));
  }
  return [...new Set(queries.filter(Boolean))].slice(0, 6);
}

function scoreProductSearchCandidateUrl(url, pageLink = "") {
  const u = String(url || "").toLowerCase();
  if (!u || !isValidHttpUrl(url)) return -999;

  let score = productSearchSourceDomainScore(url, pageLink).score;
  if (u.includes("face") || u.includes("portrait") || u.includes("headshot")) score -= 100;
  if (u.includes("model") || u.includes("athlete")) score -= 40;
  if (u.includes("lifestyle") || u.includes("editorial") || u.includes("lookbook")) {
    score -= 50;
  }
  if (u.includes("onbody") || u.includes("on-body") || u.includes("worn")) score -= 50;
  if (urlHasStrongPersonHints(url)) score -= 30;

  if (u.includes("packshot") || u.includes("pack-shot") || u.includes("flat")) score += 20;
  if (u.includes("product") && !u.includes("model")) score += 15;
  if (u.endsWith(".png")) score += 30;
  if (u.includes("white") || u.includes("transparent")) score += 10;

  return score;
}


function parseSerperImageHits(json) {
  const images = Array.isArray(json?.images) ? json.images : [];
  const hits = [];

  for (const img of images) {
    const imageUrl = String(img?.imageUrl || "").trim();
    const imageLink = String(img?.imageLink || img?.link || "").trim();
    const source = String(img?.source || "").trim();
    const domain = String(img?.domain || "").trim();
    const url = imageUrl || imageLink;
    if (!url || !isValidHttpUrl(url)) continue;

    const sourceHost =
      domain.replace(/^www\./i, "") ||
      productSearchSourceHost(imageLink) ||
      productSearchSourceHost(url);

    hits.push({ imageUrl, imageLink, source, domain, url, sourceHost });
  }

  return hits;
}

async function fetchSerperImagesForQuery(query) {
  const { apiKey } = getSerperApiConfig();
  if (!apiKey || !query) {
    return [];
  }

  const rawQuery = String(query || "").trim();
  console.log("[PRODUCT_SEARCH][serper_query]", rawQuery);
  logger.info("[PRODUCT_SEARCH][serper_query]", { query: rawQuery.slice(0, 200) });

  try {
    const res = await fetch(SERPER_IMAGES_ENDPOINT, {
      method: "POST",
      headers: {
        "X-API-KEY": apiKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ q: rawQuery, num: SERPER_IMAGES_RESULT_COUNT }),
    });

    const status = res.status;
    const statusText = res.statusText || "";
    let bodyText = "";
    try {
      bodyText = await res.text();
    } catch (readErr) {
      bodyText = `(failed to read response body: ${readErr?.message || readErr})`;
    }

    if (!res.ok) {
      console.log("[PRODUCT_SEARCH][serper_http_status]", status, statusText);
      console.log("[PRODUCT_SEARCH][serper_error_body]", bodyText.slice(0, 1000));
      logger.warn("[PRODUCT_SEARCH][serper_http_error]", {
        status,
        statusText,
        query: rawQuery.slice(0, 120),
        errorBody: bodyText.slice(0, 1000),
      });
      return [];
    }

    let json;
    try {
      json = JSON.parse(bodyText);
    } catch (parseErr) {
      console.log(
        "[PRODUCT_SEARCH][serper_parse_error]",
        parseErr?.message || String(parseErr)
      );
      return [];
    }

    const hits = parseSerperImageHits(json);
    if (!hits.length) {
      logger.info("[PRODUCT_SEARCH][serper_empty_results]", {
        query: rawQuery.slice(0, 120),
      });
    }
    return hits;
  } catch (e) {
    const msg = e?.message || String(e);
    console.log("[PRODUCT_SEARCH][serper_http_status] network_error");
    console.log("[PRODUCT_SEARCH][serper_error_body]", msg.slice(0, 1000));
    logger.warn("[PRODUCT_SEARCH][serper_error]", {
      message: msg,
      query: rawQuery.slice(0, 80),
    });
    return [];
  }
}

async function collectSerperImageCandidatesFirst({ sku, brand, title, subCategoryKey = "" }) {
  const seen = new Set();
  const candidates = [];
  const queries = buildSerperImageSearchQueries({ sku, brand, title, subCategoryKey });
  const { apiKey } = getSerperApiConfig();

  if (!apiKey) {
    console.log("[PRODUCT_SEARCH][serper_skipped] reason=no_api_key");
    return { candidates, queries };
  }

  console.log("[PRODUCT_SEARCH][using_serper_first]");
  logger.info("[PRODUCT_SEARCH][using_serper_first]", {
    sku,
    queryCount: queries.length,
    siteQueryCount: SERPER_PRIORITY_SITE_DOMAINS.length,
    resultCount: SERPER_IMAGES_RESULT_COUNT,
  });

  const siteQueries = queries.filter((q) => q.includes("site:"));
  const fallbackQueries = queries.filter((q) => !q.includes("site:"));

  const runQueryBatch = async (batch) => {
    for (const q of batch) {
      const hits = await fetchSerperImagesForQuery(q);
      for (const hit of hits) {
      const url = String(hit.url || "").trim();
      if (!url || !isValidHttpUrl(url) || seen.has(url)) continue;
      seen.add(url);

      const domainScore = productSearchSourceDomainScore(url, hit.imageLink);
      if (domainScore.preferred) {
        const pd =
          `[PRODUCT_SEARCH][preferred_domain_hit] domain=${domainScore.label} score=${domainScore.score} ` +
          `query=${q.slice(0, 100)} url=${url.slice(0, 200)}`;
        console.log(pd);
        logger.info("[PRODUCT_SEARCH][preferred_domain_hit]", {
          domain: domainScore.label,
          domainScore: domainScore.score,
          query: q.slice(0, 120),
          url: url.slice(0, 240),
          imageLink: String(hit.imageLink || "").slice(0, 240),
        });
      }

      const sr =
        `[PRODUCT_SEARCH][serper_result] imageUrl=${String(hit.imageUrl || "").slice(0, 200)} ` +
        `imageLink=${String(hit.imageLink || "").slice(0, 200)} ` +
        `source=${String(hit.source || "").slice(0, 80)} ` +
        `domain=${String(hit.domain || hit.sourceHost || "").slice(0, 80)} domainScore=${domainScore.score}`;
      console.log(sr);
      logger.info("[PRODUCT_SEARCH][serper_result]", {
        imageUrl: String(hit.imageUrl || "").slice(0, 240),
        imageLink: String(hit.imageLink || "").slice(0, 240),
        source: hit.source || "",
        domain: hit.domain || hit.sourceHost || "",
        domainScore: domainScore.score,
        domainLabel: domainScore.label,
        query: q.slice(0, 120),
      });

        candidates.push({
          url,
          source: "serper_images",
          sourceHost: hit.sourceHost || hit.domain || productSearchSourceHost(url),
          query: q,
          imageUrl: hit.imageUrl,
          imageLink: hit.imageLink,
          serperSource: hit.source,
          serperDomain: hit.domain,
          domainScore: domainScore.score,
          domainLabel: domainScore.label,
          preferredDomain: domainScore.preferred,
        });
      }
    }
  };

  await runQueryBatch(siteQueries);

  const preferredHits = candidates.filter((c) => c.preferredDomain).length;
  if (preferredHits === 0) {
    console.log("[PRODUCT_SEARCH][serper_open_web_fallback] reason=no_preferred_domain_hits");
    logger.info("[PRODUCT_SEARCH][serper_open_web_fallback]", {
      siteQueries: siteQueries.length,
      candidatesSoFar: candidates.length,
    });
    await runQueryBatch(fallbackQueries);
  }

  candidates.sort((a, b) => (b.domainScore ?? 0) - (a.domainScore ?? 0));

  const countLine = `[PRODUCT_SEARCH][serper_candidate_count] ${candidates.length}`;
  console.log(countLine);
  logger.info(countLine);

  return { candidates, queries };
}

async function collectPageGalleryCandidates(sourceUrl, context = {}) {
  const candidates = [];
  const seen = new Set();

  if (!sourceUrl || !sourceUrl.includes("://")) {
    return candidates;
  }

  const shopHost = productSearchSourceHost(sourceUrl);
  const isNike = shopHost.includes("nike");
  const isAdidas = shopHost.includes("adidas");
  if (isNike) {
    console.log("[PRODUCT_SEARCH][nike_gallery_fallback]");
    logger.info("[PRODUCT_SEARCH][nike_gallery_fallback]", { sourceUrl: sourceUrl.slice(0, 160) });
  }
  if (isAdidas) {
    console.log("[PRODUCT_SEARCH][adidas_page_gallery]");
    logger.info("[PRODUCT_SEARCH][adidas_page_gallery]", { sourceUrl: sourceUrl.slice(0, 160) });
  }

  console.log("[PRODUCT_SEARCH][page_gallery_start]");
  logger.info("[PRODUCT_SEARCH][page_gallery_start]", { shopHost });

  const expected = buildProductSearchExpectation({
    sourceUrl,
    brand: context.brand || "",
    title: context.title || "",
    subCategoryKey: context.subCategoryKey || "",
    sku: context.sku || "",
  });

  try {
    const pageHtml = await fetchProductPageHtml(sourceUrl);
    const meta = extractStrategy1Metadata(pageHtml);
    const jsonLd = extractStrategy2JsonLd(pageHtml);
    const signals = {
      slug: { hostname: shopHost },
      metadata: { ...meta, raw: meta.raw || meta },
      jsonLd,
    };
    const list = buildProductImageCandidatesList(sourceUrl, pageHtml, signals);
    for (const c of list) {
      const url = String(c.url || "").trim();
      if (!url || !isValidHttpUrl(url) || seen.has(url)) continue;
      if (expected.requireProductTypeMatch) {
        const typeReject = productSearchRejectsWrongProductType(url, { title: meta.title || "" }, expected);
        if (typeReject) continue;
      }
      seen.add(url);
      candidates.push({
        url,
        source: `page_${c.source}`,
        sourceHost: productSearchSourceHost(url) || shopHost,
        title: meta.title || "",
      });
    }
  } catch (e) {
    logger.warn("[PRODUCT_SEARCH][page_candidates_error]", {
      message: e?.message || String(e),
    });
  }

  logger.info("[PRODUCT_SEARCH][page_gallery_count]", { count: candidates.length });
  return candidates;
}

async function tryEvaluateProductSearchCandidates({
  uid,
  itemId,
  seed,
  seedBuf,
  candidates,
  phaseLabel,
  expected = null,
}) {
  const ranked = [...candidates]
    .map((c) => {
      const fromSourceShop =
        expected && productSearchCandidateFromSourceShop(c.url, expected) ? 40 : 0;
      const pageGalleryBoost =
        String(c.source || "").startsWith("page_") && fromSourceShop > 0 ? 25 : 0;
      return {
        ...c,
        urlScore:
          scoreProductSearchCandidateUrl(c.url, c.imageLink) +
          (c.domainScore ?? 0) +
          (c.preferredDomain ? 15 : 0) +
          (c.source === "serper_images" ? 8 : 0) +
          fromSourceShop +
          pageGalleryBoost,
      };
    })
    .sort((a, b) => b.urlScore - a.urlScore);

  let hadCandidateInspection = false;

  for (const c of ranked) {
    if ((c.urlScore ?? 0) < 5) {
      const rej = `[PRODUCT_SEARCH][candidate_rejected] phase=${phaseLabel} reason=low_url_score url=${String(c.url).slice(0, 200)}`;
      console.log(rej);
      logger.info(rej);
      continue;
    }

    const candUrlSlice = String(c.url || "").slice(0, 280);
    console.log(`[PRODUCT_SEARCH][candidate_url] ${candUrlSlice}`);
    logger.info("[PRODUCT_SEARCH][candidate_url]", {
      url: candUrlSlice,
      source: c.source,
      phase: phaseLabel,
    });

    if (seed && productSearchUrlsMatchSeed(seed, c.url)) {
      hadCandidateInspection = true;
      const rej =
        `[PRODUCT_SEARCH][candidate_rejected] phase=${phaseLabel} reason=same_url_as_seed url=${candUrlSlice}`;
      console.log(rej);
      logger.info(rej);
      continue;
    }

    if (expected) {
      const typeReject = productSearchRejectsWrongProductType(c.url, c, expected);
      if (typeReject) {
        const rej =
          `[PRODUCT_SEARCH][candidate_rejected] phase=${phaseLabel} reason=${typeReject} url=${candUrlSlice}`;
        console.log(rej);
        logger.info(rej);
        continue;
      }
    }

    try {
      const { buf: candBuf } = await downloadProductImageBuffer(c.url);
      hadCandidateInspection = true;

      let nearDup = false;
      let dupRmse = null;
      if (seedBuf) {
        ({ nearDup, rmse: dupRmse } = await imageBuffersNearDuplicateRgb(seedBuf, candBuf));
      }

      const dimensions = await analyzeImageDimensionsForPerson(candBuf);
      const visual = await analyzeVisualPersonHeuristics(candBuf);
      const scoreResult = scoreProductSearchCandidate(c.url, visual, dimensions);
      logProductSearchCandidateScore({
        phaseLabel,
        url: c.url,
        scoreResult,
        visual,
      });

      if (nearDup) {
        const rej =
          `[PRODUCT_SEARCH][candidate_rejected] phase=${phaseLabel} reason=near_duplicate_seed rmse=${dupRmse} url=${candUrlSlice}`;
        console.log(rej);
        logger.info(rej);
        continue;
      }

      const portraitReject = productSearchRejectsPortraitOrLifestyle(
        c.url,
        visual,
        dimensions
      );
      if (portraitReject) {
        logProductSearchRejectedPortrait({
          phaseLabel,
          reason: portraitReject,
          url: c.url,
          visual,
          dimensions,
          candidateScore: scoreResult.score,
        });
        const rej =
          `[PRODUCT_SEARCH][candidate_rejected] phase=${phaseLabel} reason=${portraitReject} sourceHost=${c.sourceHost || ""} url=${candUrlSlice}`;
        console.log(rej);
        logger.info(rej);
        continue;
      }

      const totalScore = scoreResult.score;
      const adidasPackshot =
        expected &&
        productSearchIsAdidasOfficialPackshot(c.url, visual, dimensions, expected);
      const acceptable =
        productSearchIsAcceptableProductImage(c.url, visual, dimensions, expected) ||
        adidasPackshot;

      if (adidasPackshot && productSearchIsAdidasLaydownPackshotUrl(c.url)) {
        logProductSearchAcceptedAdidasLaydownPackshot({
          phaseLabel,
          url: c.url,
          visual,
          dimensions,
          candidateScore: totalScore,
        });
      }

      if (!acceptable) {
        logProductSearchRejectedPortrait({
          phaseLabel,
          reason: "not_ecommerce_product_shot",
          url: c.url,
          visual,
          dimensions,
          candidateScore: totalScore,
        });
        const rej =
          `[PRODUCT_SEARCH][candidate_rejected] phase=${phaseLabel} reason=not_ecommerce_product_shot score=${totalScore} url=${candUrlSlice}`;
        console.log(rej);
        logger.info(rej);
        continue;
      }

      if (expected && !productSearchVisualMatchesSubCategory(visual, dimensions, expected)) {
        const rej =
          `[PRODUCT_SEARCH][candidate_rejected] phase=${phaseLabel} reason=visual_mismatch_subcategory url=${candUrlSlice}`;
        console.log(rej);
        logger.info(rej);
        continue;
      }

      if (scoreResult.breakdown.face_dominates === -100 || scoreResult.breakdown.portrait_url === -100) {
        logProductSearchRejectedPortrait({
          phaseLabel,
          reason: "portrait_score_penalty",
          url: c.url,
          visual,
          dimensions,
          candidateScore: totalScore,
        });
        continue;
      }

      if (totalScore < PRODUCT_SEARCH_GOOD_SCORE) {
        const rej =
          `[PRODUCT_SEARCH][candidate_rejected] phase=${phaseLabel} reason=score_below_threshold score=${totalScore} url=${candUrlSlice}`;
        console.log(rej);
        logger.info(rej);
        continue;
      }

      let productBuffer = candBuf;
      try {
        productBuffer = await buildProductPhotoBuffer(candBuf);
      } catch (_) {}

      let nearDupAfterProcess = false;
      let dupRmse2 = null;
      if (seedBuf && productBuffer) {
        ({ nearDup: nearDupAfterProcess, rmse: dupRmse2 } =
          await imageBuffersNearDuplicateRgb(seedBuf, productBuffer));
      }

      if (nearDupAfterProcess) {
        const rej =
          `[PRODUCT_SEARCH][candidate_rejected] phase=${phaseLabel} reason=near_duplicate_after_processing rmse=${dupRmse2} url=${candUrlSlice}`;
        console.log(rej);
        logger.info(rej);
        continue;
      }

      const postVisual = await analyzeVisualPersonHeuristics(productBuffer);
      const postDimensions = await analyzeImageDimensionsForPerson(productBuffer);
      const postScoreResult = scoreProductSearchCandidate(c.url, postVisual, postDimensions);
      logProductSearchCandidateScore({
        phaseLabel: `${phaseLabel}_post`,
        url: c.url,
        scoreResult: postScoreResult,
        visual: postVisual,
      });

      const postReject = productSearchRejectsPortraitOrLifestyle(
        c.url,
        postVisual,
        postDimensions
      );
      if (postReject) {
        logProductSearchRejectedPortrait({
          phaseLabel,
          reason: `after_processing_${postReject}`,
          url: c.url,
          visual: postVisual,
          dimensions: postDimensions,
          candidateScore: postScoreResult.score,
        });
        continue;
      }
      const postAcceptable =
        productSearchIsAcceptableProductImage(
          c.url,
          postVisual,
          postDimensions,
          expected
        ) ||
        (expected &&
          productSearchIsAdidasOfficialPackshot(
            c.url,
            postVisual,
            postDimensions,
            expected
          ));
      if (!postAcceptable) {
        logProductSearchRejectedPortrait({
          phaseLabel,
          reason: "after_processing_not_ecommerce_shot",
          url: c.url,
          visual: postVisual,
          dimensions: postDimensions,
          candidateScore: postScoreResult.score,
        });
        continue;
      }

      const preHadModel = productSearchCandidateHasModel(visual);
      let remnantPerson = false;
      try {
        remnantPerson = await cutoutContainsPersonRemnants(productBuffer);
      } catch (_) {}
      if (remnantPerson && !preHadModel) {
        logProductSearchRejectedPortrait({
          phaseLabel,
          reason: "after_processing_face_or_skin_remnants",
          url: c.url,
          visual: postVisual,
          dimensions: postDimensions,
          candidateScore: postScoreResult.score,
        });
        continue;
      }

      if (preHadModel && productSearchIsEcommerceProductShot(visual)) {
        logProductSearchAcceptedModelProduct({
          phaseLabel,
          url: c.url,
          score: totalScore,
          visual,
          source: c.source,
          sourceHost: c.sourceHost,
        });
      }

      const acceptLine =
        `[PRODUCT_SEARCH][selected_clean_packshot] phase=${phaseLabel} source=${c.source} sourceHost=${c.sourceHost || ""} score=${totalScore} url=${candUrlSlice}`;
      console.log(acceptLine);
      logger.info("[PRODUCT_SEARCH][selected_clean_packshot]", {
        phase: phaseLabel,
        source: c.source,
        sourceHost: c.sourceHost || "",
        score: totalScore,
        url: candUrlSlice,
      });

      const stagedUrl = await uploadProductLinkStagingImage(uid, productBuffer, { itemId });
      console.log("[PRODUCT_SEARCH][selected_image_url]", stagedUrl);
      logger.info("[PRODUCT_SEARCH][selected_image_url]", { url: stagedUrl.slice(0, 280) });
      return {
        found: true,
        productImageUrl: stagedUrl,
        cleanImageUrl: stagedUrl,
        sourceCandidateUrl: c.url,
        hadCandidateInspection,
        winner: {
          url: c.url,
          source: c.source,
          sourceHost: c.sourceHost,
          score: totalScore,
          phase: phaseLabel,
        },
      };
    } catch (e) {
      const rej =
        `[PRODUCT_SEARCH][candidate_rejected] phase=${phaseLabel} reason=download_failed message=${e?.message || String(e)} url=${candUrlSlice}`;
      console.log(rej);
      logger.info(rej);
    }
  }

  return { found: false, hadCandidateInspection };
}

async function runSourcePageOnlyImageSearch({
  uid,
  itemId,
  sourceUrl,
  seedImage,
  sku,
  brand,
  title,
  subCategoryKey,
}) {
  const expected = buildProductSearchExpectation({
    sourceUrl,
    brand,
    title,
    subCategoryKey,
    sku,
  });
  const pageCandidates = await collectPageGalleryCandidates(sourceUrl, {
    brand,
    title,
    subCategoryKey,
    sku,
  });
  let seedBuf = null;
  const seed = String(seedImage || "").trim();
  if (seed && isValidHttpUrl(seed)) {
    try {
      ({ buf: seedBuf } = await downloadProductImageBuffer(seed));
    } catch (_) {}
  }
  return tryEvaluateProductSearchCandidates({
    uid,
    itemId,
    seed,
    seedBuf,
    candidates: pageCandidates,
    phaseLabel: "source_page_only",
    expected,
  });
}

async function runProductImageWebSearch({
  uid,
  itemId,
  sourceUrl,
  seedImage,
  sku,
  brand,
  title,
  colors,
  subCategoryKey = "",
}) {
  logProductSearchSerperStartup();

  const resolvedSku =
    String(sku || "").trim() ||
    extractProductSkuFromText(`${title} ${brand}`, sourceUrl);

  const expected = buildProductSearchExpectation({
    sourceUrl,
    brand,
    title,
    subCategoryKey,
    sku: resolvedSku,
  });

  const skuLine = `[PRODUCT_SEARCH][sku] ${resolvedSku || "(empty)"}`;
  console.log(skuLine);
  logger.info(skuLine);

  logger.info("[PRODUCT_SEARCH][sku_meta]", { sku: resolvedSku || null });
  const searchStartMsg = `[PRODUCT_SEARCH][search_start] itemId=${itemId || "?"} sku=${
    resolvedSku || "(empty)"
  }`;
  console.log(searchStartMsg);
  logger.info(searchStartMsg);

  logger.info("[PRODUCT_SEARCH][status]", { phase: "searching" });

  const seed = String(seedImage || "").trim();
  const adidasFirst = isAdidasProductSourceUrl(sourceUrl);

  logger.info("[PRODUCT_SEARCH][seed_url]", { url: seed.slice(0, 280) });
  if (adidasFirst) {
    console.log("[PRODUCT_SEARCH][adidas_source_gallery_first]");
    logger.info("[PRODUCT_SEARCH][adidas_source_gallery_first]", {
      sourceUrl: sourceUrl.slice(0, 160),
    });
  }

  let seedBuf = null;
  if (seed && isValidHttpUrl(seed)) {
    try {
      ({ buf: seedBuf } = await downloadProductImageBuffer(seed));
    } catch (e) {
      logger.warn("[PRODUCT_SEARCH][seed_download_error]", {
        message: e?.message || String(e),
      });
    }
  }

  let hadCandidateInspection = false;

  const evaluatePageGallery = async () => {
    const pageCandidates = await collectPageGalleryCandidates(sourceUrl, {
      brand,
      title,
      subCategoryKey,
      sku: resolvedSku,
    });
    return tryEvaluateProductSearchCandidates({
      uid,
      itemId,
      seed,
      seedBuf,
      candidates: pageCandidates,
      phaseLabel: "page_gallery",
      expected,
    });
  };

  const evaluateSerper = async () => {
    if (!resolvedSku) return { found: false, hadCandidateInspection: false };
    const { candidates: serperCandidates } = await collectSerperImageCandidatesFirst({
      sku: resolvedSku,
      brand,
      title,
      subCategoryKey,
    });
    return tryEvaluateProductSearchCandidates({
      uid,
      itemId,
      seed,
      seedBuf,
      candidates: serperCandidates,
      phaseLabel: "serper_images",
      expected,
    });
  };

  if (adidasFirst) {
    const pageOutcome = await evaluatePageGallery();
    hadCandidateInspection =
      hadCandidateInspection || pageOutcome.hadCandidateInspection === true;
    if (pageOutcome.found) {
      logger.info("[PRODUCT_SEARCH][winner]", pageOutcome.winner || {});
      logger.info("[PRODUCT_SEARCH][status]", { phase: "found", via: "page_gallery" });
      return {
        found: true,
        productImageUrl: pageOutcome.productImageUrl,
        cleanImageUrl: pageOutcome.cleanImageUrl,
        sourceCandidateUrl: pageOutcome.sourceCandidateUrl,
        sku: resolvedSku,
        hadCandidateInspection,
      };
    }

    if (seed && isValidHttpUrl(seed)) {
      console.log("[PRODUCT_SEARCH][adidas_skip_serper_valid_seed]");
      logger.info("[PRODUCT_SEARCH][adidas_skip_serper_valid_seed]", {
        seed: seed.slice(0, 200),
      });
      return {
        found: false,
        sku: resolvedSku,
        hadCandidateInspection,
        skipSerperValidSeed: true,
      };
    }

    const serperOutcome = await evaluateSerper();
    hadCandidateInspection =
      hadCandidateInspection || serperOutcome.hadCandidateInspection === true;
    if (serperOutcome.found) {
      logger.info("[PRODUCT_SEARCH][winner]", serperOutcome.winner || {});
      logger.info("[PRODUCT_SEARCH][status]", { phase: "found", via: "serper_images" });
      return {
        found: true,
        productImageUrl: serperOutcome.productImageUrl,
        cleanImageUrl: serperOutcome.cleanImageUrl,
        sourceCandidateUrl: serperOutcome.sourceCandidateUrl,
        sku: resolvedSku,
        hadCandidateInspection,
      };
    }
    logger.info("[PRODUCT_SEARCH][serper_phase_complete]", {
      accepted: false,
      inspected: serperOutcome.hadCandidateInspection === true,
    });
  } else {
    if (resolvedSku) {
      const serperOutcome = await evaluateSerper();
      hadCandidateInspection =
        hadCandidateInspection || serperOutcome.hadCandidateInspection === true;
      if (serperOutcome.found) {
        logger.info("[PRODUCT_SEARCH][winner]", serperOutcome.winner || {});
        logger.info("[PRODUCT_SEARCH][status]", { phase: "found", via: "serper_images" });
        return {
          found: true,
          productImageUrl: serperOutcome.productImageUrl,
          cleanImageUrl: serperOutcome.cleanImageUrl,
          sourceCandidateUrl: serperOutcome.sourceCandidateUrl,
          sku: resolvedSku,
          hadCandidateInspection,
        };
      }
      logger.info("[PRODUCT_SEARCH][serper_phase_complete]", {
        accepted: false,
        inspected: serperOutcome.hadCandidateInspection === true,
      });
    }

    const pageOutcome = await evaluatePageGallery();
    hadCandidateInspection =
      hadCandidateInspection || pageOutcome.hadCandidateInspection === true;
    if (pageOutcome.found) {
      logger.info("[PRODUCT_SEARCH][winner]", pageOutcome.winner || {});
      logger.info("[PRODUCT_SEARCH][status]", { phase: "found", via: "page_gallery" });
      return {
        found: true,
        productImageUrl: pageOutcome.productImageUrl,
        cleanImageUrl: pageOutcome.cleanImageUrl,
        sourceCandidateUrl: pageOutcome.sourceCandidateUrl,
        sku: resolvedSku,
        hadCandidateInspection,
      };
    }
  }

  logger.info("[PRODUCT_SEARCH][true_packshot_found]", { value: false });
  logger.info("[PRODUCT_SEARCH][status]", { phase: "no_good_match" });
  return {
    found: false,
    sku: resolvedSku,
    hadCandidateInspection,
  };
}

// ---------------------------------------------------------------------------
// Product-link image: person detect + rembg + e-shop product photo (reuse)
// ---------------------------------------------------------------------------
const PERSON_IMAGE_KEYWORDS = [
  "model",
  "athlete",
  "worn",
  "look",
  "lookbook",
  "lifestyle",
  "onbody",
  "on-body",
  "editorial",
  "campaign",
  "styling",
  "outfit",
];

const PERSON_CONFIDENCE_THRESHOLD = 0.85;

const RETAILERS_LIKELY_ON_BODY = [
  "nike.com",
  "nike.",
  "zara.com",
  "zara.",
  "adidas.com",
  "adidas.",
  "hm.com",
  "asos.",
  "uniqlo.",
  "puma.com",
];

async function buildProductPhotoBuffer(
  cutoutBuffer,
  opts = {}
) {
  const ITEM_MAX = opts.itemMax ?? 880;
  const BG = opts.bg ?? "#FFFFFF";
  const SHADOW_DY = opts.shadowDy ?? 22;
  const SHADOW_BLUR = opts.shadowBlur ?? 16;
  const SHADOW_OPACITY = opts.shadowOpacity ?? 0.2;
  const PAD = opts.pad ?? 40;

  const trimmed = await sharp(cutoutBuffer)
    .ensureAlpha()
    .trim({ threshold: 12 })
    .png()
    .toBuffer();

  const resizedItem = await sharp(trimmed)
    .resize(ITEM_MAX, ITEM_MAX, { fit: "inside" })
    .png()
    .toBuffer({ resolveWithObject: true });

  const rw = resizedItem.info.width || 1;
  const rh = resizedItem.info.height || 1;
  const CANVAS = Math.min(1024, Math.max(rw, rh) + PAD * 2);
  const x = Math.floor((CANVAS - rw) / 2);
  const y = Math.floor((CANVAS - rh) / 2);

  const b64 = resizedItem.data.toString("base64");

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
    width="${rw}"
    height="${rh}"
    filter="url(#ds)"
  />
</svg>`.trim();

  return sharp(Buffer.from(svg)).png({ compressionLevel: 9 }).toBuffer();
}

/** Wardrobe tile pipeline after Serper picks a clean ecommerce image. */
async function finalizeSerperSelectedWardrobeImage({
  uid,
  itemId,
  imageUrl,
  title = "",
  brand = "",
}) {
  console.log("[PRODUCT_SEARCH][selected_clean_image_needs_cleanup]");
  logger.info("[PRODUCT_SEARCH][selected_clean_image_needs_cleanup]", {
    itemId,
    url: String(imageUrl || "").slice(0, 240),
  });

  const { buf } = await downloadProductImageBuffer(imageUrl);
  const garmentHint = inferGarmentRegionHint(`${title} ${brand}`);
  let productBuffer = buf;
  let cutoutBuffer = null;

  try {
    const visual = await analyzeVisualPersonHeuristics(buf);
    const hasModel = productSearchCandidateHasModel(visual);
    const whiteBg = visual.whiteBackgroundRatio >= 0.3;
    const { buf: rembgInput, contentType } = await resizeImageBufferForRembg(buf);

    if (hasModel || whiteBg) {
      try {
        cutoutBuffer = await removeBackgroundWithRetry({
          buf: rembgInput,
          contentType,
        });
        productBuffer = await buildProductPhotoBuffer(cutoutBuffer);
      } catch (rembgErr) {
        logger.warn("[PRODUCT_SEARCH][serper_rembg_fallback]", {
          message: rembgErr?.message || String(rembgErr),
        });
        productBuffer = await buildProductPhotoBuffer(rembgInput);
      }
    } else {
      productBuffer = await buildProductPhotoBuffer(rembgInput);
    }
  } catch (layoutErr) {
    logger.warn("[PRODUCT_SEARCH][serper_layout_fallback]", {
      message: layoutErr?.message || String(layoutErr),
      garmentHint,
    });
    try {
      productBuffer = await buildProductPhotoBuffer(buf);
    } catch (_) {
      productBuffer = buf;
    }
  }

  const productImageUrl = await uploadProductLinkStagingImage(uid, productBuffer, {
    itemId,
    suffix: "product",
  });

  let cleanImageUrl = productImageUrl;
  let cutoutImageUrl = productImageUrl;
  if (cutoutBuffer) {
    try {
      cleanImageUrl = await uploadProductLinkStagingImage(uid, cutoutBuffer, {
        itemId,
        suffix: "cutout",
      });
      cutoutImageUrl = cleanImageUrl;
    } catch (_) {}
  }

  console.log("[PRODUCT_SEARCH][cleanup_after_serper_done]");
  logger.info("[PRODUCT_SEARCH][cleanup_after_serper_done]", {
    itemId,
    productImageUrl: productImageUrl.slice(0, 240),
    cleanImageUrl: cleanImageUrl.slice(0, 240),
  });

  return { productImageUrl, cleanImageUrl, cutoutImageUrl };
}

function imageMetadataSuggestsPerson(imageUrl, extraText = "") {
  const blob = `${imageUrl} ${extraText}`.toLowerCase();
  return PERSON_IMAGE_KEYWORDS.some((k) => blob.includes(k));
}

function retailerLikelyUsesModelShots(hostname) {
  const h = String(hostname || "").toLowerCase();
  return RETAILERS_LIKELY_ON_BODY.some((r) => h.includes(r));
}

function shouldRunPersonDetection(imageUrl, hostname, extraText = "") {
  if (!imageUrl || !isValidHttpUrl(imageUrl)) return false;
  if (imageMetadataSuggestsPerson(imageUrl, extraText)) return true;
  if (retailerLikelyUsesModelShots(hostname)) return true;
  return false;
}

function isSkinTonePixel(r, g, b) {
  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  return (
    r > 95 &&
    g > 40 &&
    b > 20 &&
    max - min > 15 &&
    Math.abs(r - g) > 15 &&
    r > g &&
    r > b
  );
}

function parseVisionTrueFalse(text) {
  const raw = String(text || "").trim().toLowerCase();
  if (raw === "true" || raw === "yes") return true;
  if (raw === "false" || raw === "no") return false;
  const parsed = extractFirstJsonObjectGlobal(text);
  if (parsed && typeof parsed === "object") {
    if (parsed.person === true || parsed.contains_person === true) return true;
    if (parsed.person === false || parsed.contains_person === false) return false;
  }
  const wordTrue = /\btrue\b/.test(raw);
  const wordFalse = /\bfalse\b/.test(raw);
  if (wordTrue && !wordFalse) return true;
  if (wordFalse && !wordTrue) return false;
  return null;
}

async function analyzeImageDimensionsForPerson(buf) {
  const meta = await sharp(buf).metadata();
  const width = meta.width || 0;
  const height = meta.height || 0;
  if (!width || !height) {
    return {
      portraitLike: false,
      substantial: false,
      notFlatPackshot: false,
    };
  }
  const portraitLike = height >= width * 1.05;
  const substantial = height >= 320 && width >= 200;
  const aspect = height / width;
  const notFlatPackshot = portraitLike || aspect > 0.75;
  return { portraitLike, substantial, notFlatPackshot, width, height };
}

async function analyzeVisualPersonHeuristics(buf) {
  const { data, info } = await sharp(buf)
    .resize(160, 160, { fit: "inside" })
    .removeAlpha()
    .raw()
    .toBuffer({ resolveWithObject: true });

  const w = info.width || 1;
  const h = info.height || 1;
  const pixels = w * h;
  let skinPixels = 0;
  let skinUpper = 0;
  let upperPixels = 0;
  let skinFace = 0;
  let facePixels = 0;
  let skinCenter = 0;
  let centerPixels = 0;
  let skinMid = 0;
  let midPixels = 0;
  let skinLower = 0;
  let lowerPixels = 0;
  let skinBandUpper = 0;
  let bandUpperPx = 0;
  let skinBandMid = 0;
  let bandMidPx = 0;
  let skinBandLower = 0;
  let bandLowerPx = 0;
  let whitePixels = 0;
  let productPixels = 0;
  let centerProduct = 0;
  let centerZone = 0;
  let shoeDark = 0;
  let shoeZonePx = 0;
  let varianceSum = 0;

  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const i = (y * w + x) * 3;
      const r = data[i];
      const g = data[i + 1];
      const b = data[i + 2];
      const lum = 0.299 * r + 0.587 * g + 0.114 * b;
      varianceSum += Math.abs(lum - 128);

      const isWhiteBg = r > 238 && g > 238 && b > 238;
      const isLightBg = lum > 225 && Math.max(r, g, b) - Math.min(r, g, b) < 28;
      if (isWhiteBg) whitePixels++;

      const inFace = y < h * 0.26;
      const inCenter =
        y >= h * 0.22 && y < h * 0.72 && x >= w * 0.18 && x < w * 0.82;
      const inMid = y >= h * 0.18 && y < h * 0.88;
      const inLower = y >= h * 0.62;
      const inShoeZone = y >= h * 0.76;
      const inCenterZone =
        y >= h * 0.2 && y < h * 0.8 && x >= w * 0.2 && x < w * 0.8;
      const inBandUpper = y < h * 0.33;
      const inBandMid = y >= h * 0.33 && y < h * 0.66;
      const inBandLower = y >= h * 0.66;

      if (inFace) facePixels++;
      if (inCenter) centerPixels++;
      if (inMid) midPixels++;
      if (inLower) lowerPixels++;
      if (y < h * 0.45) upperPixels++;
      if (inBandUpper) bandUpperPx++;
      if (inBandMid) bandMidPx++;
      if (inBandLower) bandLowerPx++;
      if (inShoeZone) shoeZonePx++;
      if (inCenterZone) centerZone++;

      if (!isWhiteBg && !isLightBg) productPixels++;
      if (inCenterZone && !isWhiteBg && !isLightBg) centerProduct++;

      const isSkin = isSkinTonePixel(r, g, b);
      if (isSkin) {
        skinPixels++;
        if (y < h * 0.45) skinUpper++;
        if (inFace) skinFace++;
        if (inCenter) skinCenter++;
        if (inMid) skinMid++;
        if (inLower) skinLower++;
        if (inBandUpper) skinBandUpper++;
        if (inBandMid) skinBandMid++;
        if (inBandLower) skinBandLower++;
      } else if (inShoeZone && lum < 95 && !isLightBg) {
        shoeDark++;
      }
    }
  }

  const skinToneRatio = skinPixels / pixels;
  const skinUpperRatio = skinUpper / Math.max(upperPixels, 1);
  const skinInUpperRegion = skinUpperRatio >= 0.05;
  const skinFaceRatio = skinFace / Math.max(facePixels, 1);
  const skinCenterRatio = skinCenter / Math.max(centerPixels, 1);
  const skinMidRatio = skinMid / Math.max(midPixels, 1);
  const skinLowerRatio = skinLower / Math.max(lowerPixels, 1);
  const skinBandUpperRatio = skinBandUpper / Math.max(bandUpperPx, 1);
  const skinBandMidRatio = skinBandMid / Math.max(bandMidPx, 1);
  const skinBandLowerRatio = skinBandLower / Math.max(bandLowerPx, 1);
  const shoeZoneSignal = shoeDark / Math.max(shoeZonePx, 1);
  const whiteBackgroundRatio = whitePixels / pixels;
  const productFillRatio = productPixels / pixels;
  const centeredProductRatio = centerProduct / Math.max(centerZone, 1);
  const colorVarianceHigh = varianceSum / pixels > 28;
  const limbLikeEdges = skinToneRatio >= 0.03 && colorVarianceHigh;

  let distributedSkinBands = 0;
  if (skinBandUpperRatio >= 0.02) distributedSkinBands++;
  if (skinBandMidRatio >= 0.02) distributedSkinBands++;
  if (skinBandLowerRatio >= 0.02) distributedSkinBands++;

  const fullStandingModel =
    distributedSkinBands >= 2 &&
    (skinLowerRatio >= 0.018 || shoeZoneSignal >= 0.07) &&
    skinToneRatio >= 0.012;

  const ecommerceProductShot =
    productFillRatio >= PRODUCT_SEARCH_ECOMMERCE_MIN_FILL &&
    centeredProductRatio >= PRODUCT_SEARCH_ECOMMERCE_MIN_CENTER &&
    whiteBackgroundRatio >= PRODUCT_SEARCH_ECOMMERCE_MIN_WHITE_BG;

  const isolatedProduct =
    productFillRatio >= 0.2 &&
    productFillRatio <= 0.82 &&
    centeredProductRatio >= 0.48 &&
    (skinToneRatio < 0.012 || ecommerceProductShot) &&
    skinFaceRatio < 0.08 &&
    !fullStandingModel;

  return {
    skinToneRatio,
    skinUpperRatio,
    skinInUpperRegion,
    skinFaceRatio,
    skinCenterRatio,
    skinMidRatio,
    skinLowerRatio,
    skinBandUpperRatio,
    skinBandMidRatio,
    skinBandLowerRatio,
    shoeZoneSignal,
    distributedSkinBands,
    fullStandingModel,
    ecommerceProductShot,
    productFillRatio,
    centeredProductRatio,
    isolatedProduct,
    whiteBackgroundRatio,
    colorVarianceHigh,
    limbLikeEdges,
  };
}

function isLikelyFlatPackshot(visual) {
  return (
    visual.skinToneRatio < 0.022 &&
    (visual.skinFaceRatio == null || visual.skinFaceRatio < 0.04) &&
    (visual.skinCenterRatio == null || visual.skinCenterRatio < 0.035) &&
    visual.whiteBackgroundRatio > 0.52 &&
    !visual.skinInUpperRegion
  );
}

/**
 * Multi-step person detection for product-link cleanup.
 * Returns confidence that a visible model/person is present (0–1).
 */
async function assessPersonInProductImage({
  imageUrl,
  apiKey,
  hostname = "",
  pageTitle = "",
  productUrl = "",
  skipVision = false,
  imageBuffer = null,
}) {
  const metadataText = `${pageTitle} ${productUrl}`.trim();
  const reasons = [];
  let personConfidence = 0;
  let visionAnswer = null;

  // 1) Lightweight vision prompt (skipped in fast cleanup — no OpenAI)
  if (!skipVision && apiKey && imageUrl && isValidHttpUrl(imageUrl)) {
    const prompt =
      "Does image contain a visible human/model wearing clothing?\n" +
      "Answer only true or false.";

    try {
      const response = await fetch("https://api.openai.com/v1/chat/completions", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${apiKey}`,
        },
        body: JSON.stringify({
          model: "gpt-4o-mini",
          temperature: 0,
          max_tokens: 8,
          messages: [
            {
              role: "user",
              content: [
                { type: "text", text: prompt },
                {
                  type: "image_url",
                  image_url: { url: imageUrl, detail: "low" },
                },
              ],
            },
          ],
        }),
      });

      if (response.ok) {
        const aiJson = await response.json();
        const text = aiJson?.choices?.[0]?.message?.content || "";
        visionAnswer = parseVisionTrueFalse(text);
        if (visionAnswer === true) {
          personConfidence = Math.max(personConfidence, 0.93);
          reasons.push("vision_true");
        } else if (visionAnswer === false) {
          personConfidence = Math.max(personConfidence, 0.38);
          reasons.push("vision_false");
        } else {
          personConfidence = Math.max(personConfidence, 0.58);
          reasons.push("vision_uncertain");
        }
      } else {
        reasons.push("vision_http_error");
        personConfidence = Math.max(personConfidence, 0.58);
      }
    } catch (e) {
      reasons.push("vision_error");
      personConfidence = Math.max(personConfidence, 0.58);
      logger.warn("[PRODUCT_IMAGE][person_detect_error]", {
        message: e?.message || String(e),
      });
    }
  } else {
    reasons.push(skipVision ? "vision_skipped_fast" : "vision_skipped");
    personConfidence = Math.max(personConfidence, 0.58);
  }

  // 3) URL / metadata signals (independent of AI page metadata)
  if (imageMetadataSuggestsPerson(imageUrl, metadataText)) {
    personConfidence = Math.max(personConfidence, 0.78);
    reasons.push("url_metadata");
  }
  if (retailerLikelyUsesModelShots(hostname) || retailerLikelyUsesModelShots(productUrl)) {
    personConfidence = Math.max(personConfidence, 0.82);
    reasons.push("retailer_model_shot");
  }

  let visual = null;
  let dimensions = null;

  // 2) Image dimensions + 4) visual heuristics
  try {
    let buf = imageBuffer;
    if (!buf) {
      const downloaded = await downloadProductImageBuffer(imageUrl);
      buf = downloaded.buf;
    }
    dimensions = await analyzeImageDimensionsForPerson(buf);
    if (dimensions.portraitLike && dimensions.substantial) {
      personConfidence = Math.max(personConfidence, 0.76);
      reasons.push("portrait_dimensions");
    }
    if (dimensions.notFlatPackshot) {
      personConfidence = Math.max(personConfidence, 0.72);
      reasons.push("non_packshot_layout");
    }

    visual = await analyzeVisualPersonHeuristics(buf);
    if (visual.skinToneRatio >= 0.06) {
      personConfidence = Math.max(personConfidence, 0.87);
      reasons.push("skin_tones");
    }
    if (visual.skinInUpperRegion) {
      personConfidence = Math.max(personConfidence, 0.89);
      reasons.push("upper_body_skin");
    }
    if (visual.limbLikeEdges) {
      personConfidence = Math.max(personConfidence, 0.85);
      reasons.push("limb_heuristic");
    }
    if (visual.colorVarianceHigh && visual.skinToneRatio >= 0.04) {
      personConfidence = Math.max(personConfidence, 0.84);
      reasons.push("face_region_heuristic");
    }
  } catch (e) {
    reasons.push("image_heuristic_skipped");
    logger.warn("[PRODUCT_IMAGE][person_heuristic_error]", {
      message: e?.message || String(e),
    });
  }

  // 5) Decide + safety fallback — prefer rembg over skipping model shots
  const rawConfidence = personConfidence;
  let containsPerson = true;

  const retailerModelShop =
    retailerLikelyUsesModelShots(hostname) ||
    retailerLikelyUsesModelShots(productUrl);

  const packshotVisionFalse = skipVision ? false : visionAnswer === false;
  if (
    !retailerModelShop &&
    visual &&
    isLikelyFlatPackshot(visual) &&
    packshotVisionFalse &&
    rawConfidence < PERSON_CONFIDENCE_THRESHOLD
  ) {
    containsPerson = false;
    personConfidence = 0.2;
    reasons.push("flat_packshot_no_person");
  } else if (rawConfidence < PERSON_CONFIDENCE_THRESHOLD) {
    containsPerson = true;
    reasons.push("safety_fallback");
    personConfidence = PERSON_CONFIDENCE_THRESHOLD;
  } else {
    containsPerson = true;
  }

  const reason = reasons.join("+") || "unknown";
  logger.info("[PRODUCT_IMAGE][person_confidence]", {
    confidence: Number(personConfidence.toFixed(3)),
    visionAnswer,
    hostname: String(hostname || "").slice(0, 80),
  });
  logger.info("[PRODUCT_IMAGE][person_reason]", { reason });

  return {
    containsPerson,
    personConfidence,
    personReason: reason,
    visionAnswer,
  };
}

async function downloadProductImageBuffer(imageUrl) {
  const res = await fetch(imageUrl, {
    redirect: "follow",
    headers: {
      "User-Agent":
        "Mozilla/5.0 (compatible; OutfitOfTheDayBot/1.0; +https://outfitoftheday.app)",
      Accept: "image/*,*/*;q=0.8",
    },
  });
  if (!res.ok) {
    const err = new Error(`image download failed ${res.status}`);
    err.status = res.status;
    throw err;
  }
  const buf = Buffer.from(await res.arrayBuffer());
  const contentType = String(res.headers.get("content-type") || "image/jpeg");
  return { buf, contentType };
}

const PREPARE_REMBG_MAX_WIDTH = 1200;

/** Resize/compress before rembg to cut latency and payload size. */
async function resizeImageBufferForRembg(buf) {
  const meta = await sharp(buf).metadata();
  const width = meta.width || 0;
  const pipeline = sharp(buf);
  const needsResize = width > PREPARE_REMBG_MAX_WIDTH;
  const out = needsResize
    ? pipeline.resize(PREPARE_REMBG_MAX_WIDTH, null, {
        fit: "inside",
        withoutEnlargement: true,
      })
    : pipeline;
  const resized = await out.jpeg({ quality: 85, mozjpeg: true }).toBuffer();
  return { buf: resized, contentType: "image/jpeg", width, outWidth: needsResize ? PREPARE_REMBG_MAX_WIDTH : width };
}

/**
 * Product-link cleanup: prefer packshot gallery image; else crop garment region
 * before rembg and validate person/face was removed.
 */
async function runPrepareProductLinkImagePipeline({
  uid,
  itemId,
  url,
  imageUrl,
  hostname = "",
  pageTitle = "",
  apiKey = null,
}) {
  const t0 = Date.now();
  const elapsed = () => Date.now() - t0;
  const logPrep = (step, extra = {}) =>
    logger.info(`[PREPARE_PRODUCT_IMAGE]${step}`, { ...extra, elapsedMs: elapsed() });

  const originalImageUrl = String(imageUrl || "").trim();
  const metadataText = `${pageTitle} ${url}`.trim();
  const host = String(hostname || url || "").toLowerCase();
  const garmentHint = inferGarmentRegionHint(`${pageTitle} ${url}`);

  try {
    logPrep("[start]", {
      imageUrl: originalImageUrl.slice(0, 160),
      hostname: host.slice(0, 80),
      garmentHint,
    });

    if (!originalImageUrl || !isValidHttpUrl(originalImageUrl)) {
      throw new Error("invalid imageUrl");
    }

    if (!shouldRunPersonDetection(originalImageUrl, host, metadataText)) {
      logPrep("[total_ms]", { ms: elapsed(), skipped: true });
      logPrep("[cleanup_succeeded]", { ok: true, path: "no_cleanup_needed" });
      return {
        containsPerson: false,
        needsCleanup: false,
        cleanImageUrl: null,
        productImageUrl: originalImageUrl,
        originalImageUrl,
        analysisImageUrl: originalImageUrl,
        cleanupSkipped: true,
        cleanupSucceeded: true,
        failureReason: null,
      };
    }

    let scoredCandidates = [
      {
        url: originalImageUrl,
        source: "client",
        index: 0,
        cleanupScore: scoreCleanupImageCandidate(originalImageUrl, {}),
      },
    ];

    if (url && url.includes("://")) {
      try {
        const pageHtml = await fetchProductPageHtml(url);
        const meta = extractStrategy1Metadata(pageHtml);
        const jsonLd = extractStrategy2JsonLd(pageHtml);
        if (!pageTitle) pageTitle = meta.title || jsonLd.name || "";
        const signals = {
          slug: { hostname: host },
          metadata: { ...meta, raw: meta.raw || meta },
          jsonLd,
        };
        scoredCandidates = buildProductImageCandidatesList(
          url,
          pageHtml,
          signals,
          [{ url: originalImageUrl, source: "client", index: 0 }]
        ).sort((a, b) => b.cleanupScore - a.cleanupScore);
      } catch (fetchErr) {
        logger.warn("[PREPARE_PRODUCT_IMAGE][page_fetch_failed]", {
          message: fetchErr?.message || String(fetchErr),
        });
      }
    }

    logPrep("[candidate_count]", { count: scoredCandidates.length });

    const packshot = await findPackshotFromCandidates(scoredCandidates);
    if (packshot) {
      logPrep("[selected_candidate_reason]", { reason: packshot.reason });
      logPrep("[person_detected]", { person: false, path: "packshot" });

      let packBuf = packshot.buf;
      if (!packBuf) {
        logPrep("[download_start]", { source: "packshot" });
        const dl = await downloadProductImageBuffer(packshot.url);
        packBuf = dl.buf;
        logPrep("[download_done]", { bytes: packBuf.length });
      }

      let productBuffer = packBuf;
      try {
        const { buf: resized } = await resizeImageBufferForRembg(packBuf);
        productBuffer = await buildProductPhotoBuffer(resized);
      } catch (_) {
        try {
          productBuffer = await buildProductPhotoBuffer(packBuf);
        } catch (__) {
          productBuffer = packBuf;
        }
      }

      logPrep("[upload_start]");
      const stagedUrl = await uploadProductLinkStagingImage(uid, productBuffer, { itemId });
      logPrep("[upload_done]", { url: stagedUrl.slice(0, 160) });
      logPrep("[cleanup_succeeded]", { ok: true, path: "packshot" });
      logPrep("[total_ms]", { ms: elapsed() });

      return {
        containsPerson: false,
        needsCleanup: true,
        cleanImageUrl: stagedUrl,
        productImageUrl: stagedUrl,
        originalImageUrl,
        analysisImageUrl: stagedUrl,
        cleanupFailed: false,
        cleanupSucceeded: true,
        failureReason: null,
      };
    }

    logPrep("[selected_candidate_reason]", {
      reason: "model_image_garment_crop",
      url: originalImageUrl.slice(0, 160),
    });

    logPrep("[download_start]");
    const { buf } = await downloadProductImageBuffer(originalImageUrl);
    logPrep("[download_done]", { bytes: buf.length });

    const personAssessment = await assessPersonInProductImage({
      imageUrl: originalImageUrl,
      apiKey: null,
      hostname: host,
      pageTitle,
      productUrl: url,
      skipVision: true,
      imageBuffer: buf,
    });

    logPrep("[person_detected]", {
      person: personAssessment.containsPerson === true,
      reason: personAssessment.personReason,
    });

    if (!personAssessment.containsPerson) {
      logPrep("[cleanup_succeeded]", { ok: true, path: "no_person_in_image" });
      logPrep("[total_ms]", { ms: elapsed() });
      return {
        containsPerson: false,
        needsCleanup: false,
        cleanImageUrl: null,
        productImageUrl: originalImageUrl,
        originalImageUrl,
        analysisImageUrl: originalImageUrl,
        cleanupSkipped: true,
        cleanupSucceeded: true,
        failureReason: null,
      };
    }

    logPrep("[garment_crop_start]", { garmentHint });
    let cropBox =
      (await requestGarmentCropBoxFromVision({
        imageUrl: originalImageUrl,
        apiKey,
        garmentHint,
        productTitle: pageTitle,
      })) || heuristicGarmentCropBox(garmentHint);
    logPrep("[garment_crop_box]", cropBox);

    const croppedBuf = await cropImageBufferNormalized(buf, cropBox);
    const { buf: rembgInput, contentType: rembgContentType } =
      await resizeImageBufferForRembg(croppedBuf);

    logPrep("[rembg_after_crop_start]", { inputBytes: rembgInput.length });
    const cleanBuffer = await removeBackgroundWithRetry({
      buf: rembgInput,
      contentType: rembgContentType,
    });
    logPrep("[rembg_done]", { bytes: cleanBuffer.length });

    const personRemnants = await cutoutContainsPersonRemnants(cleanBuffer);
    logPrep("[skin_or_face_removed]", { removed: !personRemnants });

    if (personRemnants) {
      logPrep("[failure_reason]", { reason: "person_not_removed" });
      logPrep("[cleanup_succeeded]", { ok: false });
      logPrep("[total_ms]", { ms: elapsed() });
      return buildCleanupFailureResult(originalImageUrl, "person_not_removed");
    }

    let productBuffer = cleanBuffer;
    try {
      productBuffer = await buildProductPhotoBuffer(cleanBuffer);
    } catch (cropErr) {
      logger.warn("[PREPARE_PRODUCT_IMAGE][crop_failed]", {
        message: cropErr?.message || String(cropErr),
      });
    }

    logPrep("[upload_start]");
    const stagedUrl = await uploadProductLinkStagingImage(uid, productBuffer, { itemId });
    logPrep("[upload_done]", { url: stagedUrl.slice(0, 160) });
    logPrep("[cleanup_succeeded]", { ok: true, path: "garment_crop_rembg" });
    logPrep("[total_ms]", { ms: elapsed() });

    return {
      containsPerson: true,
      needsCleanup: true,
      cleanImageUrl: stagedUrl,
      productImageUrl: stagedUrl,
      originalImageUrl,
      analysisImageUrl: stagedUrl,
      cleanupFailed: false,
      cleanupSucceeded: true,
      failureReason: null,
    };
  } catch (e) {
    logPrep("[error]", {
      message: e?.message || String(e),
      status: e?.status || null,
    });
    logPrep("[failure_reason]", { reason: "pipeline_error" });
    logPrep("[cleanup_succeeded]", { ok: false });
    logPrep("[total_ms]", { ms: elapsed() });
    return buildCleanupFailureResult(
      originalImageUrl,
      e?.message || "pipeline_error"
    );
  }
}

function buildStorageDownloadUrl(bucketName, path, token) {
  const encoded = encodeURIComponent(path);
  return `https://firebasestorage.googleapis.com/v0/b/${bucketName}/o/${encoded}?alt=media&token=${token}`;
}

/**
 * Upload product-link image to wardrobe_product/ with a Firebase download token
 * (same pattern as wardrobe_clean / wardrobe_product storage triggers).
 */
async function uploadProductLinkStagingImage(uid, buffer, opts = {}) {
  const bucket = storage.bucket();
  const bucketName = bucket.name;
  const id = crypto.randomUUID();
  const itemPart = opts.itemId ? `${String(opts.itemId)}_` : "";
  const suffixPart = opts.suffix ? `${String(opts.suffix)}_` : "";
  const path = `wardrobe_product/${uid}/product_link_${itemPart}${suffixPart}${id}.png`;
  const token = crypto.randomUUID();
  const file = bucket.file(path);

  await file.save(buffer, {
    contentType: "image/png",
    metadata: {
      metadata: {
        firebaseStorageDownloadTokens: token,
      },
    },
  });

  await file.setMetadata({
    metadata: {
      firebaseStorageDownloadTokens: token,
    },
  });

  const downloadUrl = buildStorageDownloadUrl(bucketName, path, token);
  if (!downloadUrl.includes("token=")) {
    throw new Error("uploadProductLinkStagingImage: missing download token in URL");
  }
  logger.info("[WARDROBE_IMAGE_PROCESS][download_url]", {
    url: downloadUrl.slice(0, 240),
    path,
  });
  return downloadUrl;
}

/**
 * Download product image, detect model/person shots, isolate clothing via rembg when needed.
 * Returns URLs for AI analysis and form display.
 */
async function prepareProductImageForAnalysis({
  uid,
  imageUrl,
  hostname,
  apiKey,
  pageTitle = "",
  productUrl = "",
}) {
  const originalImageUrl = String(imageUrl || "").trim();
  if (!originalImageUrl || !isValidHttpUrl(originalImageUrl)) {
    return {
      analysisImageUrl: "",
      productImageUrl: "",
      originalImageUrl: "",
      personDetected: false,
    };
  }

  const metadataText = `${pageTitle} ${productUrl}`.trim();
  const runDetect = shouldRunPersonDetection(
    originalImageUrl,
    hostname || productUrl,
    metadataText
  );
  if (!runDetect) {
    logger.info("[PRODUCT_IMAGE][analysis_image]", {
      source: "original",
      reason: "no_person_check_needed",
    });
    return {
      analysisImageUrl: originalImageUrl,
      productImageUrl: originalImageUrl,
      originalImageUrl,
      personDetected: false,
    };
  }

  const personAssessment = await assessPersonInProductImage({
    imageUrl: originalImageUrl,
    apiKey,
    hostname,
    pageTitle,
    productUrl,
  });
  const personDetected = personAssessment.containsPerson === true;

  logger.info("[PRODUCT_IMAGE][contains_person]", { person: personDetected });

  if (!personDetected) {
    logger.info("[PRODUCT_IMAGE][analysis_image]", {
      source: "original",
      reason: "no_person",
    });
    return {
      analysisImageUrl: originalImageUrl,
      productImageUrl: originalImageUrl,
      originalImageUrl,
      personDetected: false,
      personConfidence: personAssessment.personConfidence,
      personReason: personAssessment.personReason,
    };
  }

  try {
    logger.info("[PRODUCT_IMAGE][rembg_start]", {
      url: originalImageUrl.slice(0, 160),
    });
    const { buf } = await downloadProductImageBuffer(originalImageUrl);
    const { buf: rembgInput, contentType: rembgContentType } =
      await resizeImageBufferForRembg(buf);
    const cleanBuffer = await removeBackgroundWithRetry({
      buf: rembgInput,
      contentType: rembgContentType,
    });

    logger.info("[PRODUCT_IMAGE][crop_start]");
    let productBuffer = cleanBuffer;
    try {
      productBuffer = await buildProductPhotoBuffer(cleanBuffer);
      logger.info("[PRODUCT_IMAGE][clean_ready]");
    } catch (cropErr) {
      logger.warn("[PRODUCT_IMAGE][crop_failed]", {
        message: cropErr?.message || String(cropErr),
      });
    }

    const stagedUrl = await uploadProductLinkStagingImage(uid, productBuffer);
    logger.info("[PRODUCT_IMAGE][analysis_image]", {
      source: "cleaned",
      url: stagedUrl.slice(0, 200),
    });

    return {
      analysisImageUrl: stagedUrl,
      productImageUrl: stagedUrl,
      originalImageUrl,
      personDetected: true,
      personConfidence: personAssessment.personConfidence,
      personReason: personAssessment.personReason,
    };
  } catch (e) {
    logger.error("[PRODUCT_IMAGE][clean_failed]", {
      message: e?.message || String(e),
      status: e?.status || null,
    });
    return {
      analysisImageUrl: originalImageUrl,
      productImageUrl: originalImageUrl,
      originalImageUrl,
      personDetected: true,
      cleanFailed: true,
      personConfidence: personAssessment.personConfidence,
      personReason: personAssessment.personReason,
    };
  }
}

function extractJsonLdProductImages(product) {
  if (!product?.image) return [];
  const imgs = Array.isArray(product.image) ? product.image : [product.image];
  return imgs
    .map((img) =>
      typeof img === "string" ? img : String(img?.url || img?.contentUrl || "")
    )
    .filter((u) => u && isValidHttpUrl(u));
}

function extractAdidasAssetUrlsFromHtml(html) {
  const out = [];
  const seen = new Set();
  const blob = String(html || "");
  if (!blob) return out;

  const assetRe =
    /https?:\/\/assets\.adidas\.com\/[^"'\\\s<>]+\.(?:jpg|jpeg|png|webp)(?:\?[^"'\\\s<>]*)?/gi;
  let m;
  while ((m = assetRe.exec(blob))) {
    const u = String(m[0] || "").trim();
    if (!u || seen.has(u)) continue;
    seen.add(u);
    out.push(u);
  }

  const nextMatch = blob.match(
    /<script[^>]*id=["']__NEXT_DATA__["'][^>]*>([\s\S]*?)<\/script>/i
  );
  if (nextMatch && nextMatch[1]) {
    try {
      const json = JSON.parse(nextMatch[1]);
      const stack = [json];
      while (stack.length) {
        const node = stack.pop();
        if (!node || typeof node !== "object") continue;
        if (Array.isArray(node)) {
          for (const item of node) stack.push(item);
          continue;
        }
        for (const [k, v] of Object.entries(node)) {
          if (typeof v === "string" && v.includes("assets.adidas.com")) {
            const hits = v.match(assetRe) || [];
            for (const hit of hits) {
              const u = String(hit).trim();
              if (u && !seen.has(u)) {
                seen.add(u);
                out.push(u);
              }
            }
          } else if (v && typeof v === "object") {
            stack.push(v);
          }
        }
      }
    } catch (_) {}
  }

  return out;
}

async function probeAdidasSkuImageUrls(sku) {
  const s = String(sku || "")
    .trim()
    .toUpperCase()
    .replace(/\.HTML$/i, "");
  if (!s || s.length < 4) return [];

  const templates = [
    `https://assets.adidas.com/images/h_600,f_auto,q_auto,fl_lossy,c_fill,g_auto/${s}_21_model.jpg`,
    `https://assets.adidas.com/images/w_600,f_auto,q_auto,fl_lossy,c_fill,g_auto/${s}_01_standard.jpg`,
    `https://assets.adidas.com/images/w_600,f_auto,q_auto,fl_lossy,c_fill,g_auto/${s}_010_21_model.jpg`,
    `https://assets.adidas.com/images/w_600,f_auto,q_auto/${s}_21_model.jpg`,
  ];

  const ok = [];
  for (const url of templates) {
    try {
      const res = await fetch(url, {
        method: "HEAD",
        redirect: "follow",
        headers: {
          "User-Agent":
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
        },
      });
      const ct = String(res.headers.get("content-type") || "").toLowerCase();
      if (res.ok && ct.includes("image")) {
        ok.push(url);
      }
    } catch (_) {}
  }
  return ok;
}

function scoreAdidasSourceImageUrl(url, sku = "") {
  const u = String(url || "").toLowerCase();
  let score = scoreProductImageCandidate(url, { source: "gallery", isAdidas: true });
  if (u.includes("laydown_hover") || u.includes("01_laydown")) score += 60;
  else if (u.includes("laydown") || u.includes("hover")) score += 48;
  if (u.includes("plavecke_sortky")) score += 25;
  if (u.includes("_01_standard") || u.includes("standard")) score += 45;
  if (u.includes("packshot") || u.includes("flat")) score += 40;
  if (u.includes("_21_model") || u.includes("model")) score += 18;
  if (sku && u.includes(String(sku).toLowerCase())) score += 30;
  if (u.includes("lifestyle") || u.includes("lookbook")) score -= 40;
  return score;
}

function pickBestAdidasSourceSeedImage(candidates, sku = "") {
  const ranked = [...candidates]
    .filter((c) => c.url && isValidHttpUrl(c.url))
    .map((c) => ({
      ...c,
      score: scoreAdidasSourceImageUrl(c.url, sku) + (c.source === "og" ? 12 : 0),
    }))
    .sort((a, b) => b.score - a.score);
  return ranked[0] || null;
}

async function extractProductLinkSourcePage(url) {
  const sourceUrl = String(url || "").trim();
  const isAdidas = isAdidasProductSourceUrl(sourceUrl);
  const sku = extractProductSkuFromText("", sourceUrl);

  if (isAdidas) {
    console.log("[ADIDAS_SOURCE][fetch_start]", sourceUrl.slice(0, 200));
    logger.info("[ADIDAS_SOURCE][fetch_start]", { url: sourceUrl.slice(0, 200) });
  }

  const signals = await extractAllProductSignals(sourceUrl);
  let html = "";
  try {
    if (signals.fetchOk !== true) {
      html = await fetchProductPageHtml(sourceUrl);
    } else {
      html = await fetchProductPageHtml(sourceUrl).catch(() => "");
    }
  } catch (_) {
    html = "";
  }

  if (isAdidas) {
    const len = String(html || "").length;
    console.log("[ADIDAS_SOURCE][html_length]", len);
    logger.info("[ADIDAS_SOURCE][html_length]", { length: len });
  }

  const meta = signals.metadata?.raw || {};
  const ogImage = String(meta.ogImage || signals.metadata?.imageUrl || "").trim();
  const twitterImage = String(meta.twitterImage || "").trim();
  const jsonLdImages = extractJsonLdProductImages(signals.jsonLd?.product);

  if (isAdidas) {
    console.log("[ADIDAS_SOURCE][og_image]", ogImage.slice(0, 200));
    console.log("[ADIDAS_SOURCE][twitter_image]", twitterImage.slice(0, 200));
    console.log("[ADIDAS_SOURCE][jsonld_images_count]", jsonLdImages.length);
    logger.info("[ADIDAS_SOURCE][og_image]", { url: ogImage.slice(0, 200) });
    logger.info("[ADIDAS_SOURCE][twitter_image]", { url: twitterImage.slice(0, 200) });
    logger.info("[ADIDAS_SOURCE][jsonld_images_count]", { count: jsonLdImages.length });
  }

  const assetUrls = html ? extractAdidasAssetUrlsFromHtml(html) : [];
  if (isAdidas) {
    console.log("[ADIDAS_SOURCE][asset_images_count]", assetUrls.length);
    logger.info("[ADIDAS_SOURCE][asset_images_count]", { count: assetUrls.length });
  }

  const gallerySignals = {
    slug: signals.slug,
    metadata: { ...signals.metadata, raw: meta },
    jsonLd: signals.jsonLd,
  };
  const galleryList = html
    ? buildProductImageCandidatesList(sourceUrl, html, gallerySignals)
    : [];

  const candidates = [];
  const seen = new Set();
  const add = (imageUrl, source) => {
    const u = String(imageUrl || "").trim();
    if (!u || !isValidHttpUrl(u) || seen.has(u)) return;
    seen.add(u);
    candidates.push({ url: u, source });
  };

  if (ogImage) add(ogImage, "og");
  if (twitterImage) add(twitterImage, "twitter");
  for (const u of jsonLdImages) add(u, "jsonld");
  for (const c of galleryList) add(c.url, c.source || "gallery");
  for (const u of assetUrls) add(u, "adidas_asset");

  if (candidates.length === 0 && isAdidas && sku) {
    const probed = await probeAdidasSkuImageUrls(sku);
    for (const u of probed) add(u, "adidas_sku_probe");
  }

  const best = pickBestAdidasSourceSeedImage(candidates, sku);
  const seedImage = best?.url || "";

  if (seedImage) {
    console.log("[BACKEND_SOURCE_IMAGE][selected]", seedImage.slice(0, 280));
    logger.info("[BACKEND_SOURCE_IMAGE][selected]", { url: seedImage.slice(0, 280) });
  }

  if (isAdidas) {
    console.log("[ADIDAS_SOURCE][selected_seed_image]", seedImage.slice(0, 240));
    logger.info("[ADIDAS_SOURCE][selected_seed_image]", { url: seedImage.slice(0, 240) });
  }

  const heuristic = signals.heuristic || {};
  const slugBlob = [
    signals.slug?.joined || "",
    signals.slug?.path || "",
    signals.metadata?.title || "",
    signals.metadata?.description || "",
    signals.jsonLd?.name || "",
    signals.jsonLd?.description || "",
    seedImage,
  ].join(" ");
  const slugColors = matchSlugColors(slugBlob);
  const jdColors = Array.isArray(signals.jsonLd?.colors) ? signals.jsonLd.colors : [];
  const colors = [...new Set([...jdColors, ...slugColors])].filter(Boolean);

  return {
    sourceUrl,
    sku,
    seedImage,
    candidates,
    signals,
    heuristic,
    colors,
    fetchOk: signals.fetchOk === true || html.length > 1000,
  };
}

function extractGalleryImageUrls(html, pageUrl) {
  const out = [];
  const seen = new Set();

  function add(raw) {
    const u = String(raw || "").trim();
    if (!u || u.startsWith("data:")) return;
    try {
      const abs = u.startsWith("http") ? u : new URL(u, pageUrl).href;
      if (!isValidHttpUrl(abs)) return;
      if (seen.has(abs)) return;
      seen.add(abs);
      out.push(abs);
    } catch (_) {}
  }

  const imgRe =
    /<img[^>]+(?:src|data-src|data-original|data-lazy-src)=["']([^"']+)["'][^>]*>/gi;
  let m;
  while ((m = imgRe.exec(html))) {
    add(m[1]);
  }

  const srcsetRe = /srcset=["']([^"']+)["']/gi;
  while ((m = srcsetRe.exec(html))) {
    const parts = m[1].split(",");
    for (const part of parts) {
      const url = part.trim().split(/\s+/)[0];
      add(url);
    }
  }

  return out.slice(0, 24);
}

function buildProductImageCandidatesList(pageUrl, html, signals, extra = []) {
  const host = String(signals?.slug?.hostname || "").toLowerCase();
  const isAboutYou = host.includes("aboutyou");
  const isAdidas = host.includes("adidas");
  const candidates = [...extra];

  const og = signals?.metadata?.raw?.ogImage || signals?.metadata?.imageUrl || "";
  if (og) candidates.push({ url: og, source: "og", index: 0 });

  const twitter = signals?.metadata?.raw?.twitterImage || "";
  if (twitter && twitter !== og) {
    candidates.push({ url: twitter, source: "twitter", index: 0 });
  }

  const jsonLdImages = extractJsonLdProductImages(signals?.jsonLd?.product);
  jsonLdImages.forEach((url, index) => {
    candidates.push({ url, source: "jsonld", index });
  });
  if (
    signals?.jsonLd?.imageUrl &&
    !jsonLdImages.includes(signals.jsonLd.imageUrl)
  ) {
    candidates.push({
      url: signals.jsonLd.imageUrl,
      source: "jsonld",
      index: 0,
    });
  }

  if (html) {
    const gallery = extractGalleryImageUrls(html, pageUrl);
    gallery.forEach((url, index) => {
      candidates.push({ url, source: "gallery", index });
    });
  }

  const deduped = [];
  const seen = new Set();
  for (const c of candidates) {
    const key = String(c.url || "").trim();
    if (!key || seen.has(key)) continue;
    seen.add(key);
    deduped.push(c);
  }

  return deduped.map((c) => {
    const ctx = { ...c, isAboutYou, isAdidas };
    return {
      ...c,
      score: scoreProductImageCandidate(c.url, ctx),
      cleanupScore: scoreCleanupImageCandidate(c.url, ctx),
    };
  });
}

function pickBestProductImage(pageUrl, html, signals) {
  const host = String(signals?.slug?.hostname || "").toLowerCase();
  const isAboutYou = host.includes("aboutyou");
  const scored = buildProductImageCandidatesList(pageUrl, html, signals).sort(
    (a, b) => b.score - a.score
  );

  logger.info("[ADD_LINK_IMAGE_PICK][candidates]", {
    count: scored.length,
    top: scored.slice(0, 6).map((c) => ({
      source: c.source,
      index: c.index,
      score: c.score,
      url: String(c.url || "").slice(0, 160),
    })),
    isAboutYou,
  });

  const selected = scored[0]?.url || "";
  logger.info("[ADD_LINK_IMAGE_PICK][selected]", {
    url: selected ? String(selected).slice(0, 200) : "",
    source: scored[0]?.source || null,
    score: scored[0]?.score ?? null,
    isAboutYou,
  });

  return selected;
}

function extractStrategy2JsonLd(html) {
  const flat = flattenJsonLd(extractJsonLdBlocks(html));
  const product = pickProductJsonLd(flat);
  if (!product) {
    return { product: null, name: "", brand: "", description: "", imageUrl: "", category: "", colors: [], snippet: "" };
  }

  const colors = [];
  if (product.color) {
    const arr = Array.isArray(product.color) ? product.color : [product.color];
    for (const c of arr) colors.push(String(c));
  }
  if (Array.isArray(product.additionalProperty)) {
    for (const p of product.additionalProperty) {
      const n = String(p?.name || "").toLowerCase();
      if (n.includes("color") || n.includes("farba")) {
        colors.push(String(p?.value || ""));
      }
    }
  }

  const imageUrls = extractJsonLdProductImages(product);
  let imageUrl = imageUrls[0] || "";

  const brand =
    typeof product.brand === "string"
      ? product.brand
      : String(product.brand?.name || "");

  const category = String(product.category || product.productCategory || "");

  const fields = {
    product,
    name: String(product.name || ""),
    brand,
    description: String(product.description || "").slice(0, 1500),
    imageUrl,
    category,
    colors,
    snippet: JSON.stringify(product).slice(0, 3500),
  };
  return fields;
}

function tokenizeUrlSlug(url) {
  try {
    const u = new URL(url);
    const segments = u.pathname.split(/[\/\-_]+/).filter(Boolean);
    const tokens = [];
    const skip = new Set([
      "sk", "en", "de", "cs", "pl", "hu", "product", "p", "item", "dp",
      "shop", "catalog", "category", "html",
    ]);
    for (const seg of segments) {
      const lower = seg.toLowerCase();
      if (skip.has(lower)) continue;
      if (/^\d{4,}$/.test(lower)) continue;
      tokens.push(lower);
    }
    return {
      hostname: u.hostname.toLowerCase(),
      path: u.pathname,
      tokens,
      joined: tokens.join(" "),
    };
  } catch (_) {
    return { hostname: "", path: "", tokens: [], joined: "" };
  }
}

function extractStrategy3Slug(url) {
  const slug = tokenizeUrlSlug(url);
  return slug;
}

function extractStrategy4DomainBrand(url) {
  try {
    const host = new URL(url).hostname.toLowerCase();
    for (const row of DOMAIN_BRAND_MAP) {
      if (row.hosts.some((h) => host.includes(h))) {
        return row.brand;
      }
    }
  } catch (_) {}
  return "";
}

const ABOUTYOU_BRAND_SLUGS = [
  ["tommy-hilfiger", "Tommy Hilfiger"],
  ["nike-sportswear", "Nike"],
  ["adidas-originals", "Adidas"],
  ["adidas-sportswear", "Adidas"],
  ["calvin-klein-jeans", "Calvin Klein"],
  ["calvin-klein", "Calvin Klein"],
  ["jack-jones", "Jack & Jones"],
  ["guess", "Guess"],
  ["puma-essentials", "Puma"],
  ["new-balance", "New Balance"],
  ["under-armour", "Under Armour"],
  ["hugo-boss", "Hugo Boss"],
  ["ralph-lauren", "Ralph Lauren"],
  ["levis", "Levi's"],
  ["nike", "Nike"],
  ["adidas", "Adidas"],
  ["puma", "Puma"],
  ["reebok", "Reebok"],
  ["zara", "Zara"],
  ["mango", "Mango"],
  ["reserved", "Reserved"],
];

function extractAboutYouBrandSlug(url) {
  try {
    const u = new URL(url);
    if (!u.hostname.toLowerCase().includes("aboutyou")) return "";
    const segments = u.pathname.toLowerCase().split("/").filter(Boolean);
    const pIdx = segments.indexOf("p");
    if (pIdx < 0 || pIdx + 1 >= segments.length) return "";
    const slug = segments[pIdx + 1];
    for (const [key, label] of ABOUTYOU_BRAND_SLUGS) {
      if (slug === key || slug.startsWith(`${key}-`)) return label;
    }
    return slug
      .split("-")
      .filter(Boolean)
      .map((p) => p.charAt(0).toUpperCase() + p.slice(1))
      .join(" ");
  } catch (_) {
    return "";
  }
}

function matchSlugClothingRule(searchBlob) {
  const blob = String(searchBlob || "").toLowerCase();
  if (!blob) return null;

  for (const rule of SLUG_CLOTHING_RULES) {
    for (const key of rule.keys) {
      const k = key.toLowerCase();
      if (blob.includes(k)) {
        return { ...rule };
      }
    }
  }
  return null;
}

function matchSlugColors(searchBlob) {
  const blob = String(searchBlob || "").toLowerCase();
  const out = [];
  for (const rule of SLUG_COLOR_RULES) {
    for (const key of rule.keys) {
      if (blob.includes(key.toLowerCase()) && !out.includes(rule.color)) {
        out.push(rule.color);
      }
    }
  }
  return out;
}

const WARDROBE_COLOR_NAME_HEX = {
  čierna: "#000000",
  biela: "#FFFFFF",
  sivá: "#808080",
  modrá: "#0000FF",
  tmavomodrá: "#000080",
  svetlomodrá: "#87CEEB",
  zelená: "#008000",
  olivová: "#808000",
  khaki: "#C3B091",
  hnedá: "#8B4513",
  béžová: "#F5F5DC",
  červená: "#FF0000",
  bordová: "#800020",
  žltá: "#FFFF00",
  oranžová: "#FFA500",
  ružová: "#FFC0CB",
  fialová: "#800080",
};

/** Color + display name from Adidas/asset winner URL (e.g. zelena in filename). */
function wardrobeColorFieldsFromWinnerUrl(imageUrl, opts = {}) {
  const hay = String(imageUrl || "").toLowerCase();
  const detected = matchSlugColors(hay);
  if (!detected.length) return null;

  const colorName = detected[0];
  const sub = String(opts.subCategoryKey || "").trim();
  const hex = WARDROBE_COLOR_NAME_HEX[colorName] || "#808080";

  let name = String(opts.title || "").trim();
  if (sub === "plavecke_sortky") {
    if (colorName === "zelená") name = "Zelené plavecké šortky";
    else if (colorName === "čierna") name = "Čierne plavecké šortky";
    else if (colorName === "modrá") name = "Modré plavecké šortky";
    else if (colorName === "biela") name = "Biele plavecké šortky";
    else if (colorName === "červená") name = "Červené plavecké šortky";
    else name = `${colorName.charAt(0).toUpperCase()}${colorName.slice(1)} plavecké šortky`;
  }

  return {
    colors: [colorName],
    baseColors: [colorName],
    colorHex: [hex],
    ...(name ? { name } : {}),
  };
}

function mergeWardrobeColorPatch(existing = {}, winnerUrl, opts = {}) {
  const fromUrl = wardrobeColorFieldsFromWinnerUrl(winnerUrl, opts);
  if (!fromUrl) return null;
  return fromUrl;
}

function inferHeuristicFromSignals(signals) {
  const blob = [
    signals.slug?.joined || "",
    signals.slug?.path || "",
    signals.metadata?.title || "",
    signals.metadata?.description || "",
    signals.jsonLd?.name || "",
    signals.jsonLd?.category || "",
    signals.metadata?.imageUrl || "",
    signals.domainBrand || "",
  ].join(" ");

  const tokens = signals.slug?.tokens || [];
  if (tokens.includes("mikina") && tokens.includes("ul")) {
    const hoodieRule = SLUG_CLOTHING_RULES.find(
      (r) => r.sub === "mikina_s_kapucnou"
    );
    if (hoodieRule) {
      const colors = matchSlugColors(blob);
      return {
        clothing: hoodieRule,
        colors,
        mainGroupKey: hoodieRule.main,
        categoryKey: hoodieRule.cat,
        subCategoryKey: hoodieRule.sub,
        canonical_type: hoodieRule.canon,
        name: hoodieRule.name,
      };
    }
  }

  const clothing = matchSlugClothingRule(blob);
  const colors = matchSlugColors(blob);

  if (!clothing) return { clothing: null, colors };

  return {
    clothing,
    colors,
    mainGroupKey: clothing.main,
    categoryKey: clothing.cat,
    subCategoryKey: clothing.sub,
    canonical_type: clothing.canon,
    name: clothing.name,
  };
}

async function fetchProductPageHtml(url) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 16000);
  let referer = "";
  try {
    const u = new URL(url);
    referer = `${u.protocol}//${u.host}/`;
  } catch (_) {}
  try {
    const res = await fetch(url, {
      method: "GET",
      redirect: "follow",
      signal: controller.signal,
      headers: {
        "User-Agent":
          "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
        Accept:
          "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8",
        "Accept-Language": "fi-FI,fi;q=0.9,en-US;q=0.8,en;q=0.7,sk;q=0.9",
        "Cache-Control": "no-cache",
        Pragma: "no-cache",
        "Upgrade-Insecure-Requests": "1",
        "Sec-Fetch-Dest": "document",
        "Sec-Fetch-Mode": "navigate",
        "Sec-Fetch-Site": "none",
        "Sec-Fetch-User": "?1",
        ...(referer ? { Referer: referer } : {}),
      },
    });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const text = await res.text();
    return String(text || "").slice(0, 600000);
  } finally {
    clearTimeout(timer);
  }
}

async function extractAllProductSignals(url) {
  const slug = extractStrategy3Slug(url);
  const domainBrand = extractStrategy4DomainBrand(url);

  const signals = {
    sourceUrl: url,
    slug,
    domainBrand,
    metadata: { title: "", description: "", imageUrl: "", raw: {} },
    jsonLd: {
      name: "",
      brand: "",
      description: "",
      imageUrl: "",
      category: "",
      colors: [],
      snippet: "",
    },
    fetchOk: false,
  };

  logger.info("[URL_AI][slug]", {
    tokens: slug.tokens,
    joined: slug.joined,
    hostname: slug.hostname,
  });
  if (domainBrand) {
    logger.info("[URL_AI][domain]", { brand: domainBrand });
  }

  let html = "";
  try {
    html = await fetchProductPageHtml(url);
    signals.fetchOk = true;
  } catch (e) {
    logger.warn("[URL_AI][fetch_failed]", {
      url,
      error: e?.message || String(e),
    });
  }

  if (html) {
    const s1 = extractStrategy1Metadata(html);
    signals.metadata = {
      title: s1.title,
      description: s1.description,
      imageUrl: s1.imageUrl,
      raw: s1.raw,
    };
    logger.info("[URL_AI][metadata]", {
      title: s1.title ? s1.title.slice(0, 120) : "",
      hasDescription: !!s1.description,
      hasImage: !!s1.imageUrl,
    });

    const s2 = extractStrategy2JsonLd(html);
    signals.jsonLd = s2;
    logger.info("[URL_AI][jsonld]", {
      hasProduct: !!s2.product,
      name: s2.name ? s2.name.slice(0, 120) : "",
      brand: s2.brand,
      category: s2.category,
      colors: s2.colors,
    });

    const pickedImage = pickBestProductImage(url, html, signals);
    if (pickedImage) {
      signals.selectedImageUrl = pickedImage;
      signals.metadata.imageUrl = pickedImage;
      if (!signals.jsonLd.imageUrl) {
        signals.jsonLd.imageUrl = pickedImage;
      }
    }
  }

  signals.heuristic = inferHeuristicFromSignals(signals);
  if (signals.heuristic?.clothing) {
    logger.info("[URL_AI][heuristic]", signals.heuristic);
  }

  return signals;
}

function mergeWithHeuristics(parsed, signals, pickAllowedKey) {
  const h = signals.heuristic || {};
  const meta = signals.metadata || {};
  const jd = signals.jsonLd || {};

  let mainGroupKey = pickAllowedKey(parsed.mainGroupKey, WARDROBE_MAIN_GROUP_KEYS);
  let categoryKey = pickAllowedKey(parsed.categoryKey, WARDROBE_CATEGORY_KEYS);
  let subCategoryKey = pickAllowedKey(parsed.subCategoryKey, WARDROBE_SUB_CATEGORY_KEYS);

  if (!subCategoryKey && h.subCategoryKey) subCategoryKey = h.subCategoryKey;
  if (!categoryKey && h.categoryKey) categoryKey = h.categoryKey;
  if (!mainGroupKey && h.mainGroupKey) mainGroupKey = h.mainGroupKey;

  let canonical_type = String(parsed.canonical_type || h.canonical_type || "").trim();

  let name =
    String(parsed.name || "").trim() ||
    String(jd.name || "").trim() ||
    String(meta.title || "").trim() ||
    String(h.name || "").trim();

  if (name.length > 80) {
    name = name.split(/[|\-–—]/)[0].trim();
  }
  if (!name) name = h.name || "Produkt z linku";

  const aboutYouBrand = extractAboutYouBrandSlug(signals.sourceUrl || "");
  let brand =
    String(parsed.brand || "").trim() ||
    aboutYouBrand ||
    String(jd.brand || "").trim() ||
    String(signals.domainBrand || "").trim();
  if (
    aboutYouBrand &&
    String(brand).toLowerCase() === "about you"
  ) {
    brand = aboutYouBrand;
  }

  const imageUrl =
    String(parsed.imageUrl || "").trim() ||
    String(signals.selectedImageUrl || "").trim() ||
    String(meta.imageUrl || "").trim() ||
    String(jd.imageUrl || "").trim();

  return {
    mainGroupKey,
    categoryKey,
    subCategoryKey,
    canonical_type,
    name,
    brand,
    imageUrl,
  };
}

// Deploy: firebase deploy --only functions:analyzeClothingProductUrl
exports.analyzeClothingProductUrl = functions
  .region("us-east1")
  .runWith({ timeoutSeconds: 300, memory: "1GB" })
  .https.onCall(async (data, context) => {
    if (!context.auth || !context.auth.uid) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Musíš byť prihlásený."
      );
    }

    let url = String(data?.url || "").trim();
    if (!url) {
      throw new functions.https.HttpsError("invalid-argument", "Chýba url.");
    }
    if (!url.includes("://")) url = `https://${url}`;
    if (!isValidHttpUrl(url)) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Zadaj platný link na produkt."
      );
    }

    const metadataOnly = data?.metadataOnly === true;
    const sourcePageOnly = data?.sourcePageOnly === true || metadataOnly;

    const apiKey = getOpenAiKey();
    if (!sourcePageOnly && !apiKey) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "Server nemá nastavený OPENAI_API_KEY."
      );
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
      black: "čierna",
      white: "biela",
      grey: "sivá",
      gray: "sivá",
      beige: "béžová",
      brown: "hnedá",
      olive: "olivová",
      khaki: "khaki",
      green: "zelená",
      red: "červená",
      burgundy: "bordová",
      yellow: "žltá",
      orange: "oranžová",
      pink: "ružová",
      purple: "fialová",
      blue: "modrá",
    };

    const STYLE_MAP = {
      elegant: "elegantný",
      formal: "elegantný",
      business: "business",
      casual: "casual",
      street: "streetwear",
      streetwear: "streetwear",
      sport: "športový",
      sports: "športový",
      outdoor: "outdoor",
      basic: "basic",
      party: "party",
    };

    const PATTERN_MAP = {
      solid: "jednofarebné",
      plain: "jednofarebné",
      striped: "pruhované",
      checked: "kockované",
      plaid: "kockované",
      dots: "bodkované",
      floral: "kvetované",
      camo: "maskáčové",
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

    function pickAllowedKey(value, allowed) {
      const raw = String(value || "").trim().toLowerCase();
      if (!raw) return null;
      return allowed.find((k) => k.toLowerCase() === raw) || null;
    }

    const imageCleanupOnly = data?.imageCleanupOnly === true;

    try {
      logger.info("[ANALYZE_PRODUCT_URL][start]", {
        uid: context.auth.uid,
        metadataOnly,
        sourcePageOnly,
        imageCleanupOnly,
      });
      logger.info("[ANALYZE_PRODUCT_URL][url]", { url });

      if (sourcePageOnly) {
        const source = await extractProductLinkSourcePage(url);
        const h = source.heuristic || {};
        const metaTitle =
          source.signals?.metadata?.title ||
          source.signals?.jsonLd?.name ||
          h.name ||
          "";
        let metaName = String(metaTitle || "").trim();
        if (metaName.length > 80) {
          metaName = metaName.split(/[|\-–—]/)[0].trim();
        }
        const metaBrand =
          extractAboutYouBrandSlug(url) ||
          String(source.signals?.jsonLd?.brand || "").trim() ||
          String(source.signals?.domainBrand || "").trim() ||
          (isAdidasProductSourceUrl(url) ? "Adidas" : "");
        const seed = String(source.seedImage || "").trim();
        const hasWardrobe =
          !!h.subCategoryKey && !!h.categoryKey && !!h.mainGroupKey;
        let colors = source.colors || [];
        let displayName = metaName || h.name || "Produkt z linku";
        const colorFromSeed = mergeWardrobeColorPatch(
          {},
          seed,
          { subCategoryKey: h.subCategoryKey, title: displayName }
        );
        if (colorFromSeed) {
          colors = colorFromSeed.colors;
          if (colorFromSeed.name) displayName = colorFromSeed.name;
        }
        return {
          sourceUrl: url,
          name: displayName,
          brand: metaBrand || null,
          imageUrl: seed,
          productImageUrl: seed || null,
          originalImageUrl: seed || null,
          mainGroupKey: h.mainGroupKey || null,
          categoryKey: h.categoryKey || null,
          subCategoryKey: h.subCategoryKey || null,
          colors,
          baseColors: colorFromSeed?.baseColors || colors,
          colorHex: colorFromSeed?.colorHex || [],
          seasons:
            h.subCategoryKey === "plavecke_sortky" ? ["leto"] : [],
          styles: ["casual", "športový"],
          patterns: ["jednofarebné"],
          partial: !hasWardrobe || !seed,
          sourceImageCandidates: (source.candidates || []).map((c) => c.url),
        };
      }

      const signals = await extractAllProductSignals(url);
      const heuristic = signals.heuristic || {};
      const aboutYouBrand = extractAboutYouBrandSlug(url);

      const metaTitle =
        signals.metadata?.title ||
        signals.jsonLd?.name ||
        heuristic.name ||
        "";
      let metaName = String(metaTitle || "").trim();
      if (metaName.length > 80) {
        metaName = metaName.split(/[|\-–—]/)[0].trim();
      }
      if (!metaName) metaName = heuristic.name || "Produkt z linku";

      const metaBrand =
        aboutYouBrand ||
        String(signals.jsonLd?.brand || "").trim() ||
        String(heuristic.brand || "").trim() ||
        "";

      const metaImageUrl =
        String(signals.selectedImageUrl || "").trim() ||
        String(signals.metadata?.imageUrl || "").trim() ||
        String(signals.jsonLd?.imageUrl || "").trim();

      logger.info("[ANALYZE_PRODUCT_URL][metadata]", {
        title: signals.metadata?.title ? String(signals.metadata.title).slice(0, 120) : "",
        brand: metaBrand,
        hasImage: !!metaImageUrl,
        fetchOk: signals.fetchOk,
      });
      logger.info("[ANALYZE_PRODUCT_URL][image]", {
        imageUrl: metaImageUrl ? String(metaImageUrl).slice(0, 200) : "",
      });

      if (metadataOnly) {
        const source = await extractProductLinkSourcePage(url);
        const h = source.heuristic || {};
        const seed = String(source.seedImage || "").trim();
        const metaTitle =
          source.signals?.metadata?.title ||
          source.signals?.jsonLd?.name ||
          h.name ||
          "";
        let metaNameOnly = String(metaTitle || "").trim();
        if (metaNameOnly.length > 80) {
          metaNameOnly = metaNameOnly.split(/[|\-–—]/)[0].trim();
        }
        const metaBrandOnly =
          extractAboutYouBrandSlug(url) ||
          String(source.signals?.jsonLd?.brand || "").trim() ||
          String(source.signals?.domainBrand || "").trim() ||
          (isAdidasProductSourceUrl(url) ? "Adidas" : "");
        const colors = source.colors || [];
        const hasWardrobe =
          !!h.subCategoryKey && !!h.categoryKey && !!h.mainGroupKey;
        return {
          sourceUrl: url,
          name: metaNameOnly || h.name || "Produkt z linku",
          brand: metaBrandOnly || null,
          imageUrl: seed,
          productImageUrl: seed || null,
          originalImageUrl: seed || null,
          mainGroupKey: h.mainGroupKey || null,
          categoryKey: h.categoryKey || null,
          subCategoryKey: h.subCategoryKey || null,
          colors,
          seasons: h.subCategoryKey === "plavecke_sortky" ? ["leto"] : [],
          styles: ["casual", "športový"],
          patterns: ["jednofarebné"],
          partial: !hasWardrobe || !seed,
          sourceImageCandidates: (source.candidates || []).map((c) => c.url),
        };
      }

      if (imageCleanupOnly) {
        const cleanupImageUrl =
          String(data?.imageUrl || "").trim() || metaImageUrl;
        if (!cleanupImageUrl || !isValidHttpUrl(cleanupImageUrl)) {
          throw new functions.https.HttpsError(
            "invalid-argument",
            "Chýba platný imageUrl pre cleanup."
          );
        }
        logger.info("[ANALYZE_PRODUCT_URL][image_cleanup_only]", {
          imageUrl: cleanupImageUrl.slice(0, 160),
        });
        return executeProductLinkImageCleanup({
          uid: context.auth.uid,
          url,
          imageUrl: cleanupImageUrl,
          apiKey,
          hostname: String(signals?.slug?.hostname || "").toLowerCase(),
          pageTitle: metaName,
          fastMode: true,
        });
      }

      const pageHost = String(signals?.slug?.hostname || "").toLowerCase();
      let preparedImage = {
        analysisImageUrl: metaImageUrl,
        productImageUrl: metaImageUrl,
        originalImageUrl: metaImageUrl,
        personDetected: false,
      };
      if (metaImageUrl && isValidHttpUrl(metaImageUrl)) {
        preparedImage = await prepareProductImageForAnalysis({
          uid: context.auth.uid,
          imageUrl: metaImageUrl,
          hostname: pageHost,
          apiKey,
          pageTitle: metaName,
        });
      }

      const imageUrlForVision = String(
        preparedImage.analysisImageUrl || metaImageUrl || ""
      ).trim();
      const productImageOut = String(
        preparedImage.productImageUrl || metaImageUrl || ""
      ).trim();
      const personInImage = preparedImage.personDetected === true;

      const clothingOnlyVisionRules = personInImage
        ? `
The product image was a model/lifestyle shot. Analyze ONLY the clothing item.
Ignore completely: face, body, hands, hair, background, environment, props.
Focus only on: garment type, shape, sleeves, hood, zipper, pockets, colors, pattern, fabric look.
`
        : "";

      const systemPrompt = `
You are an AI wardrobe assistant for the Outfit Of The Day app.
Analyze a fashion product from:
- product URL
- title
- brand
- description
- product image (when provided)
${clothingOnlyVisionRules}

Return JSON only.
Use exact existing wardrobe keys.
If text metadata and image disagree, trust the image for color/pattern and trust text/title/URL for brand/product name.
Do not include price.
Do not invent unsupported keys.
If unsure, use closest existing category but do not leave obvious clothing type empty.

Use ONLY these existing wardrobe keys (Slovak app schema):
mainGroupKey: ${JSON.stringify(WARDROBE_MAIN_GROUP_KEYS)}
categoryKey: ${JSON.stringify(WARDROBE_CATEGORY_KEYS)}
subCategoryKey: ${JSON.stringify(WARDROBE_SUB_CATEGORY_KEYS)}
colors: ${JSON.stringify(ALLOWED_COLORS)}
styles: ${JSON.stringify(ALLOWED_STYLES)}
patterns (max 1): ${JSON.stringify(ALLOWED_PATTERNS)}
seasons: ${JSON.stringify(ALLOWED_SEASONS)}

Return STRICT JSON ONLY. No markdown. No extra text.

Required JSON shape:
{
  "name": "short Slovak garment name",
  "brand": "brand or empty string",
  "mainGroupKey": "oblecenie|obuv|doplnky",
  "categoryKey": "valid categoryKey",
  "subCategoryKey": "valid subCategoryKey",
  "canonical_type": "english type key e.g. hoodie, jeans, t_shirt",
  "colors": [],
  "seasons": [],
  "styles": [],
  "patterns": [],
  "imageUrl": "",
  "confidence": 0.0
}
      `.trim();

      const userPrompt = `
URL: ${url}
About You brand hint: ${aboutYouBrand || ""}
Domain brand hint: ${signals.domainBrand || ""}
Slug tokens: ${JSON.stringify(signals.slug?.tokens || [])}
Slug joined: ${signals.slug?.joined || ""}

Page metadata:
title: ${signals.metadata?.title || ""}
description: ${signals.metadata?.description || ""}
image: ${signals.metadata?.imageUrl || ""}

JSON-LD:
name: ${signals.jsonLd?.name || ""}
brand: ${signals.jsonLd?.brand || ""}
category: ${signals.jsonLd?.category || ""}
colors: ${JSON.stringify(signals.jsonLd?.colors || [])}
description: ${(signals.jsonLd?.description || "").slice(0, 600)}

URL slug heuristic suggestion:
${JSON.stringify(heuristic.clothing ? {
  mainGroupKey: heuristic.mainGroupKey,
  categoryKey: heuristic.categoryKey,
  subCategoryKey: heuristic.subCategoryKey,
  canonical_type: heuristic.canonical_type,
  name: heuristic.name,
  colors: heuristic.colors,
} : null)}
      `.trim();

      const userContent = [{ type: "text", text: userPrompt }];
      if (imageUrlForVision && isValidHttpUrl(imageUrlForVision)) {
        userContent.push({
          type: "image_url",
          image_url: { url: imageUrlForVision, detail: "low" },
        });
      }

      const openAiBody = {
        model: "gpt-4o-mini",
        temperature: 0.15,
        messages: [
          { role: "system", content: systemPrompt },
          { role: "user", content: userContent },
        ],
      };

      logger.info("[ANALYZE_PRODUCT_URL][openai_start]", {
        hasVision: userContent.length > 1,
        personInImage,
        analysisImage: imageUrlForVision
          ? String(imageUrlForVision).slice(0, 200)
          : "",
        slugTokens: signals.slug?.tokens,
        heuristicSub: heuristic.subCategoryKey || null,
      });

      let parsed = {};
      try {
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
          logger.error("[ANALYZE_PRODUCT_URL][error]", {
            stage: "openai_http",
            status: response.status,
            errorText: String(errorText).slice(0, 600),
          });
        } else {
          const aiJson = await response.json();
          const text = aiJson?.choices?.[0]?.message?.content;
          parsed = extractFirstJsonObjectGlobal(text) || {};
          logger.info("[ANALYZE_PRODUCT_URL][openai_result]", {
            name: parsed.name || "",
            subCategoryKey: parsed.subCategoryKey || "",
            colors: parsed.colors || [],
          });
        }
      } catch (openAiErr) {
        logger.error("[ANALYZE_PRODUCT_URL][error]", {
          stage: "openai_fetch",
          message: openAiErr?.message || String(openAiErr),
        });
        parsed = {};
      }

      const merged = mergeWithHeuristics(parsed, signals, pickAllowedKey);

      const colors = [];
      for (const c of [
        ...toStringArray(parsed.colors),
        ...(heuristic.colors || []),
        ...(signals.jsonLd?.colors || []),
      ]) {
        const mapped = normalizeToAllowed(c, ALLOWED_COLORS, COLOR_MAP);
        if (mapped && !colors.includes(mapped)) colors.push(mapped);
      }
      if (colors.length === 0) {
        for (const c of matchSlugColors(signals.slug?.joined || "")) {
          const mapped = normalizeToAllowed(c, ALLOWED_COLORS, COLOR_MAP);
          if (mapped && !colors.includes(mapped)) colors.push(mapped);
        }
      }

      const styles = [];
      for (const s of toStringArray(parsed.styles)) {
        const mapped = normalizeToAllowed(s, ALLOWED_STYLES, STYLE_MAP);
        if (mapped && !styles.includes(mapped)) styles.push(mapped);
      }
      if (styles.length === 0) styles.push("casual");

      let patterns = [];
      for (const p of toStringArray(parsed.patterns)) {
        const mapped = normalizeToAllowed(p, ALLOWED_PATTERNS, PATTERN_MAP);
        if (mapped) {
          patterns = [mapped];
          break;
        }
      }
      if (patterns.length === 0) patterns = ["jednofarebné"];

      let seasons = [];
      for (const sea of toStringArray(parsed.seasons)) {
        const mapped = normalizeToAllowed(sea, ALLOWED_SEASONS, SEASON_MAP);
        if (mapped && !seasons.includes(mapped)) seasons.push(mapped);
      }
      const hasAllFour = ["jar", "leto", "jeseň", "zima"].every((x) =>
        seasons.includes(x)
      );
      if (seasons.includes("celoročne") || hasAllFour) seasons = ["celoročne"];
      if (seasons.length === 0) seasons = ["celoročne"];

      const partial =
        !merged.subCategoryKey || !merged.categoryKey || !merged.mainGroupKey;

      const result = {
        name: merged.name,
        brand: merged.brand,
        mainGroupKey: merged.mainGroupKey,
        categoryKey: merged.categoryKey,
        subCategoryKey: merged.subCategoryKey,
        canonical_type: merged.canonical_type,
        colors,
        seasons,
        styles,
        patterns,
        imageUrl: productImageOut || merged.imageUrl,
        productImageUrl: productImageOut || merged.imageUrl || null,
        originalImageUrl: preparedImage.originalImageUrl || metaImageUrl || null,
        analysisImageUrl: imageUrlForVision || null,
        personDetected: personInImage,
        sourceUrl: url,
        partial,
      };

      logger.info("[ANALYZE_PRODUCT_URL][openai_result]", {
        uid: context.auth.uid,
        partial,
        subCategoryKey: result.subCategoryKey,
        categoryKey: result.categoryKey,
        name: result.name,
        brand: result.brand,
        colors: result.colors,
      });

      return result;
    } catch (e) {
      if (e instanceof functions.https.HttpsError) throw e;
      logger.error("[ANALYZE_PRODUCT_URL][error]", {
        message: e?.message || String(e),
        stack: e?.stack ? String(e.stack).slice(0, 500) : "",
      });
      throw new functions.https.HttpsError(
        "internal",
        "Produkt sa nepodarilo analyzovať: " + (e?.message || String(e))
      );
    }
  });

/**
 * Shared product-link image cleanup (rembg + e-shop product photo).
 * Used by prepareProductLinkImage and analyzeClothingProductUrl (imageCleanupOnly).
 */
async function executeProductLinkImageCleanup({
  uid,
  url,
  imageUrl,
  apiKey,
  hostname = "",
  pageTitle = "",
  fastMode = false,
}) {
  if (fastMode) {
    return runPrepareProductLinkImagePipeline({
      uid,
      url,
      imageUrl,
      hostname,
      pageTitle,
      apiKey,
    });
  }

  const needsCleanupHeuristic = shouldRunPersonDetection(
    imageUrl,
    hostname,
    pageTitle
  );

  logger.info("[PRODUCT_IMAGE][needs_cleanup]", {
    needsCleanup: needsCleanupHeuristic,
    imageUrl: String(imageUrl || "").slice(0, 160),
  });

  if (!needsCleanupHeuristic) {
    logger.info("[PRODUCT_IMAGE][contains_person]", { person: false });
    return {
      containsPerson: false,
      needsCleanup: false,
      cleanImageUrl: null,
      productImageUrl: imageUrl,
      originalImageUrl: imageUrl,
      analysisImageUrl: imageUrl,
      cleanupSkipped: true,
    };
  }

  logger.info("[PRODUCT_IMAGE][cleanup_start]", {
    url: String(imageUrl || "").slice(0, 160),
  });

  const prepared = await prepareProductImageForAnalysis({
    uid,
    imageUrl,
    hostname,
    apiKey,
    pageTitle,
    productUrl: url,
  });

  const containsPerson = prepared.personDetected === true;
  const cleaned =
    containsPerson &&
    prepared.productImageUrl &&
    prepared.productImageUrl !== prepared.originalImageUrl;

  if (prepared.personConfidence != null) {
    logger.info("[PRODUCT_IMAGE][person_confidence]", {
      confidence: prepared.personConfidence,
    });
  }
  if (prepared.personReason) {
    logger.info("[PRODUCT_IMAGE][person_reason]", { reason: prepared.personReason });
  }
  logger.info("[PRODUCT_IMAGE][contains_person]", { person: containsPerson });

  if (cleaned) {
    logger.info("[PRODUCT_IMAGE][cleanup_done]");
    logger.info("[PRODUCT_IMAGE][clean_image_url]", {
      url: String(prepared.productImageUrl || "").slice(0, 200),
    });
  } else if (containsPerson && prepared.cleanFailed) {
    logger.info("[PRODUCT_IMAGE][cleanup_failed]");
  }

  return {
    containsPerson,
    needsCleanup: containsPerson,
    cleanImageUrl: cleaned ? prepared.productImageUrl : null,
    productImageUrl: prepared.productImageUrl || imageUrl,
    originalImageUrl: prepared.originalImageUrl || imageUrl,
    analysisImageUrl: prepared.analysisImageUrl || imageUrl,
    cleanupFailed: prepared.cleanFailed === true,
  };
}

// Deploy: firebase deploy --only functions:prepareProductLinkImage
exports.prepareProductLinkImage = functions
  .region("us-east1")
  .runWith({ timeoutSeconds: 300, memory: "2GB" })
  .https.onCall(async (data, context) => {
    if (!context.auth || !context.auth.uid) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Musíš byť prihlásený."
      );
    }

    let url = String(data?.url || "").trim();
    const imageUrl = String(data?.imageUrl || "").trim();
    if (!imageUrl || !isValidHttpUrl(imageUrl)) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Chýba platný imageUrl."
      );
    }
    if (!url.includes("://")) url = `https://${url}`;

    let hostname = "";
    try {
      hostname = new URL(url).hostname || "";
    } catch (_) {}

    return runPrepareProductLinkImagePipeline({
      uid: context.auth.uid,
      url,
      imageUrl,
      hostname,
      pageTitle: "",
      apiKey: getOpenAiKey() || null,
    });
  });

function wardrobeImageProcessSkuFromData(data) {
  if (!data) return "";
  const title = String(data.name || "").trim();
  const brand = String(data.brand || "").trim();
  const sourceUrl = String(data.sourceUrl || "").trim();
  return (
    String(data.productLinkSku || "").trim() ||
    extractProductSkuFromText(`${title} ${brand}`, sourceUrl) ||
    ""
  );
}

function logWardrobeImageProcessState(data, uid, itemId) {
  const queued = data?.imageProcessingJobQueued === true;
  const status = String(data?.imageProcessingStatus || "");
  const reason = String(data?.imageProcessingReason || "");
  const sku = wardrobeImageProcessSkuFromData(data);
  const sourceUrl = String(data?.sourceUrl || "").trim();
  const line =
    `[WARDROBE_IMAGE_PROCESS][state] uid=${uid} itemId=${itemId} ` +
    `queued=${queued} status=${status} sku=${sku} reason=${reason} sourceUrl=${sourceUrl}`;
  console.log(line);
  logger.info(line);
  return { queued, status };
}

// ---------------------------------------------------------------------------
// Firestore trigger: users/{uid}/wardrobe/{itemId} — product-link image job
// Deploy: firebase deploy --only functions:processWardrobeProductLinkImage
// ---------------------------------------------------------------------------
exports.processWardrobeProductLinkImage = functions
  .region("us-central1")
  .runWith({ timeoutSeconds: 300, memory: "2GB" })
  .firestore.document("users/{uid}/wardrobe/{itemId}")
  .onWrite(async (change, context) => {
    const uid = context.params.uid;
    const itemId = context.params.itemId;
    const data = change.after.exists ? change.after.data() : null;

    console.log("[WARDROBE_IMAGE_PROCESS][trigger_start]", { uid, itemId });
    logger.info("[WARDROBE_IMAGE_PROCESS][trigger_start]", { uid, itemId });

    const { queued, status } = logWardrobeImageProcessState(data, uid, itemId);

    if (!data) return null;
    if (!queued) {
      const skipLine = `[WARDROBE_IMAGE_PROCESS][skip_reason] queued_false status=${status}`;
      console.log(skipLine);
      logger.info(skipLine);
      return null;
    }

    const ref = change.after.ref;

    await ref.set({ imageProcessingJobQueued: false }, { merge: true });

    try {
      await runWardrobeProductLinkBackgroundJob(uid, itemId, data);
    } catch (e) {
      logger.error("[WARDROBE_IMAGE_PROCESS][error]", {
        itemId,
        message: e?.message || String(e),
      });
      await ref.set(
        {
          imageProcessingStatus: "failed",
          imageProcessingReason: "job_error",
          imageProcessingJobQueued: false,
          imageProcessingUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    }
    return null;
  });