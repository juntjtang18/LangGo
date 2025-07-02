#!/usr/bin/env python3
import os
import argparse
import concurrent.futures
import re
from deep_translator import GoogleTranslator
import xml.etree.ElementTree as ET

# --- SCRIPT CONFIGURATION ---
# Adjust the number of concurrent threads. A good starting point is 10.
MAX_WORKERS = 10
# The namespace for XLIFF 1.2 files. This is crucial for parsing.
XLIFF_NAMESPACE = {'xliff': 'urn:oasis:names:tc:xliff:document:1.2'}
# Regex to detect strings that are just format specifiers and should not be translated.
FORMAT_SPECIFIER_REGEX = re.compile(r'^[%@\d\$.]*[dfsclduoxfegapDFSCLaUOXFEG@]$')

# --- HELPER FUNCTIONS ---

def find_xliff_file(contents_path):
    """Finds the first .xliff file in a directory."""
    if not os.path.isdir(contents_path):
        return None, f"Directory not found: {contents_path}"
    
    xliff_files = [f for f in os.listdir(contents_path) if f.endswith(".xliff")]
    if not xliff_files:
        return None, f"No .xliff file found in {contents_path}"
        
    return os.path.join(contents_path, xliff_files[0]), None

def translate_text_worker(text, target_language_code, source_language_code="en"):
    """
    Worker function for translation. Uses the deep_translator library.
    """
    # Do not translate if the text is just a format specifier.
    if not text or FORMAT_SPECIFIER_REGEX.match(text):
        return text

    # Map language codes for the translation service.
    effective_target_code = 'zh-CN' if target_language_code == 'zh-Hans' else target_language_code

    try:
        # Initializing the translator inside the worker is better for thread safety.
        return GoogleTranslator(source=source_language_code, target=effective_target_code).translate(text)
    except Exception as e:
        print(f"❌ TRANSLATION FAILED for text: '{text}' to {target_language_code}. Reason: {e}")
        return None  # Return None on failure

def process_localization_folder(export_dir):
    """
    Reads the exported .xcloc folders, finds all source strings,
    and translates them for every target language, overwriting any previous translations.
    """
    print(f"📂 Processing localization export directory: {export_dir}")

    lang_folders = [d for d in os.listdir(export_dir) if d.endswith(".xcloc")]
    source_lang_code = "en"
    source_folder = f"{source_lang_code}.xcloc"

    if source_folder not in lang_folders:
        print(f"❌ Error: Source language folder '{source_folder}' not found in the export directory.")
        return

    source_contents_path = os.path.join(export_dir, source_folder, "Localized Contents")
    source_xliff_path, error = find_xliff_file(source_contents_path)
    if error:
        print(f"❌ {error}")
        return
    
    try:
        tree = ET.parse(source_xliff_path)
        root = tree.getroot()
    except (FileNotFoundError, ET.ParseError) as e:
        print(f"❌ Error reading or parsing source .xliff file: {e}")
        return

    source_strings = {}
    for file_node in root.findall('xliff:file', XLIFF_NAMESPACE):
        if file_node.get('original', '').endswith('Localizable.xcstrings'):
            for unit_node in file_node.findall('.//xliff:trans-unit', XLIFF_NAMESPACE):
                key = unit_node.get('id')
                source_node = unit_node.find('xliff:source', XLIFF_NAMESPACE)
                if key is not None and source_node is not None and source_node.text:
                    source_strings[key] = source_node.text
            break

    if not source_strings:
        print("✅ No localizable strings found in the source file's 'Localizable.xcstrings' section.")
        return
        
    print(f"✅ Found {len(source_strings)} strings in the source language ({source_lang_code}).")

    target_lang_folders = [f for f in lang_folders if f != source_folder]

    for lang_folder in target_lang_folders:
        target_lang_code = lang_folder.replace(".xcloc", "")
        print(f"\n--- Processing target language: {target_lang_code} ---")
        
        target_contents_path = os.path.join(export_dir, lang_folder, "Localized Contents")
        target_xliff_path, error = find_xliff_file(target_contents_path)
        if error:
            print(f"⚠️ Could not find .xliff for {target_lang_code}, skipping. Reason: {error}")
            continue
        
        try:
            target_tree = ET.parse(target_xliff_path)
            target_root = target_tree.getroot()
        except (FileNotFoundError, ET.ParseError):
            print(f"⚠️ Could not read or parse .xliff for {target_lang_code}, skipping.")
            continue
        
        # --- REFACTORED LOGIC: "Dumb but steady" approach ---
        # Always add ALL source strings to the list to be translated.
        # This overwrites existing translations and ensures everything is processed.
        strings_to_translate = source_strings.copy()
        print(f"Found {len(strings_to_translate)} strings to translate for {target_lang_code}.")

        # Translate concurrently
        translated_strings = {}
        with concurrent.futures.ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
            future_to_key = {
                executor.submit(translate_text_worker, text, target_lang_code, source_lang_code): key
                for key, text in strings_to_translate.items()
            }
            for future in concurrent.futures.as_completed(future_to_key):
                key = future_to_key[future]
                try:
                    translated_text = future.result()
                    if translated_text is not None:
                        translated_strings[key] = translated_text
                        print(f"  -> '{source_strings[key]}' -> '{translated_text}'")
                except Exception as exc:
                    print(f"❌ Exception processing result for key '{key}': {exc}")

        # Update the target .xliff data in memory
        if translated_strings:
            file_was_updated = False
            for file_node in target_root.findall('xliff:file', XLIFF_NAMESPACE):
                if file_node.get('original', '').endswith('Localizable.xcstrings'):
                    for unit_node in file_node.findall('.//xliff:trans-unit', XLIFF_NAMESPACE):
                        key = unit_node.get('id')
                        if key in translated_strings:
                            target_node = unit_node.find('xliff:target', XLIFF_NAMESPACE)
                            if target_node is None:
                                target_node = ET.SubElement(unit_node, 'target')
                            target_node.text = translated_strings[key]
                            # Set the state attribute to indicate it's translated
                            target_node.set('state', 'translated')
                            file_was_updated = True
                    break
            
            # Write the updated data back to the file only if changes were made
            if file_was_updated:
                try:
                    ET.register_namespace('', XLIFF_NAMESPACE['xliff'])
                    target_tree.write(target_xliff_path, encoding='utf-8', xml_declaration=True)
                    print(f"✅ Successfully updated '{target_xliff_path}'.")
                except IOError as e:
                    print(f"❌ Error writing to file: {e}")

def main():
    """Main function to run the script."""
    parser = argparse.ArgumentParser(description="Translate Xcode localization exports (.xcloc folders).")
    parser.add_argument("export_dir", help="The directory containing the exported .xcloc folders.")
    
    args = parser.parse_args()

    if not os.path.isdir(args.export_dir):
        print(f"❌ Error: Export directory not found at '{args.export_dir}'")
        return
        
    process_localization_folder(args.export_dir)

if __name__ == "__main__":
    main()
