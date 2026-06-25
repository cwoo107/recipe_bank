Rails.application.routes.draw do
  devise_for :users

  root 'meals#index'

  get 'grocery_list', to: 'grocery_lists#index', as: 'grocery_lists'
  resources :grocery_lists, except: :index do
    collection do
      post :generate
    end
  end

  resources :meals
  resources :household_members
  resources :households
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

  get "up" => "rails/health#show", as: :rails_health_check
end