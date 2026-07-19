# Operational / packaging improvements implementation plan

> **Required sub-skill:** Use `superpowers-ruby:subagent-driven-development` (recommended) or `superpowers-ruby:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring the `full_search` gem's packaging, CI, linting, and repository hygiene up to current Ruby gem standards without changing any feature behavior.

**Architecture:** A small set of additive metadata/config files (`gemspec`, `Gemfile`, CI workflow, `CHANGELOG.md`) plus removal of accidentally committed build artifacts and one mechanical StandardRB auto-fix pass.

**Tech Stack:** Ruby 3.1+, Rails 8.0/8.1, Minitest, StandardRB, GitHub Actions, Bundler.

---

## File structure

Files to create:
- `.github/workflows/ci.yml`
- `CHANGELOG.md`
- `bin/lint`

Files to modify:
- `full_search.gemspec`
- `Gemfile`
- `README.md`
- `.gitignore`
- `Rakefile`

Files/directories to delete from git and disk:
- `pkg/full_search-0.1.0.gem`
- `pkg/full_search-0.1.1.gem`
- `pkg/full_search-0.1.2.gem`
- `pkg/full_search-0.1.3.gem`
- `pkg/full_search-0.2.0.gem`
- `.ruby-lsp/` (entire directory)
- `Gemfile.lock`

---

## Task 1: Update gemspec version and metadata

**Files:**
- Modify: `full_search.gemspec`

- [ ] **Step 1: Relax required Ruby version**

```ruby
spec.required_ruby_version = ">= 3.1.0"
```

- [ ] **Step 2: Add required RubyGems version**

```ruby
spec.required_rubygems_version = ">= 2.0"
```

- [ ] **Step 3: Add signing metadata without forcing a build-time key**

```ruby
spec.cert_chain = ["cert/full_search.pem"]
spec.signing_key = "cert/priv_key.pem" if File.exist?("cert/priv_key.pem")
```

- [ ] **Step 4: Add StandardRB as a development dependency**

```ruby
spec.add_development_dependency "standard", "~> 1.40"
```

- [ ] **Step 5: Verify gemspec syntax**

Run: `ruby -c full_search.gemspec`
Expected: `Syntax OK`

- [ ] **Step 6: Commit**

```bash
git add full_search.gemspec
git commit -m "chore: relax Ruby requirement to 3.1+ and add signing metadata"
```

---

## Task 2: Make Gemfile support CI matrix via env var

**Files:**
- Modify: `Gemfile`

- [ ] **Step 1: Replace hard-coded Rails versions with env-driven defaults**

```ruby
# frozen_string_literal: true

source "https://rubygems.org"

rails_version = ENV.fetch("RAILS_VERSION", "8.1")

gemspec

gem "activerecord", "~> #{rails_version}"
gem "activejob", "~> #{rails_version}"
gem "railties", "~> #{rails_version}"
gem "sqlite3", ">= 2.1"
gem "minitest", "~> 5.0"
gem "rake", "~> 13.0"
```

- [ ] **Step 2: Verify both Rails versions resolve**

Run: `RAILS_VERSION=8.0 bundle update activerecord activejob railties`
Expected: resolves to Rails 8.0.x with no errors.

Run: `bundle update activerecord activejob railties`
Expected: resolves back to Rails 8.1.x (or whatever was locked).

- [ ] **Step 3: Commit**

```bash
git add Gemfile
git commit -m "chore: allow Gemfile to target Rails version via RAILS_VERSION env var"
```

---

## Task 3: Clean accidentally committed files from git

**Files:**
- Modify: `.gitignore`
- Delete: `pkg/*.gem`, `.ruby-lsp/`, `Gemfile.lock`

- [ ] **Step 1: Ensure `.gitignore` covers artifacts**

`.gitignore` should contain:

```gitignore
/Gemfile.lock
/pkg
/tmp
/coverage
/.ruby-version
/.ruby-lsp
```

If `.ruby-lsp` is missing, add it:

```bash
echo "/.ruby-lsp" >> .gitignore
```

- [ ] **Step 2: Delete tracked files from disk and git index**

```bash
git rm -r pkg .ruby-lsp Gemfile.lock
```

- [ ] **Step 3: Verify nothing unwanted remains tracked**

Run: `git ls-files | grep -E '^(pkg/|\.ruby-lsp/|Gemfile\.lock)'`
Expected: empty output.

- [ ] **Step 4: Commit**

```bash
git add .gitignore
git commit -m "chore: remove pkg gems, .ruby-lsp, and Gemfile.lock from git"
```

---

## Task 4: Add StandardRB rake tasks and convenience script

**Files:**
- Modify: `Rakefile`
- Create: `bin/lint`

- [ ] **Step 1: Load StandardRB rake tasks**

```ruby
# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"
require "standard/rake"

Rake::TestTask.new(:test) do |t|
  t.libs << "lib"
  t.libs << "test"
  t.test_files = FileList["test/**/*_test.rb"]
  t.warning = false
