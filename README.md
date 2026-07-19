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

## Index management

FTS indexes are SQLite virtual tables (`customers_fts`, `vehicles_fts`, etc.) that mirror your model tables. They stay in sync via database triggers on `INSERT` / `UPDATE` / `DELETE`.

### Auto-management on app load

When `auto_manage_schema` is enabled (default in the generated initializer), the railtie hooks into Rails `after_initialize` and:

1. Creates missing FTS tables for every model using `full_search`
2. Compares each table's stored config hash against the current DSL
3. Rebuilds the index automatically when the DSL changes (new fields, different tokenizer, etc.)

```ruby
# config/initializers/full_search.rb
FullSearch.configure do |config|
  config.auto_manage_schema = true
end
```

### In production

Auto-management runs on every Rails process boot (web, worker, console). For zero-downtime deploys where old processes still serve traffic, or if you prefer explicit control, set `auto_manage_schema` to `false` and run rebuilds manually:

```bash
# Rebuild all indexes
bin/rails full_search:rebuild

# Rebuild specific models by table name
bin/rails 'full_search:rebuild[customers,vehicles]'
```

A rebuild drops the FTS virtual tables, recreates them, backfills existing rows, and installs sync triggers. For tables under 100k rows this completes in under a second.

### Rake tasks

| Task | Description |
|------|-------------|
| `full_search:rebuild` | Drop and recreate all FTS tables, backfill data, install triggers. Pass model names to target specific tables. |
| `full_search:optimize` | Run FTS5 [`optimize`](https://www.sqlite.org/fts5.html#the_optimize_command) to merge b-tree segments. Useful after bulk updates. |
| `full_search:status` | Show each model's index status (`ok` / `stale`) and count of empty sourced fields. |

### Config hash drift detection

Every FTS table stores a SHA256 digest of its DSL configuration in the `full_search_index_versions` table. When the DSL changes (e.g., adding a field), the stored hash no longer matches, and `rebuild!` is triggered automatically (if `auto_manage_schema` is true) to bring the index in line with the new definition. If `auto_manage_schema` is false, queries still run but raise `ConfigChangedError` when the hash doesn't match.

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
