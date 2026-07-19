# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"
require "standard/rake"

Bundler::GemHelper.install do |helper|
  helper.signing_key = ENV['GEM_SIGNING_KEY'] || '~/.gem/gem-private_key.pem'
end

Rake::TestTask.new(:test) do |t|
  t.libs << "lib"
  t.libs << "test"
  t.test_files = FileList["test/**/*_test.rb"]
  t.warning = false
end

task default: [:test, :standard]
