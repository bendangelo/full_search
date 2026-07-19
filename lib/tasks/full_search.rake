# frozen_string_literal: true

def resolve_full_search_models(args)
  if args[:models]
    args[:models].split(",").map do |name|
      klass = begin
        name.singularize.camelize.constantize
      rescue
        nil
      end
      klass || FullSearch.models.find { |m| m.table_name == name }
    end.compact
  else
    FullSearch.models
  end
end

namespace :full_search do
  desc "Rebuild indexes when DSL has changed (checks config hash; safe for production)"
  task :rebuild, [:models] => :environment do |_t, args|
    Rails.application.eager_load!

    resolve_full_search_models(args).each do |model|
      if FullSearch::Index.rebuild_if_needed!(model)
        puts "Rebuilt #{FullSearch::Index.fts_table_name(model)}"
      else
        puts "#{FullSearch::Index.fts_table_name(model)} is current"
      end
    end
  end

  desc "Force reset indexes (drops and recreates all FTS tables)"
  task :reset, [:models] => :environment do |_t, args|
    Rails.application.eager_load!

    resolve_full_search_models(args).each do |model|
      FullSearch::Index.rebuild!(model)
      puts "Reset #{FullSearch::Index.fts_table_name(model)}"
    end
  end

  desc "Optimize full_search indexes"
  task optimize: :environment do
    Rails.application.eager_load!
    FullSearch.optimize!
    FullSearch.models.each do |model|
      puts "Optimized #{FullSearch::Index.fts_table_name(model)}"
    end
  end

  desc "Show full_search index status"
  task status: :environment do
    Rails.application.eager_load!
    FullSearch.models.each do |model|
      stored = FullSearch::Index.stored_config_hash(model)
      current = model.full_search_dsl.config_hash
      status = (stored == current) ? "ok" : "stale"
      source_fields = model.full_search_dsl.fields.select(&:source).map(&:name)

      drift_info = if source_fields.any?
        conn = ActiveRecord::Base.connection
        qc = ->(name) { conn.quote_column_name(name) }
        qt = ->(name) { conn.quote_table_name(name) }
        empty_count = ActiveRecord::Base.connection.execute(<<~SQL).first["c"]
          SELECT COUNT(*) AS c
          FROM #{qt.call(FullSearch::Index.fts_table_name(model))}
          WHERE #{source_fields.map { |c| "#{qc.call(c)} = ''" }.join(" OR ")}
        SQL
        " | empty source fields: #{empty_count}"
      else
        ""
      end

      puts "#{model.table_name}: #{status}#{drift_info}"
    end
  end
end
