# frozen_string_literal: true

require "test_helper"
require "rails/generators"
require "generators/full_search/install/install_generator"

class FullSearch::Generators::InstallGeneratorTest < Rails::Generators::TestCase
  tests FullSearch::Generators::InstallGenerator
  destination File.expand_path("../tmp/generator", __dir__)
  setup :prepare_destination

  def test_creates_initializer
    generator = generator_class.new([], {}, destination_root: destination_root)
    generator.stub :rake, nil do
      generator.invoke_all
    end

    assert_file "config/initializers/full_search.rb" do |content|
      assert_match(/FullSearch\.configure/, content)
      assert_match(/auto_rebuild_schema/, content)
    end
  end

  def test_skips_prepare_when_flag_given
    run_generator ["--skip-prepare"]

    assert_file "config/initializers/full_search.rb"
  end
end
