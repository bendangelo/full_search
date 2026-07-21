# frozen_string_literal: true

module FullSearch
  class ExactMatch
    def self.ids_for(model, query, filters)
      dsl = model.full_search_dsl
      return [] if dsl.exact_matches.empty?

      cleaned = query.to_s.strip
      return [] if cleaned.empty?

      sql_matches = dsl.exact_matches.select(&:sql)
      ruby_matches = dsl.exact_matches.reject(&:sql)

      ids = []

      if sql_matches.any?
        base = model.all
        filters.each { |name, value| base = base.where(name => value) }

        conditions = sql_matches.map do |em|
          value = em.normalize ? em.normalize.call(cleaned) : cleaned
          "(#{em.sql}) = #{model.connection.quote(value)}"
        end.join(" OR ")

        ids += base.where(conditions).pluck(:id)
      end

      if ruby_matches.any?
        base = model.all
        filters.each { |name, value| base = base.where(name => value) }

        base.find_each do |record|
          ruby_matches.each do |em|
            value = record.instance_exec(&em.source)
            ids << record.id if value.to_s.casecmp?(cleaned)
          end
        end
      end

      ids.uniq
    end
  end
end
