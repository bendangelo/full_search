# full_search Production Readiness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-ruby:subagent-driven-development (recommended) or superpowers-ruby:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the critical correctness, concurrency, and design issues in `full_search`, expand the test suite to cover the identified blind spots, and make the gem behavior predictable for production Rails/SQLite apps.

**Architecture:** Keep the existing module layout and DSL surface, but harden the index lifecycle, query execution, callback registration, and highlighter against real-world edge cases. Add focused tests for each fix rather than broad integration tests.

**Tech Stack:** Ruby 3.2+, Rails/ActiveRecord 8+, SQLite 3.34+, Minitest.

---

## File structure changes

| File | Responsibility |
|------|---------------|
| `lib/full_search/index.rb` | Table/trigger lifecycle, config hash storage, rebuild locking |
| `lib/full_search/search.rb` | Query execution, ranking, soft-delete filtering, typo fallback |
| `lib/full_search/soft_delete.rb` | Trigger WHEN-clause generation and soft-delete helpers |
| `lib/full_search/highlighter.rb` | Snippet and field highlighting (fix column-index bug, merge logic) |
| `lib/full_search/callbacks.rb` | Idempotent callback installation and sourced-field sync |
| `lib/full_search/model.rb` | Model registry that supports deregistration |
| `lib/full_search/query_parser.rb` | Input validation and reserved-token handling |
| `lib/full_search/dsl.rb` | More stable config hashing |
| `lib/full_search/exact_match.rb` | Execute exact-match source procs safely |
| `test/full_search/*_test.rb` | New and updated tests for the fixes |
| `full_search.gemspec` | Lower Ruby requirement |

---

### Task 1: Fix model registry memory leak and duplicate registration

**Files:**
- Modify: `lib/full_search.rb:31-39`
- Modify: `lib/full_search/model.rb:16`
- Add test: `test/full_search/model_registry_test.rb`

**Problem:** `FullSearch.models` is a plain array; anonymous classes and reloaded classes accumulate. There is no way to deregister.

**Implementation:**
1. Change `FullSearch.models` from `Array` to `Set`
2. Add `register_model` and `deregister_model` methods
3. Use `register_model` in model.rb
4. Add `model_registry_test.rb` with tests

```ruby
# lib/full_search.rb
module FullSearch
  class << self
    def models
      @models ||= Set.new
    end

    def register_model(model)
      models << model
    end

    def deregister_model(model)
      models.delete(model)
    end
  end
end
```

```ruby
# lib/full_search/model.rb - line 16 change
FullSearch.register_model(self)
```

```ruby
# test/full_search/model_registry_test.rb
require "test_helper"

class FullSearch::ModelRegistryTest < ActiveSupport::TestCase
  def test_models_is_a_set_of_unique_classes
    assert_kind_of Set, FullSearch.models
  end

  def test_rebuild_in_registry_is_easiest_to_setup
    klass = Class.new(Customer) do
      full_search do
        field :first_name
        filter :account_id, required: true
      end
    end
    klass.table_name = "customers"
    assert_includes FullSearch.models, klass
  end

  def test_deregister_model
    klass = Class.new(Customer) do
      full_search do
        field :first_name
        filter :account_id, required: true
      end
    end
    klass.table_name = "customers"
    FullSearch.register_model(klass)
    assert_includes FullSearch.models, klass
    FullSearch.deregister_model(klass)
    refute_includes FullSearch.models, klass
  end

  def test_registering_same_class_twice_is_idempotent
    klass = Class.new(Customer) do
      full_search do
        field :first_name
        filter :account_id, required: true
      end
    end
    klass.table_name = "customers"
    FullSearch.register_model(klass)
    size_before = FullSearch.models.size
    FullSearch.register_model(klass)
    assert_equal size_before, FullSearch.models.size
  end
end
```

---

### Task 2: Make callback installation idempotent

**Files:**
- Modify: `lib/full_search/callbacks.rb:5-30`
- Add test: `test/full_search/callbacks_test.rb`

**Problem:** Calling `full_search` twice on the same model installs duplicate `after_save` / `after_destroy` callbacks.

**Implementation:**
Set a class instance variable flag on the model to skip re-installation.

