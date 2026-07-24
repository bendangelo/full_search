# frozen_string_literal: true

require "full_search/errors"

module FullSearch
  module Callbacks
    def self.install!(model)
      return if model.instance_variable_get(:@__full_search_callbacks_installed)

      dsl = model.full_search_dsl

      source_fields = dsl.fields.select(&:source)
      return if source_fields.empty?

      model.after_save_commit do
        next if FullSearch.bulk_importing?(self.class)
        FullSearch::Callbacks.reindex_record!(self)
      end

      model.after_destroy_commit do
        next if FullSearch.bulk_importing?(self.class)
        FullSearch::Callbacks.remove_record!(self)
      end

      dsl.fields.each do |field|
        next unless field.reindex_on

        assoc_class = associated_class(model, field.reindex_on)
        assoc_class&.after_save_commit do |record|
          next if FullSearch.bulk_importing?(record.class)
          FullSearch::Callbacks.reindex_dependents!(record, model, field)
        end
        assoc_class&.after_destroy_commit do |record|
          next if FullSearch.bulk_importing?(record.class)
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

      model_name = record.class.name
      dsl.fields.each do |field|
        next unless field.source

        if model_name && field.async_source
          FullSearch::ReindexJob.perform_later(model_name, record.id, field.name)
        else
          reindex_field!(record, field.name)
        end
      end
    end

    def self.reindex_field!(record, field_name)
      dsl = record.class.full_search_dsl
      field = dsl.fields.find { |f| f.name == field_name }
      return unless field&.source

      value = FullSearch::Model.evaluate_source(record, field)
      table = qt(FullSearch::Index.fts_table_name(record.class))
      conn = connection_for(record.class)
      conn.execute(
        "UPDATE #{table} SET #{qc(field.as || field.name)} = #{q(value.to_s)} WHERE rowid = #{q(record.id)}"
      )
    rescue ActiveRecord::StatementInvalid => e
      raise_missing_table_or_original(e, record.class)
    end

    def self.remove_record!(record)
      table = qt(FullSearch::Index.fts_table_name(record.class))
      conn = connection_for(record.class)
      conn.execute("DELETE FROM #{table} WHERE rowid = #{q(record.id)}")
    rescue ActiveRecord::StatementInvalid => e
      raise_missing_table_or_original(e, record.class)
    end

    def self.reindex_dependents!(parent_record, dependent_model, field)
      fk = association_key(dependent_model, field.reindex_on)
      conn = ActiveRecord::Base.connection
      sql = "SELECT id FROM #{qt(dependent_model.table_name)} WHERE #{qc(fk)} = #{q(parent_record.id)}"
      dependent_ids = conn.execute(sql).map { |r| r["id"] }

      dependent_ids.each do |dep_id|
        if field.async
          FullSearch::ReindexJob.perform_later(dependent_model.name, dep_id, field.name)
        else
          dependent = dependent_model.find_by(id: dep_id)
          reindex_field!(dependent, field.name) if dependent
        end
      end
    end

    class << self
      include FullSearch::Quoting
    end

    def self.connection
      ActiveRecord::Base.connection
    end

    def self.associated_class(model, association_name)
      reflection = model.reflect_on_association(association_name.to_sym)
      reflection&.klass
    end

    def self.association_key(model, association_name)
      reflection = model.reflect_on_association(association_name.to_sym)
      reflection&.foreign_key&.to_s || "#{association_name}_id"
    end

    def self.connection_for(klass)
      klass.connection
    rescue NoMethodError
      ActiveRecord::Base.connection
    end

    def self.raise_missing_table_or_original(error, _model_class)
      if error.message.include?("no such table")
        return
      end
      raise error
    end
    private_class_method :raise_missing_table_or_original
  end
end
