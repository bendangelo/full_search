# frozen_string_literal: true

require "rails"

module FullSearch
  class Railtie < Rails::Railtie
    rake_tasks do
      load File.expand_path("../tasks/full_search.rake", __dir__)
    end

    initializer "full_search.ensure_tables" do
      config.after_initialize do
        next unless FullSearch.config.auto_rebuild_schema
        ActiveSupport.on_load(:active_record) do
          FullSearch.models.each do |model|
            FullSearch::Index.rebuild_if_needed!(model)
          end
        end
      end
    end
  end
end
