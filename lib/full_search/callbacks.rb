# frozen_string_literal: true

module FullSearch
  module Callbacks
    def self.install!(model)
      return if model.instance_variable_get(:@__full_search_callbacks_installed)

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

    def self.reset_installed_flag!(model)
      model.instance_variable_set(:@__full_search_callbacks_installed, false)
    end

    def self.reindex_record!(record)
      dsl = record.class.full_search_dsl
      return unless dsl

      dsl.fields.each do |field|
        next unless field.source

        reindex_field!(record, field.name)
      end
    end

    def self.reindex_field!(record, field_name)
      dsl = record.class.full_search_dsl
      field = dsl.fields.find { |f| f.name == field_name }
      return unless field&.source

      value = record.instance_exec(&field.source)
      table = FullSearch::Index.fts_table_name(record.class)
      quoted_value = ActiveRecord::Base.connection.quote(value.to_s)
      ActiveRecord::Base.connection.execute(
        "UPDATE #{table} SET #{field.name} = #{quoted_value} WHERE rowid = #{record.id}"
      )
    end

    def self.remove_record!(record)
      table = FullSearch::Index.fts_table_name(record.class)
      ActiveRecord::Base.connection.execute("DELETE FROM #{table} WHERE rowid = #{record.id}")
    end

    def self.reindex_dependents!(parent_record, dependent_model, field)
      fk = association_key(dependent_model, field.reindex_on)
      sql = "SELECT id FROM #{dependent_model.table_name} WHERE #{fk} = #{parent_record.id}"
      dependent_ids = ActiveRecord::Base.connection.execute(sql).map { |r| r["id"] }

      dependent_ids.each do |dep_id|
        if field.async
          FullSearch::ReindexJob.perform_later(dependent_model.name, dep_id, field.name)
        else
          dependent = dependent_model.find_by(id: dep_id)
          reindex_field!(dependent, field.name) if dependent
        end
      end
    end

    def self.associated_class(model, association_name)
      reflection = model.reflect_on_association(association_name.to_sym)
      reflection&.klass
    end

    def self.association_key(model, association_name)
      reflection = model.reflect_on_association(association_name.to_sym)
      reflection&.foreign_key&.to_s || "#{association_name}_id"
    end
  end
end
