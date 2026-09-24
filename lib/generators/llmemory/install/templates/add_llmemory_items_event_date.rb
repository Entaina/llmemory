# frozen_string_literal: true

class AddLlmemoryItemsEventDate < ActiveRecord::Migration[7.0]
  def change
    add_column :llmemory_items, :event_date, :datetime unless column_exists?(:llmemory_items, :event_date)
  end
end
