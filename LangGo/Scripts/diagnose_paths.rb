#!/usr/bin/env ruby

require 'xcodeproj'

# --- Configuration ---
# The full path to your .xcodeproj file.
project_path = '/Users/James/develop/apple/LangGo/LangGo.xcodeproj'
# ---------------------

puts "--- Diagnostic Script ---"
puts "Attempting to open project: #{project_path}"

# Check if the project file exists
unless File.exist?(project_path)
  puts "🛑 Error: The project file was not found. Please double-check the path."
  exit
end

project = Xcodeproj::Project.open(project_path)

puts "\n✅ Project opened successfully."
puts "Listing all file paths found in the project:"
puts "--------------------------------------------"

# Print the `real_path` for every single file reference in the project
project.files.each do |file|
  puts file.real_path.to_s
end

puts "--------------------------------------------"
puts "Diagnostic complete."
puts "\nACTION: Please check if your file path appears in the list above."
puts "=> /Users/James/develop/apple/LangGo/LangGo/Localizable.xcstrings"