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

      ids = []
      relation.find_each do |record|
        dsl.exact_matches.each do |em|
          value = record.instance_exec(&em.source)
          ids << record.id if value.to_s.casecmp?(cleaned)
        end
      end
      ids.uniq
    end
  end
end
