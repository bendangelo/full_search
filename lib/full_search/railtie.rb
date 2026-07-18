# frozen_string_literal: true

require "rails"

module FullSearch
  class Railtie < Rails::Railtie
    rake_tasks do
      load File.expand_path("../tasks/full_search.rake", __dir__)
    end

    initializer "full_search.ensure_tables" do
      config.after_initialize do
        next unless FullSearch.config.auto_manage_schema
        ActiveSupport.on_load(:active_record) do
          FullSearch.models.each do |model|
            FullSearch::Index.ensure_table!(model)
            next unless FullSearch.config.auto_manage_schema == true

            stored = FullSearch::Index.stored_config_hash(model)
            if stored && stored != model.full_search_dsl.config_hash
              FullSearch::Index.rebuild!(model)
            end
          end
        end
      end
    end
  end
end
