# lib/tasks/ingredients.rake
namespace :ingredients do
  desc "Give every recipe its own household's copy of each ingredient (dry run unless APPLY=1)"
  task localize: :environment do
    apply = ENV['APPLY'] == '1'
    stats = Hash.new(0)
    households = {}

    puts apply ? "Applying changes." : "Dry run — nothing will be saved. Re-run with APPLY=1 to apply."

    ActiveRecord::Base.transaction do
      # Recipes are re-homed into their owner's household, so every owner
      # needs one (the app provisions these lazily on first request).
      User.where(id: Recipe.select(:user_id)).find_each do |user|
        next if user.household

        user.create_owned_household!(family_name: Household.default_family_name_for(user))
        stats[:households_provisioned] += 1
      end

      # Same as the migration's backfill, for anything created since.
      Ingredient.where(household_id: nil).where.not(created_by_id: nil).includes(:created_by).find_each do |ingredient|
        household = ingredient.created_by&.household
        next unless household

        ingredient.update_columns(household_id: household.id)
        stats[:ingredients_assigned] += 1
      end

      RecipeIngredient.includes(:ingredient, recipe: :user).find_each do |line|
        user      = line.recipe.user
        household = user && (households[user.id] ||= user.household)
        unless household
          puts "  skipped: \"#{line.recipe.title}\" (recipe ##{line.recipe_id}) has no owner to re-home it to"
          stats[:recipe_lines_skipped] += 1
          next
        end
        next if line.ingredient.household_id == household.id

        copy = line.ingredient.copy_for(household, user: user)
        stats[copy.previously_new_record? ? :ingredients_copied : :ingredients_reused] += 1

        puts "  #{household.family_name}: \"#{line.recipe.title}\" — #{line.ingredient.ingredient} " \
             "##{line.ingredient_id} → ##{copy.id}#{' (new copy)' if copy.previously_new_record?}"

        line.update!(ingredient: copy)
        stats[:recipe_lines_repointed] += 1
      end

      # Grocery rows follow their household's copy where one now exists, so
      # the list keeps working if the original's owner deletes it.
      GroceryList.includes(:ingredient).find_each do |row|
        next if row.ingredient.household_id == row.household_id

        copy = Ingredient.find_by(household_id: row.household_id, source_ingredient_id: row.ingredient_id)
        next unless copy

        row.update_columns(ingredient_id: copy.id)
        stats[:grocery_rows_repointed] += 1
      end

      raise ActiveRecord::Rollback unless apply
    end

    remaining = RecipeIngredient.includes(:ingredient, recipe: :user).count do |line|
      line.recipe.user && line.ingredient.household_id != line.recipe.user.household&.id
    end

    puts
    puts "Summary#{' (dry run — rolled back)' unless apply}:"
    %i[households_provisioned ingredients_assigned recipe_lines_repointed
       ingredients_copied ingredients_reused grocery_rows_repointed recipe_lines_skipped].each do |key|
      puts format("  %-24s %d", key.to_s.tr('_', ' '), stats[key])
    end
    puts "  recipe lines still using another household's ingredient: #{remaining}"
  end

  # Cleans up names mangled by recipe imports (". finely parmesan", "/8 tsp
  # black pepper", "Vegetable or canola oil") and merges the duplicates that
  # turn up once they're clean. See IngredientNameNormalizer for the rules
  # and Ingredient::NameAudit for how merges work. New imports get the same
  # cleanup as they're parsed (IngredientParser#parse).
  #
  #   bin/rails ingredients:normalize_names                 # audit only
  #   bin/rails ingredients:normalize_names HOUSEHOLD=12    # one household
  #   bin/rails ingredients:normalize_names CSV=tmp/ingredient_audit.csv
  #   bin/rails ingredients:normalize_names APPLY=1         # save the changes
  desc "Audit and clean up ingredient names, merging duplicates (dry run unless APPLY=1; HOUSEHOLD=id, CSV=path)"
  task normalize_names: :environment do
    apply     = ENV['APPLY'] == '1'
    household = ENV['HOUSEHOLD'].presence && Household.find(ENV['HOUSEHOLD'])
    audit     = Ingredient::NameAudit.new(household: household)
    changes   = audit.changes

    puts apply ? "Applying changes." : "Dry run — nothing will be saved. Re-run with APPLY=1 to apply."
    puts "Scope: #{household ? "#{household.family_name} (household ##{household.id})" : 'every household'}"
    puts

    if changes.empty?
      puts "Every ingredient name already looks clean."
      next
    end

    labels = { rename: "rename", merge: "merge ", review: "check " }
    changes.group_by { |change| change.ingredient.household }.each do |owner, owner_changes|
      puts owner ? "#{owner.family_name} (household ##{owner.id})" : "Shared catalog (no household)"
      owner_changes.sort_by { |change| [ change.ingredient.ingredient.downcase, change.kind.to_s ] }.each do |change|
        target =
          case change.kind
          when :merge  then "merge into ##{change.into.id} \"#{change.to_name}\""
          when :rename then "\"#{change.to_name}\""
          else "(left as is)"
          end
        puts format("  %s  #%-6d %-45s → %s", labels[change.kind], change.ingredient.id, change.ingredient.ingredient.inspect, target)
        change.notes.each { |note| puts "             ! #{note}" }
      end
      puts
    end

    if (path = ENV['CSV'].presence)
      require 'csv'
      CSV.open(path, 'w') do |csv|
        csv << %w[action household_id ingredient_id current_name new_name merge_into_id notes]
        changes.each do |change|
          csv << [ change.kind, change.ingredient.household_id, change.ingredient.id, change.ingredient.ingredient,
                   change.to_name, change.into&.id, change.notes.join('; ') ]
        end
      end
      puts "Wrote #{changes.size} rows to #{path}"
    end

    audit.apply! if apply

    counts = changes.group_by(&:kind).transform_values(&:size)
    puts "Summary#{' (dry run — nothing saved)' unless apply}:"
    puts format("  %-30s %d", "renamed", counts.fetch(:rename, 0))
    puts format("  %-30s %d", "merged into another", counts.fetch(:merge, 0))
    puts format("  %-30s %d", "flagged to check by hand (!)", changes.count { |change| change.notes.any? })
  end

  # Tidies how units are written on recipe lines and nutrition facts —
  # "Tablespoons", "Tbsp", "T" all become the picker's "tbsp" — and flags
  # units the picker doesn't offer. Amounts are never changed. See UnitAudit.
  #
  #   bin/rails ingredients:normalize_units                 # audit only
  #   bin/rails ingredients:normalize_units HOUSEHOLD=12    # one household
  #   bin/rails ingredients:normalize_units CSV=tmp/unit_audit.csv
  #   bin/rails ingredients:normalize_units APPLY=1         # save the changes
  desc "Audit and clean up how units are written (dry run unless APPLY=1; HOUSEHOLD=id, CSV=path)"
  task normalize_units: :environment do
    apply     = ENV['APPLY'] == '1'
    household = ENV['HOUSEHOLD'].presence && Household.find(ENV['HOUSEHOLD'])
    audit     = UnitAudit.new(household: household)
    changes   = audit.changes

    puts apply ? "Applying changes." : "Dry run — nothing will be saved. Re-run with APPLY=1 to apply."
    puts "Scope: #{household ? "#{household.family_name} (household ##{household.id})" : 'every household'}"
    puts

    if changes.empty?
      puts "Every unit is already written the picker's way."
      next
    end

    shown = ->(unit) { unit.nil? ? "(no unit)" : unit.inspect }
    changes.group_by(&:source).each do |source, source_changes|
      puts source.label.capitalize
      source_changes.sort_by { |change| [ change.kind.to_s, change.from.downcase ] }.each do |change|
        label  = change.update? ? "update" : "check "
        target = change.update? ? shown.(change.to) : "(left as is)"
        puts format("  %s  %-22s → %-12s %5d", label, change.from.inspect, target, change.count)
        change.notes.each { |note| puts "          ! #{note}" }
      end
      puts
    end

    if (path = ENV['CSV'].presence)
      require 'csv'
      CSV.open(path, 'w') do |csv|
        csv << %w[action table current_unit new_unit rows notes]
        changes.each do |change|
          csv << [ change.kind, change.source.model.table_name, change.from, change.to, change.count, change.notes.join('; ') ]
        end
      end
      puts "Wrote #{changes.size} rows to #{path}"
    end

    audit.apply! if apply

    updates = changes.select(&:update?)
    puts "Summary#{' (dry run — nothing saved)' unless apply}:"
    puts format("  %-30s %d (%d rows)", "units rewritten", updates.size, updates.sum(&:count))
    puts format("  %-30s %d (%d rows)", "flagged to check by hand (!)", changes.count { |change| !change.update? },
                changes.reject(&:update?).sum(&:count))
  end

  # Loads the shared ingredient catalog from a CSV — see
  # Ingredient::CatalogImport for the columns and how rows are matched.
  # Re-running after editing the file updates what changed.
  #
  #   bin/rails ingredients:import_catalog                       # dry run of db/ingredients.csv
  #   bin/rails ingredients:import_catalog FILE=tmp/more.csv
  #   bin/rails ingredients:import_catalog VERBOSE=1             # list unchanged rows too
  #   bin/rails ingredients:import_catalog APPLY=1               # save
  desc "Import the shared ingredient catalog from a CSV (dry run unless APPLY=1; FILE=path, VERBOSE=1)"
  task import_catalog: :environment do
    apply  = ENV['APPLY'] == '1'
    path   = ENV['FILE'].presence || Rails.root.join('db/ingredients.csv').to_s
    import = Ingredient::CatalogImport.new(path)

    begin
      rows = import.rows
    rescue Ingredient::CatalogImport::HeaderError => e
      abort "#{path}: #{e.message}"
    end

    puts apply ? "Applying changes." : "Dry run — nothing will be saved. Re-run with APPLY=1 to apply."
    puts "File: #{path} (#{rows.size} rows)"
    puts

    labels = { create: "create ", update: "update ", unchanged: "same   ", invalid: "SKIP   " }
    rows.each do |row|
      next if row.action == :unchanged && row.notes.empty? && ENV['VERBOSE'] != '1'

      detail =
        if row.update?
          (row.attributes.merge(row.nutrition)).map { |attribute, value| "#{attribute}=#{value.inspect}" }.join(', ')
        end
      puts format("  %s line %-4d %-40s %s", labels[row.action], row.line, row.name.to_s.inspect, detail)
      row.problems.each { |problem| puts "                   ✗ #{problem}" }
      row.notes.each { |note| puts "                   ! #{note}" }
    end
    puts

    import.apply! if apply

    counts = rows.group_by(&:action).transform_values(&:size)
    puts "Summary#{' (dry run — nothing saved)' unless apply}:"
    puts format("  %-30s %d", "created", counts.fetch(:create, 0))
    puts format("  %-30s %d", "updated", counts.fetch(:update, 0))
    puts format("  %-30s %d", "already up to date", counts.fetch(:unchanged, 0))
    puts format("  %-30s %d", "skipped as invalid (✗)", counts.fetch(:invalid, 0))
    puts format("  %-30s %d", "with notes to check (!)", rows.count { |row| row.notes.any? })
  end
end
