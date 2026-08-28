Rails.application.routes.draw do
  devise_for :users

  root 'static_pages#home'

  get "dashboard", to: "dashboard#show", as: :dashboard

  get   "plan-week",          to: "plan_week#start", as: :plan_week
  get   "plan-week/:section", to: "plan_week#show",  as: :plan_week_step
  patch "plan-week/:section", to: "plan_week#update"

  get 'pricing', to: 'static_pages#pricing'
  get 'features/meal-planning', to: 'static_pages#meal_planning', as: :feature_meal_planning
  get 'features/grocery-lists', to: 'static_pages#grocery_lists', as: :feature_grocery_lists
  get 'features/recipes',       to: 'static_pages#recipes',       as: :feature_recipes
  get 'features/todos',         to: 'static_pages#todos',         as: :feature_todos
  get 'features/calendar',      to: 'static_pages#calendar',      as: :feature_calendar

  get 'grocery_list', to: 'grocery_lists#index', as: 'grocery_lists'
  # `create`'s default path helper (grocery_lists_path) would collide with the
  # `grocery_lists` alias claimed above for the custom index route, so create
  # gets its own explicit name instead.
  resources :grocery_lists, except: [:index, :create] do
    collection do
      post :generate
    end
  end
  post 'grocery_lists', to: 'grocery_lists#create', as: :create_grocery_list

  resources :meals
  resources :recurring_meals, only: [:index, :edit, :update, :destroy]
  resource  :household                           # singular resource — index doesn't exist for these
  resources :household_members, except: :show   # scoped by current_household, not URL

  resources :recipe_imports, only: [:new, :create, :show] do
    collection do
      post :create_from_file
    end
  end

  resources :recipes do
    resources :recipe_ingredients, only: [:create, :destroy]
    resources :recipe_tags, only: [:create, :destroy]
    resources :steps do
      collection do
        post :reorder
      end
    end
    member do
      patch :toggle_favorite
      get :import
    end
  end

  resources :collections do
    member do
      get :add_recipe_dropdown  # Turbo Frame dropdown for a specific recipe
    end
  end

  resources :collection_recipes, only: [:create]
  delete 'collection_recipes', to: 'collection_recipes#destroy', as: :collection_recipes_destroy

  resources :ingredients do
    resources :nutrition_facts, only: [:create, :edit, :update, :destroy]
    member do
      patch :toggle_favorite
    end
  end

  resources :tags

  resources :todos do
    collection do
      post :reorder
    end
    member do
      post :move
    end
  end

  resources :chores
  resources :weekly_chores, only: [ :index, :create, :update, :destroy ] do
    collection do
      post :reorder
    end
    member do
      post :move
    end
  end

  resources :calendar_sources do
    member do
      patch :toggle_visible
      post  :sync
    end
    collection do
      post :reorder
    end
  end

  resources :calendar_events

  # Named routes for the three calendar views
  get  "calendar",                       to: "calendars#index",  as: :calendars
  get  "calendar/month/:year/:month",    to: "calendars#month",  as: :month_calendars
  get  "calendar/week",                  to: "calendars#week",   as: :week_calendars
  get  "calendar/day",                   to: "calendars#day",    as: :day_calendars

  get "up" => "rails/health#show", as: :rails_health_check
end
