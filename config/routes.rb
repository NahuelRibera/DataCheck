Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  root "dashboard#show"

  resources :companies, only: [:index, :show]

  resources :import_runs, only: [:index, :show, :new, :create] do
    member do
      post :preflight
      post :dry_run
      post :execute
    end
  end

  namespace :api do
    namespace :v1 do
      resources :import_runs, only: [:index, :show] do
        member do
          get :issues
          post :preflight
          post :dry_run
          post :execute
          get :verification
        end
      end
    end
  end

  post "/graphql", to: "graphql#execute"
end
