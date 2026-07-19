# frozen_string_literal: true

require "test_helper"

class SchemaDumperPatchTest < ActiveSupport::TestCase
  def setup
    @model = Class.new(Customer) do
      full_search do
        field :first_name, weight: 5
        field :last_name, weight: 5
        filter :account_id, required: true
      end
    end
    @model.table_name = "customers"
    begin
      FullSearch::Index.drop!(@model)
    rescue
      nil
    end
  end

  def teardown
    Customer.delete_all
    ActiveRecord::Base.connection.execute("DROP TABLE IF EXISTS schema_dumper_test_fts;")
  end

  def test_virtual_table_sql_is_single_line
    sql = FullSearch::Index.send(:create_virtual_table_sql, @model)
    lines = sql.split("\n")
    assert_equal 1, lines.length, "Expected single-line SQL, got #{lines.length} lines:\n#{sql}"
    assert_match(/USING fts5\([^)]+\)/, sql)
  end

  def test_trigram_virtual_table_sql_is_single_line
    sql = FullSearch::Index.send(:create_trigram_virtual_table_sql, @model)
    lines = sql.split("\n")
    assert_equal 1, lines.length, "Expected single-line SQL, got #{lines.length} lines:\n#{sql}"
    assert_match(/USING fts5\([^)]+\)/, sql)
  end

  def test_schema_dumper_does_not_crash_with_multi_line_table
    conn = ActiveRecord::Base.connection
    conn.execute("DROP TABLE IF EXISTS schema_dumper_test_fts;")
    conn.execute(<<~SQL)
      CREATE VIRTUAL TABLE schema_dumper_test_fts USING fts5(
        col1,
        col2,
        tokenize='unicode61'
      );
    SQL

    assert_nothing_raised do
      ActiveRecord::SchemaDumper.dump(ActiveRecord::Base.connection_pool, StringIO.new)
    end
  end

  def test_schema_dumper_still_works_with_single_line_tables
    FullSearch::Index.ensure_table!(@model)
    stream = StringIO.new

    assert_nothing_raised do
      ActiveRecord::SchemaDumper.dump(ActiveRecord::Base.connection_pool, stream)
    end

    assert stream.string.include?("create_virtual_table"),
      "Expected schema dumper to include virtual table definitions"
  end

  def test_virtual_tables_skips_unparseable_entries
    conn = ActiveRecord::Base.connection
    conn.execute("DROP TABLE IF EXISTS schema_dumper_test_fts;")
    conn.execute(<<~SQL)
      CREATE VIRTUAL TABLE schema_dumper_test_fts USING fts5(
        col1,
        col2,
        tokenize='unicode61'
      );
    SQL

    tables = conn.virtual_tables
    refute tables.any? { |_, options| options.first.nil? },
      "Should not contain entries with nil module_name"
  end
end
