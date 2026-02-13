Rails.application.routes.draw do
  root 'meals#index'

  resources :grocery_lists do
    collection do
      post :generate
    end
  end
  resources :meals
  resources :household_members
  resources :households
  resources :recipe_imports, only: [:new, :create, :show]

  resources :recipes do
    resources :recipe_ingredients, only: [:create, :destroy]
    resources :recipe_tags, only: [:create, :destroy]
    resources :steps do
      collection do
        post :reorder
      end
    end
    member do
      get :import
    end
  end
  resources :ingredients do
    resources :nutrition_facts, only: [:create, :edit, :update, :destroy]
  end
  resources :tags
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
end
