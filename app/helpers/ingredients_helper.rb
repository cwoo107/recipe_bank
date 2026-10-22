module IngredientsHelper
  # Each family's tag colors, spelled out in full so Tailwind finds the
  # classes (it can't see ones built by interpolation). The families
  # themselves live in Ingredient::FAMILIES.
  FAMILY_TAG_CLASSES = {
    'protein'    => 'bg-mauve-300 text-mauve-600 inset-ring-mauve-600/20 dark:bg-mauve-800/20 dark:text-mauve-300 dark:inset-ring-mauve-300/30',
    'produce'    => 'bg-mist-300 text-mist-600 inset-ring-mist-600/20 dark:bg-mist-800/20 dark:text-mist-300 dark:inset-ring-mist-300/30',
    'dairy'      => 'bg-taupe-300 text-taupe-600 inset-ring-taupe-600/20 dark:bg-taupe-800/20 dark:text-taupe-300 dark:inset-ring-taupe-300/30',
    'grain'      => 'bg-honey-300 text-honey-600 inset-ring-honey-600/20 dark:bg-honey-800/20 dark:text-honey-300 dark:inset-ring-honey-300/30',
    'fat'        => 'bg-terracotta-300 text-terracotta-600 inset-ring-terracotta-600/20 dark:bg-terracotta-800/20 dark:text-terracotta-300 dark:inset-ring-terracotta-300/30',
    'spices'     => 'bg-sage-300 text-sage-700 inset-ring-sage-600/20 dark:bg-sage-800/20 dark:text-sage-300 dark:inset-ring-sage-300/30',
    'condiments' => 'bg-dusty-rose-300 text-dusty-rose-700 inset-ring-dusty-rose-600/20 dark:bg-dusty-rose-800/20 dark:text-dusty-rose-300 dark:inset-ring-dusty-rose-300/30',
    'canned'     => 'bg-olive-300 text-olive-700 inset-ring-olive-600/20 dark:bg-olive-800/20 dark:text-olive-300 dark:inset-ring-olive-300/30',
    'baking'     => 'bg-amber-100 text-amber-700/80 inset-ring-amber-600/15 dark:bg-amber-800/15 dark:text-amber-200/70 dark:inset-ring-amber-300/20',
    'nuts'       => 'bg-orange-100 text-orange-800/70 inset-ring-orange-700/15 dark:bg-orange-900/15 dark:text-orange-200/70 dark:inset-ring-orange-300/20',
    'frozen'     => 'bg-seafoam-300 text-seafoam-700 inset-ring-seafoam-600/20 dark:bg-seafoam-800/20 dark:text-seafoam-300 dark:inset-ring-seafoam-300/30',
    'beverages'  => 'bg-sky-100 text-sky-700/80 inset-ring-sky-600/15 dark:bg-sky-800/15 dark:text-sky-200/70 dark:inset-ring-sky-300/20',
    'grocery'    => 'bg-stone-200 text-stone-600 inset-ring-stone-600/20 dark:bg-stone-700/30 dark:text-stone-300 dark:inset-ring-stone-300/30'
  }.freeze
  UNKNOWN_FAMILY_TAG_CLASSES = 'bg-gray-200 text-gray-600 inset-ring-gray-600/20 dark:bg-white/10 dark:text-gray-300 dark:inset-ring-white/20'

  def ingredient_family_tag(family)
    return content_tag(:span, '—', class: 'text-gray-400 text-xs') if family.blank?

    colors = FAMILY_TAG_CLASSES.fetch(family.downcase, UNKNOWN_FAMILY_TAG_CLASSES)
    content_tag(:span, Ingredient.family_label(family), class: "inline-flex items-center rounded-full px-2 py-1 text-xs font-medium inset-ring #{colors}")
  end

  # The <option>s for an ingredient picker: the household's ingredients and
  # the catalog's it doesn't have yet (Ingredient.pickable_for).
  def ingredient_picker_options(household, selected = nil)
    options_for_select(
      Ingredient.pickable_for(household).map { |ingredient|
        [ ingredient.ingredient, ingredient.id, { 'data-favorite' => ingredient.favorite } ]
      },
      selected
    )
  end

  def ingredient_family_options
    Ingredient::FAMILIES.map { |key, config| [config[:label], key] }
  end

  def ingredient_family_select(form, options = {})
    form.select :family,
                ingredient_family_options,
                { prompt: 'Select a family' },
                { class: options[:class] || "block w-full rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-[#5f734c] sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:focus:outline-[#7a8f62]" }
  end
end