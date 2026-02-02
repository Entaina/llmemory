# frozen_string_literal: true

Llmemory::Dashboard::Engine.routes.draw do
  root to: "users#index"
  get "u/:user_id", to: "users#show", as: :user
  get "u/:user_id/short_term", to: "short_term#show", as: :user_short_term
  get "u/:user_id/long_term", to: "long_term#index", as: :user_long_term
  get "u/:user_id/long_term/categories", to: "long_term#categories", as: :user_long_term_categories
  get "u/:user_id/graph", to: "graph#index", as: :user_graph
  get "u/:user_id/stats", to: "stats#index", as: :user_stats
  get "search", to: "search#index", as: :search
end
