module MarketingHelper
  # The feature pages, for the marketing navbar's menu and the footer.
  def marketing_feature_links
    [
      [ "Plan your week",  feature_plan_week_path ],
      [ "Shared calendar", feature_calendar_path ],
      [ "Meal planning",   feature_meal_planning_path ],
      [ "Recipe bank",     feature_recipes_path ],
      [ "Restock list",    feature_restock_path ],
      [ "Grocery lists",   feature_grocery_lists_path ],
      [ "Chore chart",     feature_chores_path ],
      [ "To-do lists",     feature_todos_path ]
    ]
  end

  # The marketing pages' sign-up buttons. Before launch (Launch) sign-up is
  # closed, so they point at the launch mailing list instead.
  def signup_cta(label = "Get started", closed_label: "Join the launch list", **options)
    if Launch.registrations_open?
      link_to label, new_user_registration_path, **options
    else
      link_to closed_label, root_path(anchor: "launch-list"), **options
    end
  end

  # A screenshot of the app, swapped for its phone-sized version (when it
  # has one — see marketing:screenshots) on screens narrower than sm, and
  # for its "-dark" version when the page is in dark mode. The theme is the
  # "dark" class on <html> (layouts/_theme), not the device setting, so both
  # are in the page and CSS shows one; the hidden one is lazy, so it never loads.
  def marketing_screenshot(image, alt:, mobile_image: nil)
    screenshot_picture(image, mobile_image, alt:, theme_class: "dark:hidden") +
      screenshot_picture(dark_screenshot(image), mobile_image && dark_screenshot(mobile_image), alt:, theme_class: "hidden dark:block")
  end

  private

  def screenshot_picture(image, mobile_image, alt:, theme_class:)
    img = image_tag(image, alt:, class: "w-full h-auto rounded-xl #{theme_class}", loading: "lazy")
    return img unless mobile_image

    tag.picture { tag.source(media: "(max-width: 639px)", srcset: image_path(mobile_image)) + img }
  end

  # "marketing/chores.webp" → "marketing/chores-dark.webp"
  def dark_screenshot(image) = image.sub(/(\.\w+)\z/, '-dark\1')
end
