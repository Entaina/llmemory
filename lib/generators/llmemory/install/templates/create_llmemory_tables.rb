# frozen_string_literal: true

class CreateLlmemoryTables < ActiveRecord::Migration[7.0]
  def change
    create_table :llmemory_resources, id: false do |t|
      t.string :id, null: false, primary_key: true
      t.string :user_id, null: false
      t.text :text, null: false
      t.timestamps
    end
    add_index :llmemory_resources, :user_id

    create_table :llmemory_items, id: false do |t|
      t.string :id, null: false, primary_key: true
      t.string :user_id, null: false
      t.string :category, null: false
      t.text :content, null: false
      t.string :source_resource_id
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

    create_table :llmemory_checkpoints do |t|
      t.string :user_id, null: false
      t.string :session_id, null: false
      t.jsonb :state, null: false, default: {}
      t.timestamps
    end
    add_index :llmemory_checkpoints, [:user_id, :session_id], unique: true
  end
end
