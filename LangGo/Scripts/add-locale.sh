set -euo pipefail
PROJECT="/Users/James/develop/apple/LangGo/LangGo.xcodeproj"
APPNAME="LangGo"
LANG="hi"   # change this to the language code you want

# Create xcloc layout
WORK="$(mktemp -d)"
XCLoc="$WORK/${APPNAME}.${LANG}.xcloc"
mkdir -p "$XCLoc/Localized Contents/${LANG}.lproj"

# Put a minimal strings-catalog export in place (empty translations are fine).
# Name must match your catalog file in the project.
cat > "$XCLoc/Localized Contents/${LANG}.lproj/Localizable.xcstrings" <<'JSON'
{"sourceLanguage":"en","strings":{},"version":"1.0","localizations":{}}
JSON

# Optional: include a Contents.json (xcloc metadata). xcodebuild will still accept without it.

# Import into the project (this updates knownRegions and adds the locale to the catalog)
xcodebuild -importLocalizations -project "$PROJECT" -localizationPath "$XCLoc"

echo "Imported $LANG. Open Xcode → Localizable.xcstrings to see the new column."