end

task default: [:test, :standard]
```

- [ ] **Step 2: Create `bin/lint` convenience script**

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
bundle exec rake standard
```

Make it executable:

```bash
chmod +x bin/lint
```

- [ ] **Step 3: Verify StandardRB rake tasks load**

Run: `bundle exec rake -T`
Expected: lists `standard` and `standard:fix` tasks.

- [ ] **Step 4: Commit**

```bash
git add Rakefile bin/lint
git commit -m "chore: add StandardRB rake tasks and bin/lint script"
```

---

## Task 5: Run StandardRB auto-fix once

**Files:**
- Modify: all Ruby files StandardRB reports as needing formatting.

- [ ] **Step 1: Run auto-fix**

```bash
bundle exec rake standard:fix
```

- [ ] **Step 2: Verify lint passes**

```bash
bundle exec rake standard
```
Expected: no offenses.

- [ ] **Step 3: Run tests to ensure no behavior changed**

```bash
bundle exec rake test
```
Expected: all tests pass.

- [ ] **Step 4: Review the diff for anything suspicious**

Run: `git diff --stat`
Expected: large but mechanical changes only (quotes, spacing, parentheses, trailing commas, etc.).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "style: apply StandardRB formatting"
```

---

## Task 6: Add GitHub Actions CI workflow

**Files:**
- Create: `.github/workflows/ci.yml`

- [ ] **Step 1: Create workflow file**

```yaml
name: CI

on:
  push:
    branches: [main, master]
  pull_request:
    branches: [main, master]

jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        ruby: ["3.1", "3.2", "3.3"]
        rails: ["8.0", "8.1"]

    steps:
      - uses: actions/checkout@v4

      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: ${{ matrix.ruby }}
          bundler-cache: true

      - name: Install dependencies
        run: bundle install
        env:
          RAILS_VERSION: ${{ matrix.rails }}

      - name: Run tests
        run: bundle exec rake test
        env:
          RAILS_VERSION: ${{ matrix.rails }}

      - name: Run linter
        run: bundle exec rake standard
```

- [ ] **Step 2: Verify YAML syntax**

Run: `ruby -ryaml -e 'YAML.load_file(".github/workflows/ci.yml")'`
Expected: no output / no errors.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "chore: add GitHub Actions CI matrix for Ruby 3.1-3.3 and Rails 8.0/8.1"
```

---

## Task 7: Update README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Replace the Ruby 4.0 claim with accurate requirements**

Find:

```markdown
SQLite FTS5 full-text search for Rails/ActiveRecord.
```

No explicit "Ruby >= 4.0" line exists, but the gemspec did. Add a small requirements section under the opening paragraph:

```markdown
## Requirements

- Ruby 3.1+
- Rails 8.0+
- SQLite 3.34+ (if using typo tolerance)
```

