module MarketingHelper
  # The feature pages, for the marketing navbar's menu and the footer.
  def marketing_feature_links
    [
      [ "Meal planning",   feature_meal_planning_path ],
      [ "Grocery lists",   feature_grocery_lists_path ],
      [ "Recipe bank",     feature_recipes_path ],
      [ "Plan your week",  feature_plan_week_path ],
      [ "To-do lists",     feature_todos_path ],
      [ "Chore chart",     feature_chores_path ],
      [ "Restock list",    feature_restock_path ],
      [ "Shared calendar", feature_calendar_path ]
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
  # has one — see marketing:screenshots) on screens narrower than sm.
  def marketing_screenshot(image, alt:, mobile_image: nil)
    img = image_tag(image, alt:, class: "w-full h-auto rounded-xl", loading: "lazy")
    return img unless mobile_image

    tag.picture { tag.source(media: "(max-width: 639px)", srcset: image_path(mobile_image)) + img }
  end
end
