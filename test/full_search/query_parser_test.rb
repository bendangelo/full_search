# frozen_string_literal: true

require "test_helper"

class FullSearch::QueryParserTest < ActiveSupport::TestCase
  def test_simple_terms
    parsed = FullSearch::QueryParser.parse("honda civic")
    assert_equal [:and, [[:term, "honda"], [:term, "civic"]]], parsed
  end

  def test_phrase
    parsed = FullSearch::QueryParser.parse('"exact phrase"')
    assert_equal [:phrase, "exact phrase"], parsed
  end

  def test_exclusion
    parsed = FullSearch::QueryParser.parse("honda -civic")
    assert_equal [:and, [[:term, "honda"], [:exclude, "civic"]]], parsed
  end

  def test_or
    parsed = FullSearch::QueryParser.parse("honda OR civic")
    assert_equal [:or, [[:term, "honda"], [:term, "civic"]]], parsed
  end

  def test_mixed
    parsed = FullSearch::QueryParser.parse('"honda civic" OR toyota -camry')
    assert_equal [
      :or, [
        [:phrase, "honda civic"],
        [:and, [[:term, "toyota"], [:exclude, "camry"]]]
      ]
    ], parsed
  end

  def test_empty
    assert_equal [], FullSearch::QueryParser.parse("")
  end

  def test_long_query_is_rejected
    assert_raises(FullSearch::InvalidQueryError) do
      FullSearch::QueryParser.parse("a" * 5000)
    end
  end

  def test_query_with_null_bytes_is_rejected
    assert_raises(FullSearch::InvalidQueryError) do
      FullSearch::QueryParser.parse("foo\0bar")
    end
  end

  def test_leading_or_returns_single_term
    parsed = FullSearch::QueryParser.parse("OR foo")
    assert_equal [:term, "foo"], parsed
  end

  def test_trailing_or_returns_single_term
    parsed = FullSearch::QueryParser.parse("foo OR")
    assert_equal [:term, "foo"], parsed
  end
end