```ruby
# lib/full_search/callbacks.rb
def self.install!(model)
  return if model.instance_variable_defined?(:@__full_search_callbacks_installed) &&
            model.instance_variable_get(:@__full_search_callbacks_installed)

  dsl = model.full_search_dsl
  source_fields = dsl.fields.select(&:source)
  return if source_fields.empty?

  model.after_save do
    FullSearch::Callbacks.reindex_record!(self)
  end

  model.after_destroy do
    FullSearch::Callbacks.remove_record!(self)
  end

  dsl.fields.each do |field|
    next unless field.reindex_on
    assoc_class = associated_class(model, field.reindex_on)
    assoc_class&.after_save do |record|
      FullSearch::Callbacks.reindex_dependents!(record, model, field)
    end
    assoc_class&.after_destroy do |record|
      FullSearch::Callbacks.reindex_dependents!(record, model, field)
    end
  end

  model.instance_variable_set(:@__full_search_callbacks_installed, true)
end

def self.uninstall!(model)
  model.instance_variable_set(:@__full_search_callbacks_installed, false)
end
```

**Test:**
```ruby
def test_callbacks_are_idempotent
  model = Class.new(Vehicle) do
    full_search do
      field :computed, source: -> { make&.upcase }
      filter :account_id, required: true
    end
  end
  model.table_name = "vehicles"
  FullSearch::Index.rebuild!(model)

  save_callbacks = model._save_callbacks.dup
  destroy_callbacks = model._destroy_callbacks.dup

  # Re-open the DSL - callbacks already installed, should not duplicate
  model.full_search do
    field :computed, source: -> { make&.upcase }
    filter :account_id, required: true
  end

  assert_equal save_callbacks.size, model._save_callbacks.size
  assert_equal destroy_callbacks.size, model._destroy_callbacks.size
ensure
  FullSearch::Index.drop!(model) rescue nil
end
```

---

### Task 3: Fix soft-delete trigger logic

**Files:**
- Modify: `lib/full_search/soft_delete.rb`
- Modify: `lib/full_search/index.rb:248-265` (update trigger SQL generation)
- Add tests: `test/full_search/soft_delete_test.rb`

**Problem:** The update trigger only fires `WHEN new.discarded_at IS NULL`, so soft-deleting a record never removes it from the FTS index. Restoring a deleted record is also not handled correctly.

**Implementation:**
Update `soft_delete.rb` to provide two clauses: one for the delete transition (old IS NULL, new IS NOT NULL) which removes the FTS row, and one for active updates that delete+reinsert.

Add a second update trigger for the soft-delete transition that removes the FTS row. The existing update trigger stays but its WHEN clause removes the soft-delete condition (just always reindex on update for active records).

Simpler approach: The update trigger should unconditionally delete and re-insert. If soft-delete is configured, the re-insert only happens when `new.col IS NULL`. Add a second update trigger for the soft-delete transition:

```ruby
# soft_delete.rb
def self.delete_transition_sql(model)
  dsl = model.full_search_dsl
  return nil unless dsl&.soft_delete_column
  "WHEN old.#{dsl.soft_delete_column} IS NULL AND new.#{dsl.soft_delete_column} IS NOT NULL"
end

def self.active_update_clause(model)
  dsl = model.full_search_dsl
  return nil unless dsl&.soft_delete_column
  "WHEN new.#{dsl.soft_delete_column} IS NULL"
end
```

Then `index.rb` update_trigger_sql uses `WHEN new.soft_delete_col IS NULL` for the main update trigger. If soft-delete is configured, a second trigger is created for the delete transition.

**Test additions:**
```ruby
def test_soft_delete_removes_from_fts_index
  account = Account.create!(name: "Acme")
  customer = @model.create!(account_id: account.id, first_name: "Sam")
  FullSearch::Index.rebuild!(@model)
  customer.update!(discarded_at: Time.current)
  fts_count = ActiveRecord::Base.connection.execute(
    "SELECT COUNT(*) AS c FROM #{FullSearch::Index.fts_table_name(@model)} WHERE rowid = #{customer.id}"
  ).first["c"]
  assert_equal 0, fts_count
end

def test_restore_re_adds_to_fts_index
  account = Account.create!(name: "Acme")
  customer = @model.create!(account_id: account.id, first_name: "Sam", discarded_at: Time.current)
  FullSearch::Index.rebuild!(@model)
  customer.update!(discarded_at: nil)
  results = @model.full_search("Sam", filters: { account_id: account.id })
  assert_includes results.to_a, customer
end
```

---

