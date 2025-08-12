#!/usr/bin/env python3
import json, re, shutil, sys, pathlib

# ---- CONFIG ----
repo = pathlib.Path("/Users/James/develop/apple/LangGo")
proj = repo / "LangGo.xcodeproj" / "project.pbxproj"
xcstrings = repo / "LangGo" / "Localizable.xcstrings"
lang = "fr"  # <- change to the new language code, e.g., "de", "fr", "ar"
# --------------

def backup(p: pathlib.Path):
    bak = p.with_suffix(p.suffix + ".bak")
    shutil.copy2(p, bak)
    print(f"Backed up {p} -> {bak}")

# 1) Patch project.pbxproj (add to knownRegions)
text = proj.read_text(encoding="utf-8")
backup(proj)

# Find knownRegions = ( ... );
m = re.search(r"knownRegions\s*=\s*\((.*?)\);", text, re.DOTALL)
if not m:
    print("Could not find knownRegions in project.pbxproj", file=sys.stderr); sys.exit(1)

block = m.group(1)
# Normalize entries
entries = [e.strip().strip(",") for e in block.splitlines() if e.strip()]
# Drop comments and quotes
clean = []
for e in entries:
    e = re.sub(r"/\*.*?\*/", "", e).strip()
    e = e.strip('"')
    if e:
        clean.append(e)

if lang not in clean:
    clean.append(lang)
    # Rebuild the block (keep quotes, pretty-ish)
    newblock = "\n\t\t\t\t" + ",\n\t\t\t\t".join(f"\"{e}\"" for e in clean) + ",\n\t\t\t"
    text = text[:m.start(1)] + newblock + text[m.end(1):]
    proj.write_text(text, encoding="utf-8")
    print(f"Added {lang} to knownRegions.")
else:
    print(f"{lang} already present in knownRegions.")

# 2) Patch Localizable.xcstrings (JSON catalog)
backup(xcstrings)
data = json.loads(xcstrings.read_text(encoding="utf-8"))

# Ensure required top-level keys exist
data.setdefault("sourceLanguage", "en")
data.setdefault("version", "1.0")
data.setdefault("strings", {})
data.setdefault("localizations", {})

loc = data["localizations"]
if lang not in loc:
    # Create empty locale entry with no translations yet
    loc[lang] = {
        "strings": {},         # each key -> {"stringUnit": {"state":"translated","value":"..."}}
        "excluded": False
    }
    xcstrings.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Added locale '{lang}' to Localizable.xcstrings.")
else:
    print(f"Locale '{lang}' already exists in Localizable.xcstrings.")

print("Done. Build/clean and select the App Language in the scheme to verify.")

