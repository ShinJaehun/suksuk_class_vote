Rails.application.routes.draw do
  devise_for :users
  resource :dashboard, only: :show
  resources :polls, only: %i[index show new create] do
    get :ballot, on: :member
    post :start, on: :member
    post :submit_vote, on: :member
    post :record_participation_outcome, on: :member
    post :advance_current_participant, on: :member
    post :resume_current_participant, on: :member
    post :close, on: :member
    resources :poll_options, path: "options", only: %i[new create edit update destroy]
  end
  resources :voter_groups, only: %i[index show new create edit update destroy] do
    resources :voter_slots, only: %i[new create edit update destroy]
    resource :bulk_voter_slots, only: %i[new create], controller: "bulk_voter_slots"
  end

  namespace :admin do
    resources :teachers, only: %i[index new create]
  end

  root "dashboards#show"

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
end