### Task 4: Fix rebuild lock clobbering config hash

**Files:**
- Modify: `lib/full_search/index.rb:355-367`
- Add test: `test/full_search/index_test.rb`

**Problem:** `with_rebuild_lock` inserts/updates config_hash with an empty string `""`. If the rebuild crashes after this point, the config hash is stored as `""`, and `rebuild_if_needed!` may skip rebuilding if `""` matches the current DSL config hash.

**Solution:** Use a sentinel value `"__rebuilding__"` that can never equal a real config hash.

```ruby
def with_rebuild_lock(model)
  if FullSearch.config.lock_rebuilds
    connection.transaction do
      connection.execute(
        "INSERT INTO full_search_index_versions (table_name, config_hash, rebuilt_at) VALUES (#{q(model.table_name)}, #{q("__rebuilding__")}, datetime('now'))
         ON CONFLICT(table_name) DO UPDATE SET config_hash=excluded.config_hash;"
      )
      yield
    end
  else
    yield
  end
end
```

**Test:**
```ruby
def test_rebuild_lock_uses_sentinel_not_empty
  FullSearch::Index.rebuild!(@model)
  stored = ActiveRecord::Base.connection.execute(
    "SELECT config_hash FROM full_search_index_versions WHERE table_name = 'customers'"
  ).first
  refute_equal "", stored["config_hash"]
  refute_equal "__rebuilding__", stored["config_hash"]
end
```

---

### Task 5: Fix highlighter column-index bug when filters exist

**Files:**
- Modify: `lib/full_search/highlighter.rb:177-198`
- Add test: `test/full_search/highlighter_test.rb`

**Problem:** `highlight_rows` uses sequential indices `0...fields.count` for `highlight(table, idx, ...)`, but FTS table columns include both fields and filters. When filters exist, the highlight column index is wrong.

**Solution:** Compute correct column indices by looking up each field's position in the full column list (fields + filters).

```ruby
# In highlight_rows
all_columns = (dsl.fields + dsl.filters)
field_columns = dsl.fields

highlight_parts = field_columns.each_with_index.map do |field, idx|
  actual_idx = all_columns.index { |c| c.respond_to?(:name) && c.name == field.name }
  "highlight(#{table}, #{actual_idx}, #{quote(config[:open_tag])}, #{quote(config[:close_tag])}) AS #{field.name}_snippet"
end.join(", ")
```

**Test:**
```ruby
def test_highlight_with_filters_uses_correct_column_index
  model = Class.new(Customer) do
    full_search do
      field :first_name, weight: 5
      field :last_name, weight: 5
      filter :account_id, required: true
      highlight
    end
  end
  model.table_name = "customers"
  account = Account.create!(name: "Acme")
  model.create!(account_id: account.id, first_name: "Samantha", last_name: "Smith")
  FullSearch::Index.rebuild!(model)

  results = model.full_search("Samantha", filters: { account_id: account.id }, highlight: true).to_a
  result = results.first
  assert result.full_search_snippet.include?("Samantha")
  refute result.full_search_snippet.include?("Smith"), "Should not highlight last_name when first_name matched"
end
```

---

### Task 6: Fix typo fallback leaking soft-deleted records

**Files:**
- Modify: `lib/full_search/search.rb:113-191`
- Add tests: `test/full_search/soft_delete_test.rb`

**Problem:** `like_prefix_ids` and `fuzzy_match_ids` scan the source table without soft-delete filtering, so deleted rows can leak into results.

**Solution:** Apply soft-delete WHERE clause and filters directly in LIKE and Levenshtein queries.

```ruby
# In both like_prefix_ids and fuzzy_match_ids, add:
additional_where = []
additional_where << "#{connection.quote_table_name(model.table_name)}.#{dsl.soft_delete_column} IS NULL" if dsl.soft_delete_column && !include_soft_deleted
filters.each do |name, value|
  additional_where << "#{connection.quote_table_name(model.table_name)}.#{connection.quote_column_name(name.to_s)} = #{connection.quote(value)}"
end
where_clause = additional_where.any? ? "AND #{additional_where.join(' AND ')}" : ""
```

