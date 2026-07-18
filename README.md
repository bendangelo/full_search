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
- Rake tasks: `full_search:rebuild`, `full_search:optimize`, `full_search:status`

## Known limitations

- No highlighting support (v1)
- No phrase/exclusion/OR query operators (v1)
- No typo tolerance by default (v1); use `tokenize: "trigram"` or a future `spellfix1` extension
- Per-model only; no built-in multi-model aggregator
