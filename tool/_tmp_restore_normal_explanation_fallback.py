from pathlib import Path

path = Path('functions/stylist/frozen_stylist_authority_v1.js')
text = path.read_text(encoding='utf-8')
old = '''  const sentences = [];
  const itemList = listUserFacingItems(selected.presentationItems);
  if (itemList) sentences.push(`Vybral som ${itemList}.`);
  const firstCompromise = selected.compromiseDetails && selected.compromiseDetails[0];
  if (firstCompromise) {
    const itemName = cleanText(firstCompromise.itemName, 120) || "jeden kúsok";
    const ideal = cleanText(firstCompromise.idealReplacementDescription, 180);
    sentences.push(ideal ?
      `${itemName} je kompromis; ideálnejšia náhrada by bola ${ideal}.` :
      `${itemName} je tu najlepší dostupný kompromis.`);
  }
  return sentences.slice(0, 2).join(" ") ||
    "Vybral som ti najlepšiu dostupnú kombináciu z tvojho šatníka.";
'''
new = '''  const sentences = [];
  const itemList = listUserFacingItems(selected.presentationItems);
  const weatherSummary = userFacingWeatherSummary(
    normalized.resolvedContext && normalized.resolvedContext.weather,
  );
  if (itemList) {
    let summary = `Vybral som ${itemList} ako najsilnejšiu dostupnú kombináciu z tvojho šatníka.`;
    if (weatherSummary) {
      summary += ` Pri ${weatherSummary} mi táto voľba dáva najväčší zmysel.`;
    }
    sentences.push(summary);
  }
  const firstCompromise = selected.compromiseDetails && selected.compromiseDetails[0];
  if (firstCompromise) {
    const itemName = cleanText(firstCompromise.itemName, 120) || "jeden kúsok";
    const ideal = cleanText(firstCompromise.idealReplacementDescription, 180);
    sentences.push(ideal ?
      `${itemName} je kompromis; ideálnejšia náhrada by bola ${ideal}.` :
      `${itemName} je tu najlepší dostupný kompromis.`);
  }
  return sentences.slice(0, 2).join(" ") ||
    "Vybral som ti najsilnejšiu dostupnú kombináciu z tvojho šatníka.";
'''
count = text.count(old)
if count != 1:
    raise RuntimeError(f'expected deterministic explanation block once, got {count}')
path.write_text(text.replace(old, new, 1), encoding='utf-8')
print('normal deterministic explanation fallback restored')
