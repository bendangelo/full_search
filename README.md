# full_search

SQLite FTS5 full-text search for Rails/ActiveRecord. A lightweight, self-contained alternative to `pg_search` for apps already running on SQLite.

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
Customer.full_search("sam", filters: { account_id: 1 }).page(params[:page])
```

## Features

- Declarative `full_search` DSL
- SQLite FTS5 backed
- Required-filter enforcement for multi-tenant apps
- Exact-match queries for encrypted identifiers
- Soft-delete awareness
- Automatic table creation and schema-drift detection
- Phrase, exclusion, and OR query operators
- FTS5 `highlight()` support for result snippets
- Opt-in trigram typo/substring fallback (requires SQLite >= 3.34)
- Rake tasks: `full_search:rebuild`, `full_search:optimize`, `full_search:status`

## Query operators

```ruby
Customer.full_search('"Sam Smith"', filters: { account_id: 1 })      # phrase
Customer.full_search("honda -civic", filters: { account_id: 1 })     # exclusion
Customer.full_search("honda OR toyota", filters: { account_id: 1 })  # OR
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
Customer.full_search("sam", filters: { account_id: 1 }, highlight: true)
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
