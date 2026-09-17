# frozen_string_literal: true

class CreateLlmemoryZeroMemTables < ActiveRecord::Migration[7.0]
  def change
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
    add_index :llmemory_traces, [:user_id, :session_id, :sequence], unique: true, name: "idx_llmemory_traces_user_session_sequence"
    add_index :llmemory_traces, [:user_id, :idempotency_key], unique: true, where: "idempotency_key IS NOT NULL",
              name: "idx_llmemory_traces_user_idempotency"
    add_index :llmemory_traces, [:user_id, :session_id, :occurred_at], name: "idx_llmemory_traces_user_session_occurred"
    add_index :llmemory_traces, [:user_id, :boundary_id], name: "idx_llmemory_traces_user_boundary"
    add_index :llmemory_traces, [:user_id, :archived_at], name: "idx_llmemory_traces_user_archived"

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
    add_index :llmemory_trace_state_links, [:user_id, :state_key, :valid_from, :valid_to],
              name: "idx_llmemory_trace_state_links_validity"
    add_index :llmemory_trace_state_links, :trace_id, name: "idx_llmemory_trace_state_links_trace"

    # Reserved for ZM2/ZM3 — created now to avoid chained migrations later.
    create_table :llmemory_trace_units, id: false do |t|
      t.string :id, null: false, primary_key: true
      t.string :user_id, null: false
      t.string :trace_id, null: false
      t.string :unit_type, null: false
      t.jsonb :data, null: false, default: {}
      t.datetime :archived_at
      t.timestamps
    end
    add_index :llmemory_trace_units, [:user_id, :trace_id], name: "idx_llmemory_trace_units_user_trace"

    create_table :llmemory_trace_entities, id: false do |t|
      t.string :id, null: false, primary_key: true
      t.string :user_id, null: false
      t.string :name, null: false
      t.string :entity_type
      t.datetime :archived_at
      t.timestamps
    end
    add_index :llmemory_trace_entities, [:user_id, :name], name: "idx_llmemory_trace_entities_user_name"

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
    add_index :llmemory_entity_mentions, [:user_id, :trace_id], name: "idx_llmemory_entity_mentions_user_trace"
  end
end
