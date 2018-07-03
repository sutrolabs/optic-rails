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
            entity = entity_for_entity_name name

            query =
              if pivot_name = instruction["pivot"]
                # TODO this is a terrible hack to extract zero-valued pivot
                # instances. The right thing to do is select from the pivot
                # table and LEFT OUTER JOIN to the entity table, which results
                # in a much simpler query, but it means we have to rewrite the
                # pathfinding logic in the server to find paths using has_many
                # associations instead of belongs_to associations, which might
                # be less accurate for a bunch of reasons. For now, we're doing
                # an INNER JOIN selecting from the entity table and then
                # selecting every possible pivot value as a UNION, throwing out
                # the duplicates.
                pivot = entity_for_entity_name pivot_name
                join_path = instruction["join_path"]
                joins = join_path.reverse.map(&:to_sym).inject { |acc, elt| { elt => acc } }

                columns = [
                  %Q|#{qualified_primary_key(pivot)} AS "primary_key"|,
                  %Q|#{qualified_column(pivot, instruction["pivot_attribute_name"])} AS "pivot_attribute_name"|,
                ]

                join_select = entity
                              .joins(joins)
                              .group(qualified_primary_key(pivot))
                              .select(*columns, 'COUNT(*) AS "count"')
                              .to_sql

                instance_select = pivot
                                  .select(*columns, '0 AS "count"')
                                  .to_sql

                union_sql = <<~"SQL"
                              SELECT "pivot_values"."primary_key", "pivot_values"."pivot_attribute_name", MAX("pivot_values"."count") AS "count"
                                FROM (#{join_select} UNION ALL #{instance_select}) AS "pivot_values"
                                GROUP BY "pivot_values"."primary_key", "pivot_values"."pivot_attribute_name"
                            SQL
              else
                entity.select("COUNT(*)").to_sql
              end

            { metric_configuration_id: instruction["metric_configuration_id"], result: connection.execute(query).to_a }
          end
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

      def entity_for_entity_name(entity_name)
        entity_name.constantize.unscoped
      end

      def qualified_column(entity, attribute)
        %Q|"#{entity.table_name}"."#{attribute}"|
      end

      def qualified_primary_key(entity)
        qualified_column(entity, entity.primary_key)
      end

      def active_record_klasses
        base_klass = ApplicationRecord rescue ActiveRecord::Base
        ObjectSpace.each_object(Class).find_all { |klass| klass < base_klass }
      end
    end
  end
end
