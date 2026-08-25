"use strict";

/**
 * CLI/local utility entry for owner-supplied feed samples.
 * Usage (after access): node shopping/partners/reserved/validate_sample_cli.js <path>
 * Path must be outside git (see .gitignore private_partner_samples/).
 */

const fs = require("node:fs");
const path = require("node:path");
const {validateCjFeedSample} = require("./sample_validator");
const {evaluateMvpGate} = require("./mvp_go_nogo");

function main(argv = process.argv.slice(2)) {
  if (!argv.length) {
    console.log(JSON.stringify({
      ok: false,
      message: "usage: node validate_sample_cli.js <sample-path>",
      note: "Keep samples under private_partner_samples/ (gitignored)",
    }));
    return 1;
  }
  const samplePath = path.resolve(argv[0]);
  if (samplePath.includes(`${path.sep}functions${path.sep}`) &&
      !samplePath.includes("private_partner_samples")) {
    console.log(JSON.stringify({
      ok: false,
      message: "refusing sample path inside tracked functions tree",
    }));
    return 2;
  }
  const raw = fs.readFileSync(samplePath, "utf8");
  const report = validateCjFeedSample(raw);
  const gate = evaluateMvpGate(report);
  console.log(JSON.stringify({
    ok: true,
    samplePath: path.basename(samplePath),
    report,
    gate,
  }, null, 2));
  return 0;
}

if (require.main === module) {
  process.exitCode = main();
}

module.exports = {main};
