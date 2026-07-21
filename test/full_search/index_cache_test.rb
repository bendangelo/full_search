# frozen_string_literal: true

require "test_helper"

class FullSearch::IndexCacheTest < ActiveSupport::TestCase
  def setup
    FullSearch::IndexCache.clear!
  end

  def teardown
    FullSearch::IndexCache.clear!
  end

  def test_fetch_caches_value_within_with_cache
    calls = 0
    FullSearch::IndexCache.with_cache do
      2.times do
        FullSearch::IndexCache.fetch("key") { calls += 1; "value" }
      end
    end
    assert_equal 1, calls
  end

  def test_fetch_runs_block_without_cache
    calls = 0
    value = FullSearch::IndexCache.fetch("key") { calls += 1; "value" }
    assert_equal "value", value
    assert_equal 1, calls
  end

  def test_with_cache_is_safe_to_nest
    outer = nil
    inner = nil
    FullSearch::IndexCache.with_cache do
      outer = FullSearch::IndexCache.fetch("x") { "outer" }
      FullSearch::IndexCache.with_cache do
        inner = FullSearch::IndexCache.fetch("x") { "inner" }
      end
    end
    assert_equal "outer", outer
    assert_equal "outer", inner
  end

  def test_clear_resets_cache
    calls = 0
    FullSearch::IndexCache.with_cache do
      FullSearch::IndexCache.fetch("key") { calls += 1; "value" }
      FullSearch::IndexCache.clear!
      FullSearch::IndexCache.fetch("key") { calls += 1; "value2" }
    end
    assert_equal 2, calls
  end
end
