#!/usr/bin/env python3
import json, pathlib

repo = pathlib.Path("/Users/James/develop/apple/LangGo")
xc = repo / "LangGo" / "Localizable.xcstrings"
data = json.loads(xc.read_text(encoding="utf-8"))

source = data.get("sourceLanguage", "en")
targets = ["fr", "hi"]

data.setdefault("localizations", {})
for t in targets:
    data["localizations"].setdefault(t, {"strings": {}, "excluded": False})

for key, entry in data.get("strings", {}).items():
    # Try the new catalog shape first
    base = entry.get("localizations", {}).get(source, {}) \
               .get("stringUnit", {}).get("value")
    # Fallback if older shape
    if base is None:
        base = entry.get("stringUnit", {}).get("value")
    if base is None:
        continue
    for t in targets:
        tgt = data["localizations"][t]["strings"].setdefault(key, {})
        tgt.setdefault("stringUnit", {"state": "needsReview", "value": base})

xc.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print("Backfilled fr & hi with English placeholders.")
