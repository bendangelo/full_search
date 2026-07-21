# frozen_string_literal: true

require "rails/generators"

module FullSearch
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      class_option :skip_prepare, type: :boolean, default: false,
        desc: "Skip automatic full_search:prepare"

      def create_initializer
        template "full_search.rb", "config/initializers/full_search.rb"
      end

      def prepare_indexes
        return if options[:skip_prepare]

        say "Running full_search:prepare to create FTS tables..."
        rake("full_search:prepare")
      rescue => e
        say "Skipping full_search:prepare — #{e.message}", :yellow
        say "Run `bin/rails full_search:prepare` after your database is ready.", :yellow
      end
    end
  end
end
