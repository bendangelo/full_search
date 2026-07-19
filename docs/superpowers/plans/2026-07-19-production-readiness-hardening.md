# full_search Production-Readiness Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers-ruby:subagent-driven-development` (recommended) or `superpowers-ruby:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the critical security, operational, and test-coverage gaps identified in the production-readiness review, and put the gem on solid long-term footing without changing the public DSL.

**Architecture:** Keep the existing DSL and module names, but harden SQL construction with quoting/whitelisting, fail fast on unsupported adapters, make rebuild tooling dev/test-only by default, and close the missing test coverage. Refactor large classes only after the safety fixes are in place.

**Tech Stack:** Ruby 3.1+, Rails/ActiveRecord 8+, SQLite 3.34+, Minitest, StandardRB.

---

## File structure changes

| File | Responsibility |
|------|---------------|
| `lib/full_search/index.rb` | Table/trigger lifecycle, config hash storage, rebuild locking |
| `lib/full_search/search.rb` | Query execution with quoted identifiers and whitelisted filters |
| `lib/full_search/callbacks.rb` | Safe source-field sync with bound IDs and transactions |
| `lib/full_search/soft_delete.rb` | Trigger WHEN-clause generation with quoted columns |
| `lib/full_search/highlighter.rb` | Highlight snippets with safe SQL construction |
| `lib/full_search/dsl.rb` | Validate `rank_by` direction; stable config hashing |
| `lib/full_search/exact_match.rb` | Safer exact-match filtering |
| `lib/full_search/distance.rb` *(new)* | Shared Damerau-Levenshtein implementation |
| `lib/full_search/errors.rb` | Already defines errors; ensure `UnsupportedDatabaseError` used |
| `lib/full_search/railtie.rb` | Disable boot-time rebuild by default; document dev/test opt-in |
| `lib/tasks/full_search.rake` | Remove bare `rescue`; validate identifiers |
| `lib/generators/full_search/install/templates/full_search.rb` | Default `auto_rebuild_schema = Rails.env.local?` |
| `full_search.gemspec` | Tighten Rails to `< 9`; remove unused `ostruct` |
| `test/**/*_test.rb` | New injection/adapter/job/concurrency/edge-case tests |
| `README.md` / `CHANGELOG.md` | Correct inaccuracies; document public vs internal APIs |

---

## Phase 1: Security hardening

### Task 1: Quote all SQL identifiers and bind values

**Files:**
- Modify: `lib/full_search/index.rb`
- Modify: `lib/full_search/search.rb`
- Modify: `lib/full_search/callbacks.rb`
- Modify: `lib/full_search/soft_delete.rb`
- Modify: `lib/full_search/highlighter.rb`
- Modify: `lib/tasks/full_search.rake`
- Add tests: `test/full_search/sql_safety_test.rb`

**Problem:** Table names, column names, trigger names, and IDs are interpolated into SQL without quoting or parameter binding.

**Implementation:**

Introduce helper methods in each class:

```ruby
def connection = model.connection
def q(value) = connection.quote(value)
def qt(name) = connection.quote_table_name(name)
def qc(name) = connection.quote_column_name(name)
```

Then update every SQL string:

- `index.rb`: `CREATE VIRTUAL TABLE #{qt(fts_table_name(model))}`, `DROP TABLE IF EXISTS #{qt(fts_table_name(model))}`, trigger names with `qt(...)`, `WHERE rowid = #{q(value)}`, `#{model.table_name}.#{c.name}` becomes `#{qt(model.table_name)}.#{qc(c.name)}`.
- `search.rb`: `JOIN #{qt(model.table_name)}`, `#{fts_table}.#{name}` becomes `#{qt(fts_table)}.#{qc(name)}`, `rank_by` direction validated and quoted via allow-list.
- `callbacks.rb`: `UPDATE #{qt(table)} SET #{qc(field.name)} = #{q(value)} WHERE rowid = #{q(record.id)}`, `DELETE FROM #{qt(table)} WHERE rowid = #{q(record.id)}`, dependent lookup uses parameterized query.
- `soft_delete.rb`: `WHEN new.#{qc(dsl.soft_delete_column)} IS NULL`.
- `highlighter.rb`: `highlight(#{qt(table)}, ...)` and `WHERE #{qt(table)} MATCH #{q(match_expr)}`.
- `full_search.rake`: `status` task quotes identifiers.

### Task 2: Whitelist filter keys in search queries

**Files:**
- Modify: `lib/full_search/search.rb`
- Test: `test/full_search/sql_safety_test.rb`

**Problem:** `filters` hash keys are interpolated directly into SQL.

**Implementation:**

Add private method in `Search`:

```ruby
def allowed_filter_names
  @allowed_filter_names ||= Set.new(dsl.filters.map(&:name))
end

def validate_filter_keys!
  filters.each_key do |key|
    unless allowed_filter_names.include?(key.to_s)
      raise MissingRequiredFilterError, "Unknown filter: #{key}"
    end
  end
end
```

Call `validate_filter_keys!` inside `validate_required_filters!`.

### Task 3: Remove bare `rescue` and bind record IDs

