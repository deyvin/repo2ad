Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  resources :projects, only: %i[new create show] do
    resource :audience, only: %i[show update]
    resource :results, only: :show # §2 Resultado (TR)
    resources :creatives, only: [] do
      resource :regeneration, only: :create # "Gerar de novo" (T11)
    end
  end

  scope :higgsfield, controller: :higgsfield_connections do
    get :connect, action: :new, as: :connect_higgsfield
    get :callback, as: :higgsfield_callback
    delete :connection, action: :destroy, as: :higgsfield_connection
  end
  resource :balance, only: :show

  root "projects#new"
end