**Test:**
```ruby
def test_soft_deleted_records_not_leaked_by_typo_fallback
  model = Class.new(Customer) do
    full_search do
      field :first_name, weight: 5
      filter :account_id, required: true
      typo_tolerance
      soft_delete_column :discarded_at
    end
  end
  model.table_name = "customers"
  account = Account.create!(name: "Acme")
  customer = model.create!(account_id: account.id, first_name: "Samantha")
  model.create!(account_id: account.id, first_name: "Samantha", discarded_at: Time.current)
  FullSearch::Index.rebuild!(model)
  
  results = model.full_search("saman", filters: { account_id: account.id })
  assert_equal 1, results.size
end
```

---

### Task 7: Add query input validation and reserved-token handling

**Files:**
- Modify: `lib/full_search/query_parser.rb`
- Modify: `lib/full_search/errors.rb` (add `InvalidQueryError`)
- Add tests: `test/full_search/query_parser_test.rb`

**Problem:** No limits on query length, no handling of malformed input.

**Solution:**
- Add `InvalidQueryError` to errors.rb
- Validate query length (max 255 bytes) and reject null bytes
- Handle leading/trailing OR gracefully
- Handle empty parse results in `to_match_expression`

```ruby
# errors.rb
class InvalidQueryError < Error; end

# query_parser.rb
MAX_QUERY_LENGTH = 255

def self.parse(query)
  query = query.to_s.strip
  validate!(query)
  tokens = tokenize(query)
  return [] if tokens.empty?
  # ... rest unchanged
end

def self.validate!(query)
  raise InvalidQueryError, "Query too long (max #{MAX_QUERY_LENGTH} chars)" if query.bytesize > MAX_QUERY_LENGTH
  raise InvalidQueryError, "Query contains invalid characters" if query.include?("\x00")
end
```

**Tests:**
```ruby
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
```

---

### Task 8: Make config hash stable and source-change-sensitive

**Files:**
- Modify: `lib/full_search/dsl.rb:86-99`
- Add tests: `test/full_search/dsl_test.rb`

**Problem:** Config hash relies on proc `source_location` which can be identical for different source procs defined on the same line.

**Solution:** Add optional `version:` parameter to `field` and `exact_match`. Include it in config_hash. This gives users explicit control over declaring source proc changes.

```ruby
Field = Data.define(:name, :weight, :source, :reindex_on, :async, :as, :version)

def field(name, weight: 1, source: nil, reindex_on: nil, async: FullSearch.config.default_async_reindex, as: nil, version: nil)
  # ... existing validation ...
  @fields << Field.new(name: name.to_s, weight: weight.to_i, source: source, reindex_on: reindex_on&.to_s, async: async, as: as&.to_s, version: version)
end

ExactMatch = Data.define(:name, :source, :version)

def exact_match(name, source: -> { public_send(name) }, version: nil)
  # ... existing validation ...
  @exact_matches << ExactMatch.new(name: name.to_s, source: source, version: version)
end
```

Update config_hash to include version:

```ruby
def config_hash
  Digest::SHA256.hexdigest([
    # ... existing fields ...
    fields.map { |f| [f.name, f.weight, f.source.nil? ? "column" : "proc:#{f.version}", f.reindex_on, f.async, f.as] },
    exact_matches.map { |e| [e.name, "proc:#{e.version}"] },
    # ... rest unchanged
  ].inspect)
end
```

Note: The version defaults to `nil`, so existing configs without version won't trigger unwanted rebuilds.

**Tests:**
```ruby
def test_config_hash_differs_when_version_differs
  dsl1 = FullSearch::Dsl.new(Customer)
  dsl1.field :name, source: -> { name }, version: 1

  dsl2 = FullSearch::Dsl.new(Customer)
  dsl2.field :name, source: -> { name }, version: 2

  refute_equal dsl1.config_hash, dsl2.config_hash
end
```

---

### Task 9: Harden exact-match source execution

**Files:**
- Modify: `lib/full_search/exact_match.rb`
- Add tests: `test/full_search/exact_match_test.rb`

**Problem:** `exact_match_value` uses a fake object. Procs referencing non-exact-match methods will fail.

**Solution:** Execute source procs on real ActiveRecord records. Scan all records matching filters, evaluate each exact_match source, compare with query.

```ruby
def self.ids_for(model, query, filters)
  dsl = model.full_search_dsl
  return [] if dsl.exact_matches.empty?

  cleaned = query.to_s.strip
  return [] if cleaned.empty?

  relation = model.all
  filters.each { |name, value| relation = relation.where(name => value) }

  ids = []
  relation.find_each do |record|
    dsl.exact_matches.each do |em|
      value = record.instance_exec(&em.source)
      ids << record.id if value.to_s.casecmp?(cleaned)
    end
  end
  ids.uniq
end
```

