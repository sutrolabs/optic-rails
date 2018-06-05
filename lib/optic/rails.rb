# frozen_string_literal: true

require "optic/rails/railtie"

module Optic
  module Rails
    class << self
      def entities
        with_connection do
          {
            schema_version: ActiveRecord::Migrator.current_version,
            entities: active_record_klasses.map do |klass|
              {
                name: klass.name,
                table_name: klass.table_name,
                entity_attribute_names: klass.attribute_names,
                table_exists: klass.table_exists?,
                associations: klass.reflect_on_all_associations.map do |reflection|
                  {
                    name: reflection.name,
                    macro: reflection.macro,
                    options: reflection.options.map { |k, v| [k, v.to_s] }.to_h,
                    klass_name: reflection.options[:polymorphic] ? nil : reflection.klass.name,
                  }
                end
              }
            end
          }
        end
      end

      def metrics(instructions)
        with_connection do |connection|
          instructions.map do |instruction|
            name = instruction["entity"]
            entity = name.constantize.unscoped

            query =
              if pivot_name = instruction["pivot"]
                pivot = pivot_name.constantize
                join_path = instruction["join_path"]
                joins = join_path.reverse.map(&:to_sym).inject { |acc, elt| { elt => acc } }
                entity.joins(joins).group(qualified_primary_key(pivot)).select(qualified_primary_key(pivot), "COUNT(*)").to_sql # TODO collect other pivot instance columns here
              else
                entity.select("COUNT(*)").to_sql
              end

            { metric_configuration_id: instruction["metric_configuration_id"], result: connection.execute(query).to_a }
          end
        end
      end

      def instances(pivot_name)
        with_connection do |connection|
          pivot = pivot_name.constantize
          { instances: connection.execute(pivot.unscoped.select("*").to_sql).to_a }
        end
      end

      private

      # Try to be defensive with our DB connection:
      # 1) Check a connection out from the thread pool instead of using an implicit one
      # 2) Make the connection read-only
      # 3) Time out any queries that take more than 100ms
      def with_connection
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          connection.transaction do
            connection.execute "SET TRANSACTION READ ONLY"
            connection.execute "SET LOCAL statement_timeout = 100"
            yield connection
          end
        end
      end

      def qualified_primary_key(entity)
        %Q|"#{entity.table_name}"."#{entity.primary_key}"|
      end

      def active_record_klasses
        base_klass = ApplicationRecord rescue ActiveRecord::Base
        ObjectSpace.each_object(Class).find_all { |klass| klass < base_klass }
      end
    end
  end
end
