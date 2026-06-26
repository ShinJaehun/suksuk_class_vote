Rails.application.routes.draw do
  devise_for :users
  resource :dashboard, only: :show
  resources :polls, only: %i[index show new create destroy] do
    get :archived, on: :collection
    get :ballot, on: :member
    post :start, on: :member
    post :open_current_participant_ballot, on: :member
    post :submit_vote, on: :member
    post :record_participation_outcome, on: :member
    post :record_next_participant_absent, on: :member
    post :advance_current_participant, on: :member
    post :resume_current_participant, on: :member
    post :close, on: :member
    post :stop, on: :member
    post :archive, on: :member
    resources :poll_options, path: "options", only: %i[new create edit update destroy]
  end
  resources :participant_groups, only: %i[index show new create edit update destroy] do
    resources :participant_slots, only: %i[new create edit update destroy]
    resource :bulk_participant_slots, only: %i[new create], controller: "bulk_participant_slots"
  end

  namespace :elections do
    resources :sessions, only: %i[show] do
      get :ballot, on: :member
      post :start, on: :member
      post :open_ballot, on: :member
      post :lock_ballot, on: :member
      post :advance_voter, on: :member
      post :mark_absent, on: :member
      post :mark_next_absent, on: :member
      post :submit_ballot, on: :member
      post :close, on: :member
    end
  end

  namespace :admin do
    resources :schools, only: %i[new create]
    resources :election_rosters, only: %i[index new create edit update destroy] do
      get :new_bulk, on: :collection
      post :bulk_create, on: :collection
    end
    resources :elections, only: %i[index show new create destroy] do
      get :results, on: :member
      post :start, on: :member
      post :stop, on: :member
      resources :election_sessions, path: "sessions", only: %i[create destroy] do
        post :bulk_create, on: :collection
      end
      resources :election_contests, path: "contests", only: [] do
        resources :election_candidates, path: "candidates", only: %i[new create edit update destroy]
      end
    end
    resources :school_elections, only: %i[index show new create] do
      resources :school_election_classroom_sessions, only: %i[new create] do
        post :create_poll, on: :member
      end
      resources :school_election_contests, only: [] do
        resources :school_election_candidates, only: %i[new create edit update destroy]
      end
    end
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
