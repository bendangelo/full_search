# frozen_string_literal: true

namespace :full_search do
  desc "Rebuild full_search indexes"
  task :rebuild, [:models] => :environment do |_t, args|
    models = if args[:models]
               args[:models].split(",").map { |name| name.camelize.constantize }
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
    FullSearch.models.each do |model|
      FullSearch::Index.optimize!(model)
      puts "Optimized #{FullSearch::Index.fts_table_name(model)}"
    end
  end

  desc "Show full_search index status"
  task status: :environment do
    FullSearch.models.each do |model|
      stored = FullSearch::Index.stored_config_hash(model)
      current = model.full_search_dsl.config_hash
      status = stored == current ? "ok" : "stale"
      puts "#{model.table_name}: #{status} (stored=#{stored}, current=#{current})"
    end
  end
end
