Rails.application.routes.draw do
  devise_for :users
  resource :password_change, only: %i[edit update]
  resource :dashboard, only: :show
  resources :school_polls, only: %i[index new create show edit update destroy] do
    resources :test_polls, only: :create, controller: "school_poll_test_polls"
    get :runtime, on: :member
    get :results, on: :member
    post :start, on: :member
    post :stop, on: :member
    post :close, on: :member
    post :reset, on: :member
    post :mock_candidates, on: :member, action: :create_mock_candidates
    resources :contests,
              only: %i[new create edit update destroy],
              controller: "school_poll_contests" do
      resources :options,
                only: %i[new create edit update destroy],
                controller: "school_poll_options"
    end
    resources :poll_sessions,
              only: %i[create destroy],
              controller: "school_poll_sessions" do
      delete :destroy_grade, on: :collection
      post :revote, on: :member
    end
  end
  resources :polls, only: %i[index show new create edit update destroy] do
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
    resources :poll_sessions, only: :show do
      get :results, on: :member
      get :operation_frame, on: :member
      get :ballot_frame, on: :member
      get :runtime_recovery, on: :member
      post :start, on: :member
      get :ballot, on: :member
      patch :mark_current_participant_absent, on: :member
      patch :mark_next_participant_absent, on: :member
      patch :advance_participant, on: :member
      patch :open_ballot, on: :member
      patch :lock_ballot, on: :member
      post :close_ballot_screen, on: :member
      post :submit_ballot, on: :member
      patch :close, on: :member
      patch :stop, on: :member
      post :revote, on: :member
      resource :roster,
               only: %i[edit update],
               controller: "poll_session_rosters"
      resources :contests,
                controller: "classroom_poll_contests",
                only: %i[new create edit update destroy] do
        resources :options,
                  controller: "classroom_poll_options",
                  only: %i[new create edit update destroy]
      end
    end
    resources :poll_options, path: "options", only: %i[new create edit update destroy]
  end
  resources :classrooms, only: %i[index new create edit update] do
    resources :students, controller: "classroom_students", only: %i[index new create edit update] do
      collection do
        get :bulk_new
        post :bulk_create
      end
      member do
        patch :deactivate
        patch :reactivate
      end
    end
  end
  resources :teachers, only: %i[index new create]
  resources :schools, only: %i[index show new create edit update] do
    resources :teacher_memberships,
              path: "teachers",
              controller: "school_teacher_memberships",
              only: %i[index new create destroy] do
      member do
        patch :promote
        patch :demote
      end
    end
  end
  resources :participant_groups, only: %i[index show new create edit update destroy] do
    resources :participant_slots, only: %i[new create edit update destroy]
    resource :bulk_participant_slots, only: %i[new create], controller: "bulk_participant_slots"
    resource :roster, only: %i[edit update], controller: "participant_group_rosters"
  end

  namespace :elections do
    resources :sessions, only: %i[show] do
      get :ballot, on: :member
      post :close_ballot_screen, on: :member
      post :hide_from_teacher, on: :member
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
      get :edit_students, on: :member
      patch :update_students, on: :member
    end
    resources :elections, only: %i[index show new create edit update destroy] do
      get :results, on: :member
      post :start, on: :member
      post :stop, on: :member
      post :close, on: :member
      post :emergency_reset, on: :member
      post :mock_candidates, on: :member, action: :create_mock_candidates
      delete :candidate_photos, on: :member, action: :purge_candidate_photos
      resources :election_sessions, path: "sessions", only: %i[create destroy] do
        post :bulk_create, on: :collection
        delete :destroy_grade, on: :collection
        post :revote, on: :member
      end
      resources :election_contests, path: "contests", only: [] do
        resources :election_candidates, path: "candidates", only: %i[new create edit update destroy]
      end
    end
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
