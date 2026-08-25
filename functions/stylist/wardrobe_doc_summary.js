"use strict";

/**
 * Compact production Stylist wardrobe line.
 * Set membership is a preference/context signal, never a hard co-wear rule.
 */

function setMembershipOf(item) {
  const membership = item && item.setMembership;
  return membership && typeof membership === "object" ? membership : null;
}

function setPartnerIds(item, allItems = []) {
  const membership = setMembershipOf(item);
  const setId = String(membership?.setId || "").trim();
  if (!setId) return [];
  const selfId = String(item?.id || "").trim();
  return (Array.isArray(allItems) ? allItems : [])
      .filter((other) => {
        if (!other || other === item) return false;
        const otherId = String(other.id || "").trim();
        if (!otherId || otherId === selfId) return false;
        return String(setMembershipOf(other)?.setId || "").trim() === setId;
      })
      .map((other) => String(other.id).trim());
}

function setMembershipSummaryFragments(item, allItems = []) {
  const membership = setMembershipOf(item);
  if (!membership) return [];
  const setId = String(membership.setId || "").trim();
  if (!setId) return [];
  const setType = String(membership.setType || "").trim();
  const relationshipSource = String(membership.relationshipSource || "").trim();
  const authority = String(membership.authority || "").trim();
  const displayName = String(membership.displayName || "").trim();
  const partners = setPartnerIds(item, allItems);
  const fragments = [`setId: ${setId}`];
  if (setType) fragments.push(`setType: ${setType}`);
  if (relationshipSource) {
    fragments.push(`relationshipSource: ${relationshipSource}`);
    if (relationshipSource === "user_curated") {
      fragments.push("setPreference: explicit_user_preference");
    } else if (relationshipSource === "manufacturer_matching") {
      fragments.push("setPreference: confirmed_matching_relationship");
    }
  }
  if (authority) fragments.push(`setAuthority: ${authority}`);
  if (displayName) fragments.push(`setName: ${displayName}`);
  if (partners.length) fragments.push(`setPartnerIds: ${partners.join(",")}`);
  fragments.push("setSignal: preference_not_hard_constraint");
  return fragments;
}

function wardrobeDocToSummaryLine(item, allItems = []) {
  const name = String(item.name || item.typePretty || item.type || "").trim();
  const category = String(item.category || item.categoryKey || "").trim();
  const subCategory = String(item.subCategory || item.subCategoryKey || "").trim();
  const mainGroup = String(item.mainGroup || item.mainGroupKey || "").trim();
  const brand = String(item.brand || "").trim();
  const colors = Array.isArray(item.colors) ?
    item.colors.map((v) => String(v).trim()).filter(Boolean) :
    [];
  const styles = Array.isArray(item.styles) ?
    item.styles.map((v) => String(v).trim()).filter(Boolean) :
    [];
  const seasons = Array.isArray(item.seasons) ?
    item.seasons.map((v) => String(v).trim()).filter(Boolean) :
    [];
  const patterns = Array.isArray(item.patterns) ?
    item.patterns.map((v) => String(v).trim()).filter(Boolean) :
    [];
  const logoProminence = String(
    item.logo_prominence || item.logoProminence || "",
  ).trim();
  const warmthRaw = Number(item.warmth_level ?? item.warmthLevel);
  const warmthLevel = Number.isFinite(warmthRaw) ? warmthRaw : null;
  const layerRole = String(item.layer_role || item.layerRole || "").trim();

  const details = [];
  if (category) details.push(`kategória: ${category}`);
  if (subCategory) details.push(`subkategória: ${subCategory}`);
  if (mainGroup) details.push(`skupina: ${mainGroup}`);
  if (colors.length) details.push(`farby: ${colors.join(", ")}`);
  if (patterns.length) details.push(`vzor: ${patterns.join(", ")}`);
  if (logoProminence && logoProminence !== "unknown") {
    details.push(`logo: ${logoProminence}`);
  }
  if (warmthLevel != null) details.push(`teplo(1-10): ${warmthLevel}`);
  if (layerRole) details.push(`vrstva: ${layerRole}`);
  if (styles.length) details.push(`štýl: ${styles.join(", ")}`);
  if (seasons.length) details.push(`sezóny: ${seasons.join(", ")}`);
  if (brand) details.push(`značka: ${brand}`);
  const visualDesc = String(
    item.visual_description || item.visualDescription || "",
  ).trim();
  if (visualDesc) details.push(`vizuál: ${visualDesc.slice(0, 120)}`);
  if (item.id) details.push(`id: ${item.id}`);
  details.push(...setMembershipSummaryFragments(item, allItems));

  const label = name || "Neznámy kúsok";
  return details.length ? `- ${label} | ${details.join(" | ")}` : `- ${label}`;
}

module.exports = {
  setMembershipSummaryFragments,
  wardrobeDocToSummaryLine,
};
