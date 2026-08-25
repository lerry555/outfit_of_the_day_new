"use strict";

/**
 * Synthetic CJ/Reserved-shaped fixtures — NOT real Reserved data.
 */
function syntheticReservedCsv() {
  return [
    "id,title,description,link,image_link,additional_image_link,availability,price,sale_price,brand,gtin,mpn,item_group_id,color,size,size_system,google_product_category",
    "rsv-navy-m,Reserved Tee Navy M,Desc,https://www.reserved.com/sk/sk/p/rsv-navy,https://www.reserved.com/img/navy-1.jpg,https://www.reserved.com/img/navy-2.jpg,in_stock,29.99 EUR,19.99 EUR,Reserved,8590000111111,RSV-TEE-01,rsv-tee-01,Navy,M,EU,Apparel & Accessories > Clothing > Shirts & Tops",
    "rsv-navy-l,Reserved Tee Navy L,Desc,https://www.reserved.com/sk/sk/p/rsv-navy,https://www.reserved.com/img/navy-1.jpg,,in_stock,29.99 EUR,,Reserved,8590000111112,RSV-TEE-01,rsv-tee-01,Navy,L,EU,Apparel & Accessories > Clothing > Shirts & Tops",
    "rsv-white-m,Reserved Tee White M,Desc,https://www.reserved.com/sk/sk/p/rsv-white,https://www.reserved.com/img/white-model.jpg,,in_stock,29.99 EUR,,Reserved,,RSV-TEE-01,rsv-tee-01,White,M,EU,Apparel & Accessories > Clothing > Shirts & Tops",
    "rsv-nosize,Reserved Jacket,Desc,https://www.reserved.com/sk/sk/p/rsv-jacket,https://www.reserved.com/img/jacket.jpg,,in_stock,79.99 EUR,,Reserved,,,rsv-jacket,Black,,EU,Apparel & Accessories > Clothing > Outerwear",
    "rsv-bad-money,Bad,Desc,https://www.reserved.com/sk/sk/p/bad,https://www.reserved.com/img/bad.jpg,,in_stock,12.5,EUR,Reserved,,,,,,",
  ].join("\n");
}

function syntheticReservedXmlSnippet() {
  return `<?xml version="1.0"?>
<rss><channel>
<item>
  <g:id>rsv-xml-1</g:id>
  <g:title>Reserved XML Item</g:title>
  <g:description>Desc</g:description>
  <g:link>https://www.reserved.com/sk/sk/p/xml-1</g:link>
  <g:image_link>https://www.reserved.com/img/xml-1.jpg</g:image_link>
  <g:additional_image_link>https://www.reserved.com/img/xml-1b.jpg</g:additional_image_link>
  <g:availability>in_stock</g:availability>
  <g:price>39.99 EUR</g:price>
  <g:brand>Reserved</g:brand>
  <g:color>Olive</g:color>
  <g:size>S</g:size>
  <g:item_group_id>xml-group-1</g:item_group_id>
</item>
</channel></rss>`;
}

/** Cases for size model A/B/C documentation tests. */
const SIZE_MODEL_CASES = Object.freeze({
  A_ROW_PER_COLOR_SIZE: "one feed row per color+size",
  B_ROW_PER_COLOR_SIZE_LIST: "one feed row per color with size list",
  C_NO_PER_SIZE: "generic product row without per-size availability → UNKNOWN",
});

module.exports = {
  SIZE_MODEL_CASES,
  syntheticReservedCsv,
  syntheticReservedXmlSnippet,
};
