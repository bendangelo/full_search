# frozen_string_literal: true

module FullSearch
  class ExactMatch
    def self.ids_for(model, query, filters)
      dsl = model.full_search_dsl
      return [] if dsl.exact_matches.empty?

      cleaned = query.to_s.strip
      return [] if cleaned.empty?

      relation = model.all
      filters.each { |name, value| relation = relation.where(name => value) }

      conditions = dsl.exact_matches.map do |em|
        relation.model.arel_table[em.name].eq(cleaned)
      end

      relation.where(conditions.reduce(:or)).pluck(:id)
    end
  end
end