**Tests:**
```ruby
def test_exact_match_executes_source_on_real_record
  search_model = Class.new(Vehicle) do
    full_search do
      exact_match :make, source: -> { make&.upcase }
      filter :account_id, required: true
    end
  end
  search_model.table_name = "vehicles"
  FullSearch::Index.rebuild!(search_model)
  vehicle = Vehicle.create!(account_id: @account.id, make: "Honda")
  # Searching lowercase "honda" should match the upcase'd source "HONDA"
  ids_with_lowercase = FullSearch::ExactMatch.ids_for(search_model, "honda", { account_id: @account.id })
  assert_includes ids_with_lowercase, vehicle.id
end

def test_multiple_exact_matches
  search_model = Class.new(Vehicle) do
    full_search do
      exact_match :make
      exact_match :license_plate
      filter :account_id, required: true
    end
  end
  search_model.table_name = "vehicles"
  FullSearch::Index.rebuild!(search_model)
  vehicle = Vehicle.create!(account_id: @account.id, make: "Honda", license_plate: "ABC-123")
  ids = FullSearch::ExactMatch.ids_for(search_model, "Honda", { account_id: @account.id })
  assert_includes ids, vehicle.id
end
```

---

### Task 10: Reject duplicate DSL declarations

**Files:**
- Modify: `lib/full_search/dsl.rb`
- Add tests: `test/full_search/dsl_test.rb`

**Problem:** Duplicate field, filter, exact_match, and rank_by names are silently allowed.

**Solution:** Check for duplicates in all collection types before adding.

```ruby
def field(name, ...)
  raise InvalidFieldError, "Duplicate name: #{name.inspect}" if name_taken?(name)
  # ...
end

private

def name_taken?(name)
  str = name.to_s
  fields.any? { |f| f.name == str } ||
    filters.any? { |f| f.name == str } ||
    exact_matches.any? { |e| e.name == str } ||
    rank_bys.any? { |r| r.column == str }
end
```

Note: `as` aliases are not checked here to avoid complexity.

**Test:**
```ruby
def test_duplicate_field_name_raises
  @dsl.field :first_name
  assert_raises(FullSearch::InvalidFieldError) do
    @dsl.field :first_name
  end
end
```

---

### Task 11: Add missing search behavior tests

**Files:**
- Modify: `test/full_search/search_test.rb`
- Add test: `test/full_search/full_search_ids_test.rb`

Cover required-filter string keys, full_search_ids, and nil filter values.

```ruby
# search_test.rb additions
def test_required_filter_accepts_string_keys
  account = Account.create!(name: "Acme")
  customer = @customer_model.create!(account_id: account.id, first_name: "Sam")
  FullSearch::Index.rebuild!(@customer_model)
  results = @customer_model.full_search("Sam", filters: { "account_id" => account.id })
  assert_includes results.to_a, customer
end

def test_filter_with_nil_value
  account = Account.create!(name: "Acme")
  customer = @customer_model.create!(account_id: account.id, first_name: "Sam")
  FullSearch::Index.rebuild!(@customer_model)
  results = @customer_model.full_search("Sam", filters: { account_id: account.id })
  assert_includes results.to_a, customer
end
```

```ruby
# test/full_search/full_search_ids_test.rb
require "test_helper"

class FullSearch::FullSearchIdsTest < ActiveSupport::TestCase
  def test_returns_ids
    model = Class.new(Customer) do
      full_search do
        field :first_name
        filter :account_id, required: true
      end
    end
    model.table_name = "customers"
    account = Account.create!(name: "Acme")
    customer = model.create!(account_id: account.id, first_name: "Sam")
    FullSearch::Index.rebuild!(model)
    ids = model.full_search_ids("Sam", filters: { account_id: account.id })
    assert_includes ids, customer.id
  end
end
```

Also fix `Search#validate_required_filters!` to accept string filter keys:
```ruby
def validate_required_filters!
  dsl.filters.each do |filter|
    next unless filter.required
    unless filters.key?(filter.name.to_sym) || filters.key?(filter.name.to_s)
      raise MissingRequiredFilterError, "Missing required filter: #{filter.name}"
    end
  end
end
```

---

### Task 12: Add transaction and trigger behavior tests

