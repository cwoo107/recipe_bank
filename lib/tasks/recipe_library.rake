# lib/tasks/recipe_library.rake
#
# The public recipe library (Recipe::LibraryImport). Load the ingredient
# catalog first — the recipes draw on it:
#
#   bin/rails ingredients:import_catalog APPLY=1
#   bin/rails recipes:import_library                        # dry run of db/recipe_library.json
#   bin/rails recipes:import_library VERBOSE=1              # list recipes already there too
#   bin/rails recipes:import_library APPLY=1                # save
#   bin/rails recipes:import_library FILE=tmp/more.json
#   bin/rails recipes:import_library REFRESH=1              # also rewrite library recipes that differ from the file
namespace :recipes do
  desc "Import the public recipe library (dry run unless APPLY=1; FILE=path, REFRESH=1, VERBOSE=1)"
  task import_library: :environment do
    apply  = ENV["APPLY"] == "1"
    path   = ENV["FILE"].presence || Rails.root.join("db/recipe_library.json").to_s
    import = Recipe::LibraryImport.new(path, refresh: ENV["REFRESH"] == "1")
    rows   = import.rows

    puts apply ? "Applying changes." : "Dry run — nothing will be saved. Re-run with APPLY=1 to apply."
    puts "File: #{path} (#{rows.size} recipes)"
    puts "Library account: #{Recipe::LibraryImport::LIBRARY_EMAIL} (#{import.library_user ? 'exists' : 'will be created'})"
    puts

    labels = { create: "create ", update: "update ", unchanged: "same   ", invalid: "SKIP   " }
    rows.each do |row|
      next if row.action == :unchanged && row.changes.empty? && ENV["VERBOSE"] != "1"

      differs = row.action == :unchanged && row.changes.any? ? " (differs from the file — REFRESH=1 to update)" : ""
      puts format("  %s %s%s", labels[row.action], row.title.inspect, differs)
      puts "          ~ #{row.changes.join(', ')}" if row.changes.any?
      row.problems.each { |problem| puts "          ✗ #{problem}" }
    end
    puts

    created = apply ? import.apply! : 0

    counts = rows.group_by(&:action).transform_values(&:size)
    puts "Summary#{' (dry run — nothing saved)' unless apply}:"
    puts format("  %-26s %d", apply ? "created or updated" : "to create", apply ? created : counts.fetch(:create, 0))
    puts format("  %-26s %d", "to update", counts.fetch(:update, 0)) unless apply
    puts format("  %-26s %d", "already in the library", counts.fetch(:unchanged, 0))
    puts format("  %-26s %d", "skipped as invalid (✗)", counts.fetch(:invalid, 0))
  end
end
