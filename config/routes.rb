Rails.application.routes.draw do
  devise_for :users, controllers: { sessions: "users/sessions" }
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
      post :confirm_automatic_advance, on: :member
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
  end
  resources :classrooms, only: %i[index new create edit update destroy] do
    collection do
      get :bulk_setup
      get :bulk_new
      post :bulk_create
      patch :bulk_update
      patch :bulk_operation
    end
    member do
      patch :deactivate
      patch :reactivate
    end
    resources :students, controller: "classroom_students", only: %i[index new create edit update] do
      collection do
        get :bulk_new
        post :bulk_create
        get :bulk_edit
        patch :bulk_update
      end
      member do
        patch :deactivate
        patch :reactivate
      end
    end
  end
  resources :teachers, only: %i[index new create destroy] do
    collection do
      get :bulk_setup
      get :bulk_new
      post :bulk_create
      patch :bulk_update
      patch :bulk_operation
    end
    member do
      patch :deactivate
      patch :reactivate
      get :temporary_password
      post :issue_temporary_password
    end
  end
  resources :schools, only: %i[index show new create edit update destroy] do
    patch :manager, on: :member, action: :update_manager
    member do
      patch :deactivate
      patch :reactivate
    end
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
  namespace :admin do
    resources :schools, only: %i[new create]
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
