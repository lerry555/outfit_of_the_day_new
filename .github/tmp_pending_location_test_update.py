from pathlib import Path

path = Path('functions/stylist/v2/stylist_one_brain_runtime_v2.test.js')
text = path.read_text()
old = '  assert.equal(calls.brainInputs.length, 0, "country preflight must not depend on a Brain tool decision");\n'
new = '  assert.equal(calls.brainInputs.length, 1, "Brain parses the original scenario once; runtime still owns the deterministic broad-country clarification");\n'
assert old in text
text = text.replace(old, new, 1)
path.write_text(text)
