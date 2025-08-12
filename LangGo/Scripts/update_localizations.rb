#!/usr/bin/env ruby

require 'xcodeproj'

# --- Configuration ---
# The absolute paths below are based on the directory structure you provided.

# 1. The full path to your .xcodeproj file.
project_path = '/Users/James/develop/apple/LangGo/LangGo.xcodeproj'

# 2. The full path to the file you want to localize.
#    Note: We are now targeting the correct 'Localizable.xcstrings' file.
file_to_localize_path = '/Users/James/develop/apple/LangGo/LangGo/Localizable.xcstrings'

# 3. List of language codes to add.
languages_to_add = ['fr', 'ja', 'ko', 'vi']
# ---------------------

# --- Script Logic (No changes needed below) ---

# Check if the project file actually exists at the path you provided.
unless File.exist?(project_path)
  puts "🛑 Error: The project file was not found at the specified path:"
  puts "=> #{project_path}"
  puts "Please double-check that this path is correct and the file exists."
  exit
end

# Open the Xcode project.
project = Xcodeproj::Project.open(project_path)

# Find the file reference using its absolute path.
file_reference = project.files.find { |f| f.real_path.to_s == file_to_localize_path }

if file_reference.nil?
  puts "🛑 Error: Could not find a reference in the project for the file:"
  puts "=> #{file_to_localize_path}"
  puts "Please ensure the file is added to your Xcode project and its path is correct."
  exit
end

# Find the variant group associated with the file. This group holds all language versions.
variant_group = project.variant_groups.find { |vg| vg.files.include?(file_reference) }

if variant_group.nil?
  puts "🛑 Error: The file '#{File.basename(file_to_localize_path)}' is not yet localized for any language."
  puts "Please localize it for your base language (e.g., English) first within Xcode."
  exit
end

# Add a new file variant for each language.
languages_to_add.each do |lang_code|
  unless variant_group.files.find { |f| f.name == lang_code }
    # Create a new reference for the language.
    variant_group.new_variant(lang_code, :group)
    puts "Added localization for '#{lang_code}' to #{File.basename(file_to_localize_path)}"
  else
    puts "Localization for '#{lang_code}' already exists. Skipping."
  end
end

# Save the changes to the project file.
project.save

puts "\n✅ Project updated successfully!"