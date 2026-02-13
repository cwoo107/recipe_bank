module IngredientsHelper
  INGREDIENT_FAMILIES = {
    'protein' => { color: 'mauve', label: 'Protein' },
    'vegetable' => { color: 'mist', label: 'Vegetable' },
    'fruit' => { color: 'taupe', label: 'Fruit' },
    'grain' => { color: 'honey', label: 'Grain' },
    'fat' => { color: 'terracotta', label: 'Fat' }
  }.freeze

  def ingredient_family_tag(family)
    return content_tag(:span, '—', class: 'text-gray-400 text-xs') if family.blank?

    config = INGREDIENT_FAMILIES[family.downcase] || { color: 'gray', label: family }
    color = config[:color]
    label = config[:label]

    content_tag(:span, label, class: "inline-flex items-center rounded-full bg-#{color}-300 px-2 py-1 text-xs font-medium text-#{color}-600 inset-ring inset-ring-#{color}-600/20 dark:bg-#{color}-800/20 dark:text-#{color}-300 dark:inset-ring-#{color}-300/30")
  end

  def ingredient_family_options
    INGREDIENT_FAMILIES.map { |key, config| [config[:label], key] }
  end

  def ingredient_family_select(form, options = {})
    form.select :family,
                ingredient_family_options,
                { prompt: 'Select a family' },
                { class: options[:class] || "block w-full rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-[#5f734c] sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:focus:outline-[#7a8f62]" }
  end
end