- [ ] **Step 2: Add CI badge**

Below the main heading, add:

```markdown
[![CI](https://github.com/bendangelo/full_search/actions/workflows/ci.yml/badge.svg)](https://github.com/bendangelo/full_search/actions/workflows/ci.yml)
```

- [ ] **Step 3: Verify README renders**

Run: `bundle exec ruby -e 'require "redcarpet"' 2>/dev/null && echo "OK" || echo "redcarpet not installed, skip"`
Or just open the file and visually confirm Markdown is intact.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: update README with Ruby/Rails requirements and CI badge"
```

---

## Task 8: Add CHANGELOG.md

**Files:**
- Create: `CHANGELOG.md`

- [ ] **Step 1: Create changelog**

```markdown
# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

### Added

- GitHub Actions CI matrix testing Ruby 3.1, 3.2, 3.3 against Rails 8.0 and 8.1.
- StandardRB linting via `rake standard` and `bin/lint`.
- Gemspec signing metadata (`cert_chain`, `signing_key`) for future signed releases.
- `required_rubygems_version` to gemspec.
- README requirements section and CI badge.
- `CHANGELOG.md`.

### Changed

- Lowered `required_ruby_version` from `4.0.0` to `3.1.0`.
- `Gemfile` now reads the Rails version from `RAILS_VERSION` env var for CI matrix support.

### Removed

- Committed `.gem` files from `pkg/`.
- Committed `.ruby-lsp/` directory.
- Committed `Gemfile.lock` from version control.

## 0.2.0

- Initial public release with FTS5-backed full-text search, DSL, filters, highlighting, typo tolerance, and background jobs.
```

- [ ] **Step 2: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs: add CHANGELOG.md"
```

---

## Task 9: Final verification

- [ ] **Step 1: Run the full local test suite**

```bash
bundle exec rake test
```
Expected: all tests pass.

- [ ] **Step 2: Run StandardRB**

```bash
bundle exec rake standard
```
Expected: no offenses.

- [ ] **Step 3: Test Rails 8.0 compatibility locally**

```bash
RAILS_VERSION=8.0 bundle update activerecord activejob railties
bundle exec rake test
```
Expected: all tests pass.

- [ ] **Step 4: Restore Rails 8.1 for local development (optional)**

```bash
bundle update activerecord activejob railties
```

- [ ] **Step 5: Inspect git status**

```bash
git status
```
Expected: working tree clean, no untracked files other than possibly `Gemfile.lock` (ignored).

- [ ] **Step 6: Review recent commits**

```bash
git log --oneline -10
```

Expected to see separate commits for:
1. gemspec metadata
2. Gemfile env var
3. cleanup
4. StandardRB setup
5. StandardRB auto-fix
6. CI workflow
7. README update
8. CHANGELOG

---

## Spec coverage check

| Spec requirement | Implementing task |
|------------------|-------------------|
| Ruby `>= 3.1.0` | Task 1 |
| Rails 8.0 + 8.1 CI matrix | Task 2, Task 6 |
| GitHub Actions CI file | Task 6 |
| `required_rubygems_version` | Task 1 |
| Signing metadata | Task 1 |
| `CHANGELOG.md` | Task 8 |
| Remove `pkg/*.gem` | Task 3 |
| Ignore `.ruby-lsp/` | Task 3 |
| Remove `Gemfile.lock` from git | Task 3 |
| StandardRB linting | Task 4, Task 5 |
| README update | Task 7 |

## Notes for implementer

- Do **not** change any library behavior, test assertions, or public APIs.
- The StandardRB auto-fix commit should be a single mechanical commit; do not mix it with other changes.
- If StandardRB reports offenses it cannot auto-fix, stop and ask before hand-editing.
- `Gemfile.lock` will be generated locally by `bundle install` but must remain untracked thanks to `.gitignore`.
- No certificate files should be created or committed as part of this work.