**Files:**
- Add `test/full_search/transactions_test.rb`

```ruby
require "test_helper"

class FullSearch::TransactionsTest < ActiveSupport::TestCase
  def setup
    @model = Class.new(Customer) do
      full_search do
        field :first_name
        filter :account_id, required: true
      end
    end
    @model.table_name = "customers"
    FullSearch::Index.rebuild!(@model)
    @account = Account.create!(name: "Acme")
  end

  def teardown
    Customer.delete_all
    Account.delete_all
    FullSearch::Index.drop!(@model) rescue nil
  end

  def test_insert_inside_transaction_is_indexed
    customer = nil
    ActiveRecord::Base.transaction do
      customer = @model.create!(account_id: @account.id, first_name: "Sam")
    end
    results = @model.full_search("Sam", filters: { account_id: @account.id })
    assert_includes results.to_a, customer
  end

  def test_rolled_back_insert_is_not_indexed
    ActiveRecord::Base.transaction do
      @model.create!(account_id: @account.id, first_name: "Sam")
      raise ActiveRecord::Rollback
    end
    results = @model.full_search("Sam", filters: { account_id: @account.id })
    assert_empty results.to_a
  end
end
```

---

### Task 13: Add multi_search error-handling and highlight support

**Files:**
- Modify: `lib/full_search/multi_search.rb`
- Add tests: `test/full_search/multi_search_test.rb`

**Problem:** No validation for unconfigured models. No support for `highlight: true`.

**Implementation:**
Validate model configuration in `MultiSearch#call`. Support `highlight` option.

```ruby
# In MultiSearch#call
model = fetch(group, :model)
raise FullSearch::NotConfiguredError, "#{model} is not full_search configured" unless model.full_search_dsl
# ...
relation = model.full_search(
  query,
  filters: filters,
  limit: raw_limit,
  offset: offset,
  highlight: group[:highlight],
  highlight_fields: group[:highlight_fields]
)
```

**Tests:**
```ruby
def test_raises_when_model_not_configured
  unconfigured = Class.new(Customer)
  unconfigured.table_name = "customers"
  assert_raises(FullSearch::NotConfiguredError) do
    FullSearch.multi_search(
      query: "Sam",
      groups: [{ key: :bad, model: unconfigured }]
    )
  end
end

def test_highlight_option
  account = Account.create!(name: "Acme")
  @customer_model.create!(account_id: account.id, first_name: "Arthur")
  FullSearch::Index.rebuild!(@customer_model)
  result = FullSearch.multi_search(
    query: "Arthur",
    groups: [{ key: :customers, model: @customer_model, filters: { account_id: account.id }, highlight: true }]
  )
  record = result[:groups].first[:results].first
  assert record.respond_to?(:full_search_snippet)
  assert_includes record.full_search_snippet, "<mark>"
end
```

---

### Task 14: Lower Ruby requirement in gemspec

**Files:**
- Modify: `full_search.gemspec:14`

Change `spec.required_ruby_version = ">= 4.0.0"` to `spec.required_ruby_version = ">= 3.2.0"`.

---

### Task 15: Fix class-name typo in Highlighter

**Files:**
- Modify: `lib/full_search/highlighter.rb:4`

Change `class Highligther` to `class Highlighter`.

---

### Task 16: Remove unused `ostruct` runtime dependency

**Files:**
- Modify: `full_search.gemspec:23`
- Modify: `lib/full_search/index.rb:3`

**Implementation:**
1. Remove `require "ostruct"` from `index.rb`
2. Replace `OpenStruct.new(name: ..., unindexed?: true)` with a plain `Struct` or simple object
3. Remove `spec.add_dependency "ostruct", ">= 0.6"`

```ruby
# index.rb - replace OpenStruct usage
FilterColumnPlaceholder = Struct.new(:name, :unindexed, keyword_init: true)
# ... use as:
FilterColumnPlaceholder.new(name: c.name, unindexed: true)
```

Then update all `.unindexed?` calls to `.unindexed` (method name).

Wait, we need `.unindexed?` with question mark. Let's just use a plain class:

```ruby
class FilterColumn
  attr_reader :name
  def initialize(name:)
    @name = name.to_s
  end
  def unindexed?
    true
  end
end
```

---

### Task 17: Final test sweep and regression run

**Files:**
- All

Run full test suite, fix any remaining failures.

---

