# full_search

SQLite FTS5 full-text search for Rails/ActiveRecord. A lightweight, self-contained alternative to `pg_search` for apps already running on SQLite.

## When to use

`full_search` is designed for apps with **100,000 records or fewer per table** that want full-text search without running a separate service. If you're on SQLite and need keyword search, phrase matching, typo-tolerant substring queries, or result highlighting, this gem gives you production-quality search with zero infrastructure — no Elasticsearch, no Meilisearch, no Sidekiq queue.

## Installation

Add to your Gemfile:

```ruby
gem "full_search"
```

Run:

```bash
bundle install
bin/rails generate full_search:install
```

## Usage

```ruby
class Customer < ApplicationRecord
  full_search do
    field :first_name, weight: 5
    field :last_name,  weight: 5
    filter :account_id, required: true
  end
end
```

```ruby
Customer.search("sam", filters: { account_id: 1 }).page(params[:page])
```

## Features

- Declarative `full_search` DSL with `search` / `full_search` query methods
- SQLite FTS5 backed
- Required-filter enforcement for multi-tenant apps
- Exact-match queries for encrypted identifiers
- Soft-delete awareness
- Automatic table creation and schema-drift detection
- Phrase, exclusion, and OR query operators
- FTS5 `highlight()` support for result snippets
- Opt-in trigram typo/substring fallback (requires SQLite >= 3.34)

### Per-model operations

Once a model declares `full_search`, you can call these class methods:

| Method | What it does |
|--------|-------------|
| `Customer.rebuild!` | Force-drop and recreate the model's FTS table, backfill from the source table, and reinstall triggers. |
| `Customer.reindex!` | Re-evaluates computed `source:` fields for every record and updates the FTS table in-place. Table structure is untouched. |
| `Customer.optimize!` | Runs FTS5 `optimize` on the model's index to merge b-tree segments. |

## Index management

FTS indexes are SQLite virtual tables (`customers_fts`, `vehicles_fts`, etc.) that mirror your model tables. They stay in sync via database triggers on `INSERT` / `UPDATE` / `DELETE`.

### Rebuild vs reindex

These two operations are often confused:

- **Rebuild** (`full_search:rebuild` / `Customer.rebuild!`) — drops and recreates the FTS virtual table. Needed when the DSL changes (fields added/removed, tokenizer changed, etc.). The table is re-created from scratch, backfilled, triggers re-installed, and the index is optimized.
- **Reindex** (`Customer.reindex!` / `FullSearch::Index.reindex_source_fields!`) — updates existing FTS rows with fresh values from computed `source:` fields only. The table structure is untouched. Database triggers cover regular column changes automatically; only Ruby-evaluated `source:` blocks need an explicit reindex.

### Auto-rebuild on app load

When `auto_rebuild_schema` is enabled (default in the generated initializer), the railtie hooks into Rails `after_initialize` and:

1. Creates missing FTS tables for every model using `full_search`
2. Compares each table's stored config hash against the current DSL
3. Rebuilds the index automatically when the DSL changes (new fields, different tokenizer, etc.)

```ruby
# config/initializers/full_search.rb
FullSearch.configure do |config|
  config.auto_rebuild_schema = true
end
```

### In production

Auto-rebuild runs on every Rails process boot (web, worker, console). For zero-downtime deploys where old processes still serve traffic, or if you prefer explicit control, set `auto_rebuild_schema` to `false` and run the rebuild task manually:

```bash
# Rebuild only indexes whose DSL has changed (fast, safe for production)
bin/rails full_search:rebuild

# Target specific models by table name
bin/rails 'full_search:rebuild[customers,vehicles]'
```

The rebuild task checks each model's stored config hash against the current DSL and only drops/recreates indexes when they differ. For a full forced reset (drops and recreates all FTS tables regardless):

```bash
bin/rails full_search:reset
```

### Rake tasks

| Task | Description |
|------|-------------|
| `full_search:rebuild` | Drops and recreates the FTS virtual table only when the DSL config hash has changed (safe for production). Pass model names to target specific tables. |
| `full_search:reset` | Force a full rebuild — drops and recreates all FTS tables regardless of config hash. Use when data may be out of sync. |
| `full_search:optimize` | Run FTS5 [`optimize`](https://www.sqlite.org/fts5.html#the_optimize_command) to merge b-tree segments. Useful after bulk updates. |
| `full_search:status` | Show each model's index status (`ok` / `stale`) and count of empty sourced fields. |

## Background jobs

### Scheduled optimization

FTS5 b-tree segments accumulate over time as rows are inserted, updated, and deleted. Running `optimize` periodically merges these segments, keeping queries fast. For most apps, once a day during a low-traffic window is sufficient. Apps with heavy write volume may benefit from every few hours.

The gem ships `FullSearch::OptimizeJob` ready to use. Schedule it with Solid Queue's `recurring.yml`:

```yaml
# config/recurring.yml
full_search_optimize:
  class: FullSearch::OptimizeJob
  schedule: daily at 4am
  description: "Merge FTS5 b-tree segments for full_search indexes"
```

If you're not on Solid Queue, most job frameworks support recurring schedules via gems like `sidekiq-cron` or `whenever`.

### Config hash drift detection

Every FTS table stores a SHA256 digest of its DSL configuration in the `full_search_index_versions` table. When the DSL changes (e.g., adding a field), the stored hash no longer matches, and `rebuild!` is triggered automatically (if `auto_rebuild_schema` is true) to bring the index in line with the new definition. If `auto_rebuild_schema` is false, queries still run but raise `ConfigChangedError` when the hash doesn't match.

## Query operators

```ruby
Customer.search('"Sam Smith"', filters: { account_id: 1 })      # phrase
Customer.search("honda -civic", filters: { account_id: 1 })     # exclusion
Customer.search("honda OR toyota", filters: { account_id: 1 })  # OR
```

## Highlighting

```ruby
class Customer < ApplicationRecord
  full_search do
    field :first_name, weight: 5
    highlight open_tag: "<mark>", close_tag: "</mark>"
  end
end
```

```ruby
Customer.search("sam", filters: { account_id: 1 }, highlight: true)
# each result has #full_search_snippet
```

## Typo tolerance

```ruby
class Customer < ApplicationRecord
  full_search do
    field :first_name, weight: 5
    typo_tolerance
  end
end
```

`typo_tolerance` uses an FTS5 trigram shadow table as a fallback when the primary index returns no results. It is substring matching, not edit-distance correction, and requires SQLite >= 3.34.

## Known limitations

- Queries run with `highlight: true` return an Array of records, not an `ActiveRecord::Relation`. No further chaining (`.where`, `.order`, `.limit`) is possible after highlighting is applied.
- Per-model only; no built-in multi-model aggregator
