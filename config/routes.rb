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

  # Cognitive memory (CoALA) surface
  get  "u/:user_id/episodic", to: "episodic#index", as: :user_episodic
  post "u/:user_id/episodic/forget", to: "episodic#forget", as: :forget_user_episodic
  get  "u/:user_id/procedural", to: "procedural#index", as: :user_procedural
  post "u/:user_id/procedural/forget", to: "procedural#forget", as: :forget_user_procedural
  get  "u/:user_id/working/:session_id", to: "working#show", as: :user_working
  get  "u/:user_id/reflection", to: "reflection#show", as: :user_reflection
  post "u/:user_id/reflection/run", to: "reflection#run", as: :run_user_reflection
  get  "u/:user_id/forget_log", to: "forget_log#show", as: :user_forget_log
  get  "u/:user_id/maintenance", to: "maintenance#show", as: :user_maintenance
  post "u/:user_id/maintenance/run", to: "maintenance#run", as: :run_user_maintenance
  post "u/:user_id/maintenance/mine", to: "maintenance#mine", as: :mine_user_maintenance
  post "u/:user_id/maintenance/register", to: "maintenance#register", as: :register_user_maintenance
end
