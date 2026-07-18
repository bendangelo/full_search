# frozen_string_literal: true

require_relative "lib/full_search/version"

Gem::Specification.new do |spec|
  spec.name = "full_search"
  spec.version = FullSearch::VERSION
  spec.authors = ["Wenmar Pro"]
  spec.summary = "SQLite FTS5 full-text search for Rails/ActiveRecord"
  spec.description = "Declarative full-text search for Rails apps backed by SQLite FTS5"
  spec.homepage = "https://github.com/wenmar/full_search"
  spec.license = "MIT"

  spec.required_ruby_version = ">= 4.0.0"

  spec.files = Dir["lib/**/*", "README.md", "LICENSE"]
  spec.require_paths = ["lib"]

  spec.add_dependency "activerecord", ">= 8.0"
  spec.add_dependency "railties", ">= 8.0"
  spec.add_dependency "sqlite3", ">= 2.0"

  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "rake", "~> 13.0"
end
