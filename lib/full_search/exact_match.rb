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

      exact_ids = dsl.exact_matches.flat_map do |em|
        value = exact_match_value(em, cleaned)
        next [] if value.nil? || value.to_s.empty?

        relation.where(em.name => value).pluck(:id)
      end

      exact_ids.uniq
    end

    def self.exact_match_value(em, query)
      fake = Object.new
      fake.define_singleton_method(em.name) { query }
      fake.instance_exec(&em.source)
    end
  end
end
