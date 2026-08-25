"use strict";

const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(__dirname, "..");
const functionsRoot = path.join(root, "functions");
const visited = new Set();
const filePathHints = [];

function walk(relFromFunctions) {
  const abs = path.resolve(functionsRoot, relFromFunctions);
  if (visited.has(abs)) return;
  if (!abs.startsWith(functionsRoot + path.sep)) return;
  if (!fs.existsSync(abs) || !abs.endsWith(".js")) return;
  visited.add(abs);
  const text = fs.readFileSync(abs, "utf8");
  const requireRe = /require\(["'](\.\.?\/[^"']+)["']\)/g;
  let m;
  while ((m = requireRe.exec(text))) {
    const next = path.resolve(path.dirname(abs), m[1]);
    const candidate = next.endsWith(".js") ? next : next + ".js";
    if (fs.existsSync(candidate)) {
      walk(path.relative(functionsRoot, candidate));
    }
  }
  const hintRe = /(?:\.\.\/lib\/[^"'\s]+|test\/fixtures\/[^"'\s]+|tool\/[^"'\s]+)/g;
  while ((m = hintRe.exec(text))) {
    filePathHints.push({
      module: path.relative(functionsRoot, abs),
      hint: m[0],
    });
  }
}

walk("wardrobe_authority_callable_exports.js");
console.log(JSON.stringify({
  moduleCount: visited.size,
  modules: [...visited].map((p) => path.relative(functionsRoot, p)).sort(),
  pathHints: filePathHints,
}, null, 2));
