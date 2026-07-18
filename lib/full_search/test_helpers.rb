# frozen_string_literal: true

module FullSearch
  module TestHelpers
    def rebuild_full_search_index(model_name)
      model = model_name.is_a?(Class) ? model_name : model_name.to_s.camelize.constantize
      FullSearch::Index.drop!(model)
      FullSearch::Index.rebuild!(model)
    end

    def ensure_full_search_tables
      FullSearch.models.each do |model|
        FullSearch::Index.ensure_table!(model)
      end
    end
  end
end
