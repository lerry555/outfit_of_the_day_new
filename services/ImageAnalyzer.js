// Aplikácia si bude žiadať tento súbor od backendu
// Predpokladáme, že máme inštalované knižnice pre Google Cloud Vision AI
// Pred spustením musíte mať nastavené autentifikačné údaje (napr. premenné prostredia)
// v tomto príklade je to zjednodušené pre pochopenie logiky

import { ImageAnnotatorClient } from '@google-cloud/vision';

// Inicializácia klienta Google Vision AI
const client = new ImageAnnotatorClient();

/**
 * Táto funkcia analyzuje obrázok a rozpozná typ oblečenia a farby.
 * @param {string} imageUri - URL alebo cesta k obrázku, ktorý sa má analyzovať.
 * @returns {Promise<Array<Object>>} Pole rozpoznaných objektov s ich popisom.
 */
async function analyzeImage(imageUri) {
  try {
    // Definujeme požiadavku, ktorú pošleme do Vision AI
    const [result] = await client.annotateImage({
      image: { source: { imageUri } },
      features: [{ type: 'LABEL_DETECTION' }], // 'LABEL_DETECTION' identifikuje objekty na obrázku
    });

    const labels = result.labelAnnotations;
    console.log('Rozpoznané objekty:');

    // Filtrujeme a spracujeme výsledky, aby sme našli len to, čo súvisí s oblečením
    const clothingItems = labels
      .filter(label =>
        label.description.toLowerCase().includes('clothing') ||
        label.description.toLowerCase().includes('shirt') ||
        label.description.toLowerCase().includes('pants') ||
        label.description.toLowerCase().includes('dress') ||
        label.description.toLowerCase().includes('shoes')
      )
      .map(label => ({
        type: label.description,
        score: label.score // Score udáva pravdepodobnosť, že ide o daný objekt (0.0 - 1.0)
      }));

    console.log(clothingItems);
    return clothingItems;

  } catch (error) {
    console.error('Chyba pri analýze obrázka:', error);
    return null;
  }
}

// Exportujeme funkciu, aby sme ju mohli použiť v iných častiach aplikácie
export { analyzeImage };