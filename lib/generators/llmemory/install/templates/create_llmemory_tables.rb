# frozen_string_literal: true

class CreateLlmemoryTables < ActiveRecord::Migration[7.0]
  def change
    create_table :llmemory_resources, id: false do |t|
      t.string :id, null: false, primary_key: true
      t.string :user_id, null: false
      t.text :text, null: false
      t.text :search_tokens
      t.timestamps
    end
    add_index :llmemory_resources, :user_id

    create_table :llmemory_items, id: false do |t|
      t.string :id, null: false, primary_key: true
      t.string :user_id, null: false
      t.string :category, null: false
      t.text :content, null: false
      t.string :source_resource_id
      t.float :importance, default: 0.7
      t.jsonb :provenance
      t.text :search_tokens
      t.datetime :event_date
      t.timestamps
    end
    add_index :llmemory_items, :user_id

    create_table :llmemory_categories do |t|
      t.string :user_id, null: false
      t.string :category_name, null: false
      t.text :content, null: false
      t.datetime :updated_at, null: false
    end
    add_index :llmemory_categories, [:user_id, :category_name], unique: true

    # Episodic long-term memory (trajectories) — JSONB document per episode
    create_table :llmemory_episodes, id: false do |t|
      t.string :id, null: false, primary_key: true
      t.string :user_id, null: false
      t.jsonb :data, null: false, default: {}
      t.text :search_text
      t.text :search_tokens
      t.datetime :archived_at
      t.timestamps
    end
    add_index :llmemory_episodes, :user_id

    # Procedural long-term memory (skill library) — JSONB document per skill
    create_table :llmemory_skills, id: false do |t|
      t.string :id, null: false, primary_key: true
      t.string :user_id, null: false
      t.jsonb :data, null: false, default: {}
      t.text :search_text
      t.text :search_tokens
      t.text :name_det
      t.datetime :archived_at
      t.timestamps
    end
    add_index :llmemory_skills, :user_id

    create_table :llmemory_checkpoints do |t|
      t.string :user_id, null: false
      t.string :session_id, null: false
      t.jsonb :state, null: false, default: {}
      t.timestamps
    end
    add_index :llmemory_checkpoints, [:user_id, :session_id], unique: true

    # Graph-based long-term memory (nodes = entities)
    create_table :llmemory_nodes do |t|
      t.string :user_id, null: false
      t.string :entity_type, null: false
      t.string :name, null: false
      t.jsonb :properties, default: {}
      t.timestamps
    end
    add_index :llmemory_nodes, [:user_id, :entity_type, :name], unique: true

    # Graph-based long-term memory (edges = SPO relations)
    create_table :llmemory_edges do |t|
      t.string :user_id, null: false
      t.references :subject, null: false, foreign_key: { to_table: :llmemory_nodes }
      t.string :predicate, null: false
      t.references :object, null: false, foreign_key: { to_table: :llmemory_nodes }
      t.jsonb :properties, default: {}
      t.datetime :archived_at
      t.timestamps
    end
    add_index :llmemory_edges, [:user_id, :subject_id, :predicate]

    # Vector store for hybrid retrieval (requires pgvector extension)
    enable_extension "vector"
    create_table :llmemory_embeddings do |t|
      t.string :user_id, null: false
      t.string :source_type, null: false
      t.string :source_id, null: false
      t.vector :embedding, limit: 1536
      t.string :embedding_model
      t.integer :embedding_dimensions
      t.text :text_content
      t.timestamps
    end
    add_index :llmemory_embeddings, [:user_id, :source_type, :source_id], unique: true

    create_table :llmemory_traces, id: false do |t|
      t.string :id, null: false, primary_key: true
      t.string :user_id, null: false
      t.string :session_id, null: false
      t.string :boundary_id
      t.bigint :sequence, null: false
      t.string :role, null: false
      t.text :content, null: false
      t.text :search_tokens
      t.string :content_sha256, null: false
      t.datetime :occurred_at, null: false
      t.datetime :ingested_at, null: false
      t.jsonb :metadata, null: false, default: {}
      t.string :idempotency_key
      t.datetime :archived_at
      t.timestamps
    end
    add_index :llmemory_traces, [:user_id, :session_id, :sequence], unique: true
    add_index :llmemory_traces, [:user_id, :idempotency_key], unique: true, where: "idempotency_key IS NOT NULL"
    add_index :llmemory_traces, [:user_id, :session_id, :occurred_at]
    add_index :llmemory_traces, [:user_id, :boundary_id]
    add_index :llmemory_traces, [:user_id, :archived_at]

    create_table :llmemory_trace_state_links do |t|
      t.string :user_id, null: false
      t.string :state_key, null: false
      t.string :trace_id, null: false
      t.datetime :valid_from, null: false
      t.datetime :valid_to
      t.string :supersedes_trace_id
      t.string :source, null: false, default: "explicit"
      t.datetime :created_at, null: false
    end
    add_index :llmemory_trace_state_links, [:user_id, :state_key, :valid_from, :valid_to]
    add_index :llmemory_trace_state_links, :trace_id

    create_table :llmemory_trace_units, id: false do |t|
      t.string :id, null: false, primary_key: true
      t.string :user_id, null: false
      t.string :trace_id, null: false
      t.string :unit_type, null: false
      t.jsonb :data, null: false, default: {}
      t.datetime :archived_at
      t.timestamps
    end
    add_index :llmemory_trace_units, [:user_id, :trace_id]

    create_table :llmemory_trace_entities, id: false do |t|
      t.string :id, null: false, primary_key: true
      t.string :user_id, null: false
      t.string :name, null: false
      t.string :entity_type
      t.datetime :archived_at
      t.timestamps
    end
    add_index :llmemory_trace_entities, [:user_id, :name]

    create_table :llmemory_entity_mentions, id: false do |t|
      t.string :id, null: false, primary_key: true
      t.string :user_id, null: false
      t.string :trace_id, null: false
      t.string :entity_id, null: false
      t.integer :offset_start
      t.integer :offset_end
      t.datetime :archived_at
      t.timestamps
    end
    add_index :llmemory_entity_mentions, [:user_id, :trace_id]
  end
end
