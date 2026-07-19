# frozen_string_literal: true

require "test_helper"

class FullSearch::ConfigTest < ActiveSupport::TestCase
  def teardown
    FullSearch.instance_variable_set(:@config, FullSearch::Config.new)
  end

  def test_default_values
    assert_equal false, FullSearch.config.auto_rebuild_schema
    assert_equal :raise, FullSearch.config.stale_query_behavior
    assert_equal true, FullSearch.config.lock_rebuilds
    assert_equal true, FullSearch.config.default_async_reindex
    assert_equal "unicode61", FullSearch.config.default_tokenizer
  end

  def test_configure_block
    FullSearch.configure do |config|
      config.auto_rebuild_schema = true
      config.default_tokenizer = "porter"
    end

    assert_equal true, FullSearch.config.auto_rebuild_schema
    assert_equal "porter", FullSearch.config.default_tokenizer
  end

  def test_auto_rebuild_schema_deprecation_backward_compat
    FullSearch.config.auto_rebuild_schema = true
    assert_equal true, FullSearch.config.auto_rebuild_schema
  end
end
