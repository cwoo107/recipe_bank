Rails.application.routes.draw do
  devise_for :users, controllers: { registrations: "users/registrations" }

  # Before launch: beta invite links open sign-up; everyone else can join the
  # launch mailing list.
  get  "beta/:token", to: "beta_invites#show", as: :beta_invite
  resources :launch_subscribers, only: :create, path: "launch-list"
  get  "launch-list/unsubscribe/:token", to: "launch_subscribers#unsubscribe", as: :unsubscribe_launch_list

  root 'static_pages#home'

  get "dashboard", to: "dashboard#show", as: :dashboard

  # Printable week plan: /print/new to choose, /print.pdf to download
  resource :week_print, only: %i[new show], path: "print"

  get    "plan-week",          to: "plan_week#start", as: :plan_week
  delete "plan-week",          to: "plan_week#close"
  get   "plan-week/:section", to: "plan_week#show",  as: :plan_week_step
  patch "plan-week/:section", to: "plan_week#update"

  get 'pricing', to: 'static_pages#pricing'
  get 'features/meal-planning', to: 'static_pages#meal_planning', as: :feature_meal_planning
  get 'features/grocery-lists', to: 'static_pages#grocery_lists', as: :feature_grocery_lists
  get 'features/recipes',       to: 'static_pages#recipes',       as: :feature_recipes
  get 'features/todos',         to: 'static_pages#todos',         as: :feature_todos
  get 'features/calendar',      to: 'static_pages#calendar',      as: :feature_calendar
  get 'features/restock',       to: 'static_pages#restock',       as: :feature_restock
  get 'features/chores',        to: 'static_pages#chores',        as: :feature_chores
  get 'features/plan-your-week', to: 'static_pages#plan_week',    as: :feature_plan_week

  get 'grocery_list', to: 'grocery_lists#index', as: 'grocery_lists'
  # `create`'s default path helper (grocery_lists_path) would collide with the
  # `grocery_lists` alias claimed above for the custom index route, so create
  # gets its own explicit name instead.
  resources :grocery_lists, except: [:index, :create] do
    collection do
      post :generate
      patch :check_all
      delete :destroy_checked
    end
  end
  post 'grocery_lists', to: 'grocery_lists#create', as: :create_grocery_list

  # "Upload Receipt" on the grocery list: read a receipt photo, review the
  # matches (and which week), then check those items off.
  resources :receipt_scans, only: %i[new create show update], path: "receipts" do
    member do
      post :apply
    end
  end

  resources :meals do
    collection do
      get :week_stats
    end
    member do
      post :move
    end
  end
  resource  :preferences, only: :update
  resource  :theme, only: :update               # the light/dark/system switch — signed in or not
  resources :recurring_meals, only: [:index, :edit, :update, :destroy]
  resource  :household do                        # singular resource — index doesn't exist for these
    patch :adjust_servings
    resource :recipe_export, only: :show           # the owner's PDF of every household recipe
  end

  # Plan & billing actions — the section itself is on the household page.
  resource :billing, only: [] do
    post :checkout
    get  :complete                               # back from Stripe Checkout
    post :portal
    post :dismiss_trial_banner
  end
  resources :household_members, except: :index do # scoped by current_household, not URL
    member do
      patch :update_password
      post  :send_password_reset
    end
  end

  resources :recipe_imports, only: [:new, :create, :show] do
    collection do
      post :create_from_file
    end
    member do
      post :confirm_ingredients
    end
  end

  resources :recipes do
    resources :recipe_ingredients, only: [:create, :update, :destroy]
    resources :recipe_components, only: [:create, :update, :destroy]
    resources :recipe_tags, only: [:create, :destroy]
    resource  :print, only: :show, controller: "recipe_prints" # /recipes/:id/print.pdf
    resources :steps do
      collection do
        post :reorder
      end
    end
    member do
      patch :toggle_favorite
      patch :toggle_visibility
      get :import
      post :save_to_household
      post :duplicate
      post :reorder_instructions
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
      patch :plan
    end
  end
  resources :todo_tags, only: [ :index, :create, :update, :destroy ]
  resources :stores,    only: [ :index, :create, :update, :destroy ]
  # The household's time for to-dos, changed from the board or "Plan your week".
  resource :todo_budget, only: :update

  resources :restock_items do
    collection do
      post :reorder
    end
    member do
      post  :move
      patch :mark_stocked
      patch :mark_restock
    end
  end

  resources :restock_categories, only: [ :new, :create, :edit, :update, :destroy ] do
    collection do
      post :reorder
    end
  end

  resources :chore_categories, only: [ :new, :create, :edit, :update, :destroy ] do
    collection do
      post :reorder
    end
  end
  resources :chores do
    collection do
      delete :destroy_selected
    end
    resources :chore_tasks, only: [ :create, :update, :destroy ]
  end
  # The template library: ready-made categories of chores to copy onto the chart.
  resources :chore_templates, only: :index, path: "chore-templates" do
    member do
      post :add
    end
  end
  resources :weekly_chores, only: [ :index, :create, :update, :destroy ] do
    collection do
      post :reorder
    end
    member do
      post :move
    end
  end

  resources :calendar_sources, except: %i[index show] do
    member do
      patch :toggle_visible
      post  :sync
    end
    collection do
      post :reorder
      post :sync_all
    end
  end

  resources :calendar_events

  # Named routes for the three calendar views
  get  "calendar",                       to: "calendars#index",  as: :calendars
  get  "calendar/month/:year/:month",    to: "calendars#month",  as: :month_calendars
  get  "calendar/week",                  to: "calendars#week",   as: :week_calendars
  get  "calendar/day",                   to: "calendars#day",    as: :day_calendars

  post "stripe/webhooks", to: "stripe_webhooks#create", as: :stripe_webhooks

  # Staff only (users.app_admin) — see Admin::BaseController.
  namespace :admin do
    root to: "households#index"
    resources :households, only: %i[index show] do
      resource :trial_extension, only: :create
      resource :comp, only: %i[create destroy]
    end
    # :id is the recipe's — featuring is just a flag on it.
    resources :featured_recipes, only: %i[index create destroy]
    resources :beta_invites,     only: %i[index create destroy]
    resources :launch_subscribers, only: :index
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
