# frozen_string_literal: true

module FullSearch
  module VirtualTablesPatch
    def virtual_tables
      super.reject { |_, options| options.first.nil? }
    end
  end

  module SchemaDumperPatch
    private

    def virtual_tables(stream)
      virtual_tables = @connection.virtual_tables.reject { |name, _| ignored?(name) }

      if virtual_tables.any?
        stream.puts
        stream.puts "  # Virtual tables defined in this database."
        stream.puts "  # Note that virtual tables may not work with other database engines. Be careful if changing database."
        virtual_tables.sort.each do |table_name, options|
          module_name, arguments = options
          next if module_name.nil? || arguments.nil?

          stream.puts "  create_virtual_table #{table_name.inspect}, #{module_name.inspect}, #{arguments.split(", ").inspect}"
        end
      end
    end
  end
end

ActiveSupport.on_load(:active_record) do
  begin
    require "active_record/connection_adapters/sqlite3_adapter"
  rescue LoadError
    next
  end

  if defined?(ActiveRecord::ConnectionAdapters::SQLite3Adapter)
    ActiveRecord::ConnectionAdapters::SQLite3Adapter.prepend(FullSearch::VirtualTablesPatch)
  end

  if defined?(ActiveRecord::ConnectionAdapters::SQLite3::SchemaDumper)
    ActiveRecord::ConnectionAdapters::SQLite3::SchemaDumper.prepend(FullSearch::SchemaDumperPatch)
  end
end
