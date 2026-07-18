# frozen_string_literal: true

module FullSearch
  module SoftDelete
    def self.delete_transition_sql(model)
      dsl = model.full_search_dsl
      return nil unless dsl&.soft_delete_column

      "WHEN new.#{dsl.soft_delete_column} IS NULL"
    end
  end
end
