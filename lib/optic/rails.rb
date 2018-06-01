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
                attribute_names: klass.attribute_names,
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

      def metrics
        with_connection do |connection|
          result = { entity_totals: [] }
          active_record_klasses.find_all(&:table_exists?).each do |klass|
            count_query = klass.unscoped.select("COUNT(*)").to_sql
            result[:entity_totals] << { name: klass.name, total: connection.execute(count_query).first["count"] }
          end

          result
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

      def active_record_klasses
        base_klass = ApplicationRecord rescue ActiveRecord::Base
        ObjectSpace.each_object(Class).find_all { |klass| klass < base_klass }
      end
    end
  end
end