**Files:**
- Modify: `lib/full_search/search.rb`
- Modify: `lib/full_search/callbacks.rb`
- Modify: `lib/tasks/full_search.rake`

**Problem:** Bare `rescue` swallows all errors; `record.id` is interpolated into SQL.

**Implementation:**

- `Search#trigram_match_ids` / `fuzzy_match_ids`: replace `begin ... rescue; nil` with explicit parsing that returns `nil` on expected parser state; do not swallow `StandardError`.
- `Callbacks#reindex_field!` / `remove_record!`: use `connection.quote(record.id)`.
- `Callbacks#reindex_dependents!`: build SQL with quoted identifiers and bind `parent_record.id`.
- `full_search.rake#resolve_full_search_models`: rescue only `NameError`, `LoadError`; log a warning for unresolved names.

```ruby
def resolve_full_search_models(args)
  if args[:models]
    args[:models].split(",").map do |name|
      begin
        name.singularize.camelize.constantize
      rescue NameError, LoadError
        warn "[full_search] Could not resolve model: #{name}"
        nil
      end
    end.compact
  else
    FullSearch.models
  end
end
```

---

## Phase 2: Operational correctness

### Task 4: Fail fast on unsupported database adapters

**Files:**
- Modify: `lib/full_search/index.rb`
- Modify: `lib/full_search/typo.rb`
- Add tests: `test/full_search/adapter_test.rb`

**Problem:** `sqlite?` silently returns early on PostgreSQL/MySQL; `UnsupportedDatabaseError` is defined but unused.

**Implementation:**

Add adapter check:

```ruby
# lib/full_search/index.rb
def self.sqlite!(model)
  unless sqlite?(model)
    raise UnsupportedDatabaseError,
      "full_search requires SQLite, but #{model.connection.adapter_name} is configured"
  end
end
```

Call `sqlite!` at the start of `ensure_table!`, `rebuild!`, `rebuild_if_needed!`, `optimize!`, `drop!`.

Update `sqlite?` to accept a model (not use global `ActiveRecord::Base.connection`):

```ruby
def self.sqlite?(model)
  model.connection.adapter_name.downcase.include?("sqlite")
end
```

Update `Typo.sqlite_version` to accept a connection.

### Task 5: Make rebuild tooling dev/test-only by default

**Files:**
- Modify: `lib/full_search/config.rb`
- Modify: `lib/generators/full_search/install/templates/full_search.rb`
- Modify: `README.md`

**Problem:** Auto-rebuild on every Rails boot is risky in production. User clarified rebuild is dev/test-only.

**Implementation:**

- Default `Config#auto_rebuild_schema = false`.
- Generator initializer sets it to `Rails.env.local?`.
- Update README to state: rebuild rake tasks are intended for development/test and deployment-time maintenance, not for runtime web processes.

### Task 6: Implement `stale_query_behavior`

**Files:**
- Modify: `lib/full_search/search.rb`

**Problem:** README promises `ConfigChangedError` on stale config; code never checks it.

**Implementation:**

Add to `Search#relation`:

```ruby
stored = FullSearch::Index.stored_config_hash(model)
current = dsl.config_hash
if stored && stored != current
  case FullSearch.config.stale_query_behavior
  when :raise
    raise ConfigChangedError, "FTS config changed for #{model.table_name}; run full_search:rebuild"
  when :log_and_fallback
    Rails.logger.warn("[full_search] Stale config for #{model.table_name}; running query anyway")
  end
end
```

### Task 7: Document rebuild lock limitation

**Files:**
- Modify: `lib/full_search/index.rb` (add comment)
- Modify: `README.md`

**Implementation:**

Add a comment and README note:

> `lock_rebuilds` prevents concurrent rebuilds within the same process/connection. For multi-process or multi-host deployments, run `full_search:rebuild` from a single deployment step.

---

## Phase 3: Test coverage

### Task 8: Add missing edge-case and job tests

**Files:**
- Add: `test/full_search/edge_case_test.rb`
- Add: `test/full_search/job_test.rb`
- Add: `test/full_search/exact_match_test.rb` (expand)

---

## Phase 4: Refactoring

### Task 9: Extract shared Levenshtein distance

**Files:**
- Create: `lib/full_search/distance.rb`
- Modify: `lib/full_search/search.rb`
- Modify: `lib/full_search/highlighter.rb`

### Task 10: Split `FullSearch::Index` into smaller classes

**Files:**
- Create: `lib/full_search/index/schema.rb`
- Create: `lib/full_search/index/triggers.rb`
- Create: `lib/full_search/index/metadata.rb`
- Modify: `lib/full_search/index.rb` (become thin facade)

---

## Phase 5: Packaging & documentation

### Task 11: Tighten gemspec and remove unused `ostruct`

**Files:**
- Modify: `full_search.gemspec`

### Task 12: Fix README inaccuracies and add security policy

**Files:**
- Modify: `README.md`

### Task 13: Update CHANGELOG for 0.3.0

**Files:**
- Modify: `CHANGELOG.md`

---

## Final verification

- Run full test suite
- Run StandardRB
- Test Rails 8.0 compatibility
- Review git log and working tree
