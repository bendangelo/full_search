# frozen_string_literal: true

require_relative "lib/full_search/version"

Gem::Specification.new do |spec|
  spec.name = "full_search"
  spec.version = FullSearch::VERSION
  spec.authors = ["Ben D'Angelo"]
  spec.summary = "SQLite FTS5 full-text search for Rails/ActiveRecord"
  spec.description = "Declarative full-text search for Rails apps backed by SQLite FTS5"
  spec.homepage = "https://github.com/bendangelo/full_search"
  spec.license = "MIT"

  spec.required_ruby_version = ">= 3.1.0"
  spec.required_rubygems_version = ">= 2.0"

  spec.cert_chain = ["cert/full_search.pem"]
  spec.signing_key = "cert/priv_key.pem" if File.exist?("cert/priv_key.pem")

  spec.files = Dir["lib/**/*", "README.md", "LICENSE"]
  spec.executables = []
  spec.require_paths = ["lib"]

  spec.add_dependency "activerecord", ">= 8.0"
  spec.add_dependency "railties", ">= 8.0"
  spec.add_dependency "sqlite3", ">= 2.0"
  spec.add_dependency "ostruct", ">= 0.6"


  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "rake", "~> 13.0"

  spec.add_development_dependency "irb"
  spec.add_development_dependency "standard", "~> 1.40"
end
