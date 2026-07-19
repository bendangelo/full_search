# frozen_string_literal: true

namespace :full_search do
  desc "Rebuild full_search indexes"
  task :rebuild, [:models] => :environment do |_t, args|
    Rails.application.eager_load!

    models = if args[:models]
               args[:models].split(",").map do |name|
                 klass = name.singularize.camelize.constantize rescue nil
                 klass || FullSearch.models.find { |m| m.table_name == name }
               end.compact
             else
               FullSearch.models
             end

    models.each do |model|
      FullSearch::Index.rebuild!(model)
      puts "Rebuilt #{FullSearch::Index.fts_table_name(model)}"
    end
  end

  desc "Optimize full_search indexes"
  task optimize: :environment do
    Rails.application.eager_load!
    FullSearch.models.each do |model|
      FullSearch::Index.optimize!(model)
      puts "Optimized #{FullSearch::Index.fts_table_name(model)}"
    end
  end

  desc "Show full_search index status"
  task status: :environment do
    Rails.application.eager_load!
    FullSearch.models.each do |model|
      stored = FullSearch::Index.stored_config_hash(model)
      current = model.full_search_dsl.config_hash
      status = stored == current ? "ok" : "stale"
      source_fields = model.full_search_dsl.fields.select(&:source).map(&:name)

      drift_info = if source_fields.any?
        empty_count = ActiveRecord::Base.connection.execute(<<~SQL).first["c"]
          SELECT COUNT(*) AS c
          FROM #{FullSearch::Index.fts_table_name(model)}
          WHERE #{source_fields.map { |c| "#{c} = ''" }.join(' OR ')}
        SQL
        " | empty source fields: #{empty_count}"
      else
        ""
      end

      puts "#{model.table_name}: #{status}#{drift_info}"
    end
  end
end
