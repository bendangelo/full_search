# frozen_string_literal: true

module FullSearch
  module Model
    extend ActiveSupport::Concern

    class_methods do
      def full_search(query_or_options = nil, filters: {}, include_soft_deleted: false, limit: nil, offset: nil, highlight: false, highlight_fields: false, matching_strategy: nil, &block)
        if block_given? || query_or_options.is_a?(Hash)
          @full_search_dsl ||= FullSearch::Dsl.new(self)
          @full_search_dsl.tokenize(query_or_options[:tokenize]) if query_or_options.is_a?(Hash) && query_or_options.key?(:tokenize)
          @full_search_dsl.instance_eval(&block) if block_given?
          FullSearch::Index.ensure_table!(self)
          FullSearch::Callbacks.install!(self)
          include InstanceMethods
          FullSearch.models << self unless FullSearch.models.include?(self)
          @full_search_dsl
        else
          FullSearch::Search.new(self, query_or_options, filters: filters, include_soft_deleted: include_soft_deleted, limit: limit, offset: offset, highlight: highlight, highlight_fields: highlight_fields, matching_strategy: matching_strategy).relation
        end
      end

      def full_search_dsl
        @full_search_dsl
      end

      def full_search_ids(query, filters: {}, include_soft_deleted: false, limit: 1000)
        full_search(query, filters: filters, include_soft_deleted: include_soft_deleted, limit: limit).pluck(:id)
      end

      def rebuild!
        FullSearch::Index.rebuild!(self)
      end

      def optimize!
        FullSearch::Index.optimize!(self)
      end

      def reindex!
        FullSearch::Index.reindex_source_fields!(self)
      end
    end

    included do |base|
      unless base.respond_to?(:search)
        base.singleton_class.alias_method :search, :full_search
      end
    end

    module InstanceMethods
      attr_accessor :full_search_snippet, :full_search_highlight_fields

      def full_search_text_for(field_name)
        dsl = self.class.full_search_dsl
        field = dsl.fields.find { |f| f.name == field_name.to_s || f.as == field_name.to_s }
        return nil unless field

        field.source ? instance_exec(&field.source) : public_send(field.name)
      end
    end
  end
end
