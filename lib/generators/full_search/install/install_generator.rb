# frozen_string_literal: true

require "rails/generators"

module FullSearch
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      def create_initializer
        template "full_search.rb", "config/initializers/full_search.rb"
      end
    end
  end
end
