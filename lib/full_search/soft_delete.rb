# frozen_string_literal: true

module FullSearch
  module SoftDelete
    def self.active_update_clause(model)
      dsl = model.full_search_dsl
      return nil unless dsl&.soft_delete_column

      col = model.connection.quote_column_name(dsl.soft_delete_column)
      "WHEN new.#{col} IS NULL"
    end

    def self.soft_delete_remove_clause(model)
      dsl = model.full_search_dsl
      return nil unless dsl&.soft_delete_column

      col = model.connection.quote_column_name(dsl.soft_delete_column)
      "WHEN old.#{col} IS NULL AND new.#{col} IS NOT NULL"
    end

    def self.delete_transition_sql(model)
      active_update_clause(model)
    end
  end
end
