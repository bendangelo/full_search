# frozen_string_literal: true

require "ostruct"

module FullSearch
  class Index
    class << self
      def ensure_table!(model)
        return unless FullSearch::Index.sqlite?

        conn = connection
        dsl = model.full_search_dsl
        return unless dsl

        create_metadata_table!

        fts_was_created = false
        unless table_exists?(model)
          conn.execute(create_virtual_table_sql(model))
          fts_was_created = true
        end

        trigram_was_created = false
        if dsl.typo_tolerance? && !trigram_table_exists?(model)
          FullSearch::Typo.warn_unsupported! unless FullSearch::Typo.supported?
          conn.execute(create_trigram_virtual_table_sql(model))
          trigram_was_created = true
        end

        if fts_was_created || trigram_was_created
          conn.execute(backfill_sql(model)) if fts_was_created
          conn.execute(backfill_trigram_sql(model)) if trigram_was_created
          reindex_source_fields!(model) if dsl.fields.any?(&:source)
          store_config_hash!(model)
        end

        ensure_triggers!(model) if model_table_exists?(model)
      end

      def rebuild!(model)
        return unless FullSearch::Index.sqlite?

        dsl = model.full_search_dsl
        return unless dsl
        conn = connection

        create_metadata_table!

        with_rebuild_lock(model) do
          drop_triggers!(model)
          conn.execute("DROP TABLE IF EXISTS #{fts_table_name(model)};")
          conn.execute("DROP TABLE IF EXISTS #{trigram_table_name(model)};")
          conn.execute(create_virtual_table_sql(model))
          if dsl.typo_tolerance?
            FullSearch::Typo.warn_unsupported! unless FullSearch::Typo.supported?
            conn.execute(create_trigram_virtual_table_sql(model))
          end
          conn.execute(backfill_sql(model))
          conn.execute(backfill_trigram_sql(model)) if dsl.typo_tolerance?
          reindex_source_fields!(model) if dsl.fields.any?(&:source)
          create_triggers!(model)
          optimize!(model)
          store_config_hash!(model, rebuilt_at: Time.current)
        end
      end

      def rebuild_if_needed!(model)
        return false unless FullSearch::Index.sqlite?

        dsl = model.full_search_dsl
        return false unless dsl

        create_metadata_table!
        ensure_table!(model)

        stored = stored_config_hash(model)
        if stored && stored == dsl.config_hash
          false
        else
          rebuild!(model)
          true
        end
      end

      def optimize!(model)
        connection.execute("INSERT INTO #{fts_table_name(model)}(#{fts_table_name(model)}) VALUES('optimize');")
      end

      def reindex_source_fields!(model)
        model.find_each do |record|
          FullSearch::Callbacks.reindex_record!(record)
        end
      end

      def drop!(model)
        drop_triggers!(model)
        connection.execute("DROP TABLE IF EXISTS #{fts_table_name(model)};")
        connection.execute("DROP TABLE IF EXISTS #{trigram_table_name(model)};")
      end

      def fts_table_name(model)
        "#{model.table_name}_fts"
      end

      def trigram_table_name(model)
        "#{fts_table_name(model)}_trigram"
      end

      def sqlite?
        connection.adapter_name.downcase.include?("sqlite")
      end

      def stored_config_hash(model)
        row = connection.execute(
          "SELECT config_hash FROM full_search_index_versions WHERE table_name=#{q(model.table_name)}"
        ).first
        row&.[]("config_hash")
      end

      private

      def connection
        ActiveRecord::Base.connection
      end

      def q(value)
        connection.quote(value)
      end

      def model_table_exists?(model)
        connection.execute(
          "SELECT name FROM sqlite_master WHERE type='table' AND name=#{q(model.table_name)} LIMIT 1"
        ).any?
      end

      def table_exists?(model)
        connection.execute(
          "SELECT name FROM sqlite_master WHERE type='table' AND name=#{q(fts_table_name(model))} LIMIT 1"
        ).any?
      end

      def create_metadata_table!
        connection.execute(<<~SQL)
          CREATE TABLE IF NOT EXISTS full_search_index_versions (
            table_name TEXT PRIMARY KEY,
            config_hash TEXT NOT NULL,
            rebuilt_at DATETIME NOT NULL
          );
        SQL
      end

      def store_config_hash!(model, rebuilt_at: Time.current)
        sql = "INSERT INTO full_search_index_versions (table_name, config_hash, rebuilt_at) VALUES (#{q(model.table_name)}, #{q(model.full_search_dsl.config_hash)}, #{q(rebuilt_at)})
               ON CONFLICT(table_name) DO UPDATE SET config_hash=excluded.config_hash, rebuilt_at=excluded.rebuilt_at;"
        connection.execute(sql)
      end

      def create_virtual_table_sql(model)
        dsl = model.full_search_dsl
        columns = (dsl.fields + dsl.filters.map { |f| OpenStruct.new(name: f.name, unindexed?: true) })
        column_list = columns.map { |c| c.respond_to?(:unindexed?) && c.unindexed? ? "#{c.name} UNINDEXED" : c.name }.join(", ")

        <<~SQL
          CREATE VIRTUAL TABLE #{fts_table_name(model)} USING fts5(
            #{column_list},
            tokenize='#{dsl.tokenize}'
          );
        SQL
      end

      def backfill_sql(model)
        dsl = model.full_search_dsl
        cols = (dsl.fields + dsl.filters)
        select = cols.map do |c|
          if c.respond_to?(:source) && c.source
            source_value_sql(c.source)
          else
            "#{model.table_name}.#{c.name}"
          end
        end.join(", ")

        <<~SQL
          INSERT INTO #{fts_table_name(model)}(rowid, #{cols.map(&:name).join(", ")})
          SELECT #{model.table_name}.id, #{select} FROM #{model.table_name};
        SQL
      end

      def source_value_sql(_source_proc)
        "''"
      end

      def ensure_triggers!(model)
        existing = connection.execute(
          "SELECT name FROM sqlite_master WHERE type='trigger' AND tbl_name=#{q(model.table_name)}"
        ).map { |r| r["name"] }

        create_triggers!(model) unless (trigger_names(model) - existing).empty?
      end

      def create_triggers!(model)
        connection.execute(insert_trigger_sql(model))
        connection.execute(delete_trigger_sql(model))
        connection.execute(update_trigger_sql(model))
        if model.full_search_dsl.soft_delete_column
          connection.execute(soft_delete_removal_trigger_sql(model))
        end
        if model.full_search_dsl.typo_tolerance?
          connection.execute(insert_trigram_trigger_sql(model))
          connection.execute(delete_trigram_trigger_sql(model))
          connection.execute(update_trigram_trigger_sql(model))
        end
      end

      def drop_triggers!(model)
        (trigger_names(model) + trigram_trigger_names(model)).each do |name|
          connection.execute("DROP TRIGGER IF EXISTS #{name};")
        end
      end

      def trigger_names(model)
        base = fts_table_name(model)
        names = %W[#{base}_ai #{base}_ad #{base}_au]
        names << "#{base}_au_soft_delete" if model.full_search_dsl.soft_delete_column
        names
      end

      def trigram_trigger_names(model)
        base = trigram_table_name(model)
        %W[#{base}_ai #{base}_ad #{base}_au]
      end

      def insert_trigger_sql(model)
        dsl = model.full_search_dsl
        cols = dsl.fields + dsl.filters
        values = cols.map { |c| column_ref(c, prefix: "new") }.join(", ")

        <<~SQL
          CREATE TRIGGER #{trigger_names(model).first} AFTER INSERT ON #{model.table_name} BEGIN
            INSERT INTO #{fts_table_name(model)}(rowid, #{col_names(cols)})
            VALUES (new.id, #{values});
          END;
        SQL
      end

      def delete_trigger_sql(model)
        <<~SQL
          CREATE TRIGGER #{trigger_names(model)[1]} AFTER DELETE ON #{model.table_name} BEGIN
            DELETE FROM #{fts_table_name(model)} WHERE rowid = old.id;
          END;
        SQL
      end

      def update_trigger_sql(model)
        dsl = model.full_search_dsl
        cols = dsl.fields + dsl.filters
        values = cols.map { |c| column_ref(c, prefix: "new") }.join(", ")
        cols_str = col_names(cols)
        fts_table = fts_table_name(model)

        when_clause = SoftDelete.active_update_clause(model)

        <<~SQL
          CREATE TRIGGER #{trigger_names(model)[2]} AFTER UPDATE ON #{model.table_name} #{when_clause}
          BEGIN
            DELETE FROM #{fts_table} WHERE rowid = old.id;
            INSERT INTO #{fts_table}(rowid, #{cols_str})
            VALUES (new.id, #{values});
          END;
        SQL
      end

      def soft_delete_removal_trigger_sql(model)
        dsl = model.full_search_dsl
        fts_table = fts_table_name(model)
        when_clause = SoftDelete.soft_delete_remove_clause(model)

        <<~SQL
          CREATE TRIGGER #{trigger_names(model)[2]}_soft_delete AFTER UPDATE ON #{model.table_name} #{when_clause}
          BEGIN
            DELETE FROM #{fts_table} WHERE rowid = old.id;
          END;
        SQL
      end

      def trigram_table_exists?(model)
        connection.execute(
          "SELECT name FROM sqlite_master WHERE type='table' AND name=#{q(trigram_table_name(model))} LIMIT 1"
        ).any?
      end

      def create_trigram_virtual_table_sql(model)
        dsl = model.full_search_dsl
        columns = (dsl.fields + dsl.filters.map { |f| OpenStruct.new(name: f.name, unindexed?: true) })
        column_list = columns.map { |c| c.respond_to?(:unindexed?) && c.unindexed? ? "#{c.name} UNINDEXED" : c.name }.join(", ")

        <<~SQL
          CREATE VIRTUAL TABLE #{trigram_table_name(model)} USING fts5(
            #{column_list},
            tokenize='trigram'
          );
        SQL
      end

      def backfill_trigram_sql(model)
        dsl = model.full_search_dsl
        cols = (dsl.fields + dsl.filters)
        select = cols.map do |c|
          if c.respond_to?(:source) && c.source
            source_value_sql(c.source)
          else
            "#{model.table_name}.#{c.name}"
          end
        end.join(", ")

        <<~SQL
          INSERT INTO #{trigram_table_name(model)}(rowid, #{cols.map(&:name).join(", ")})
          SELECT #{model.table_name}.id, #{select} FROM #{model.table_name};
        SQL
      end

      def insert_trigram_trigger_sql(model)
        dsl = model.full_search_dsl
        cols = dsl.fields + dsl.filters
        values = cols.map { |c| column_ref(c, prefix: "new") }.join(", ")

        <<~SQL
          CREATE TRIGGER #{trigram_trigger_names(model).first} AFTER INSERT ON #{model.table_name} BEGIN
            INSERT INTO #{trigram_table_name(model)}(rowid, #{col_names(cols)})
            VALUES (new.id, #{values});
          END;
        SQL
      end

      def delete_trigram_trigger_sql(model)
        <<~SQL
          CREATE TRIGGER #{trigram_trigger_names(model)[1]} AFTER DELETE ON #{model.table_name} BEGIN
            DELETE FROM #{trigram_table_name(model)} WHERE rowid = old.id;
          END;
        SQL
      end

      def update_trigram_trigger_sql(model)
        dsl = model.full_search_dsl
        cols = dsl.fields + dsl.filters
        values = cols.map { |c| column_ref(c, prefix: "new") }.join(", ")
        cols_str = col_names(cols)
        trigram_table = trigram_table_name(model)

        when_clause = SoftDelete.active_update_clause(model)

        <<~SQL
          CREATE TRIGGER #{trigram_trigger_names(model)[2]} AFTER UPDATE ON #{model.table_name} #{when_clause}
          BEGIN
            DELETE FROM #{trigram_table} WHERE rowid = old.id;
            INSERT INTO #{trigram_table}(rowid, #{cols_str})
            VALUES (new.id, #{values});
          END;
        SQL
      end

      def col_names(cols)
        cols.map(&:name).join(", ")
      end

      def column_ref(col, prefix:)
        if col.respond_to?(:source) && col.source
          "''"
        else
          "#{prefix}.#{col.name}"
        end
      end

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
    end
  end
end
