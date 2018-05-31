# frozen_string_literal: true

require "optic/rails/railtie"

require "rgl/adjacency"
require "rgl/dot"
require "rgl/dijkstra"

module Optic
  module Rails
    # From https://gist.github.com/hongo35/7513104
    class PageRank
      EPS = 0.00001

      def initialize(matrix)
        @dim = matrix.size

        @p = []
        @dim.times do |i|
          @p[i] = []
          @dim.times do |j|
            total = matrix[i].inject(:+)
            @p[i][j] = total == 0 ? 0 : matrix[i][j] / (total * 1.0)
          end
        end
      end

      def calc(curr, alpha)
        loop do
          prev = curr.clone

          @dim.times do |i|
            ip = 0
            @dim.times do |j|
              ip += @p.transpose[i][j] * prev[j]
            end
            curr[i] = (alpha * ip) + ((1.0 - alpha) / @dim * 1.0)
          end

          err = 0
          @dim.times do |i|
            err += (prev[i] - curr[i]).abs
          end

          if err < EPS
            return curr
          elsif err.nan?
            raise "PageRank failed" # TODO just ignore and move on
          end
        end
      end
    end

    def self.qualified_primary_key(vertex)
      %Q|"#{vertex.table_name}"."#{vertex.primary_key}"|
    end

    def self.entity_graph
      graph = RGL::DirectedAdjacencyGraph.new

      base_klass = ApplicationRecord rescue ActiveRecord::Base
      klasses = ObjectSpace.each_object(Class).find_all { |klass| klass < base_klass }.find_all(&:table_exists?)

      graph.add_vertices *klasses

      klasses.each do |klass|
        klass.reflect_on_all_associations(:belongs_to).each do |reflection|
          next if reflection.options[:polymorphic] # TODO

          # TODO should the source be reflection.active_record or klass?
          graph.add_edge klass, reflection.klass
        end
      end

      graph
    end

    def self.get_entities
      graph = entity_graph

      # TODO send entire graph to server
      entities = graph.vertices.map { |v| { name: v.name, table_name: v.table_name } }

      {
        schema_version: ActiveRecord::Migrator.current_version,
        entities: entities # TODO also return entity attributes?
      }
    end

    # Try to be defensive with our DB connection:
    # 1) Check a connection out from the thread pool instead of using an implicit one
    # 2) Make the connection read-only
    # 3) Time out any queries that take more than 100ms
    def self.with_connection
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        connection.transaction do
          connection.execute "SET TRANSACTION READ ONLY"
          connection.execute "SET LOCAL statement_timeout = 100"
          yield connection
        end
      end
    end

    def self.get_metrics(pivot_name)
      with_connection do |connection|
        result = { entity_totals: [] }
        pivot = nil

        if pivot_name
          pivot = pivot_name.constantize
          result[:pivot_name] = pivot.name
          result[:pivot_values] = connection.execute(pivot.unscoped.select("*").to_sql).to_a
          result[:pivoted_totals] = []
        end

        graph = entity_graph

        # Spit out counts for each entity by the customer pivot

        edge_weights = lambda { |_| 1 }

        graph.vertices.each do |vertex|
          count_query = vertex.unscoped.select("COUNT(*)").to_sql
          result[:entity_totals] << { name: vertex.name, total: connection.execute(count_query).first["count"] }

          if pivot && vertex != pivot
            # TODO weight edges to give preference to non-optional belongs_to (and other attributes?)
            path = graph.dijkstra_shortest_path(edge_weights, vertex, pivot)
            if path
              # Generate a SQL query to count the number of vertex instances grouped by pivot id, with appropriate joins from the path
              belongs_to_names = path.each_cons(2).map do |join_from, join_to|
                # TODO we shouldn't have to look up the edge again - use a graph model that allows us to annotate the edges with the reflections
                reflections = join_from.reflect_on_all_associations(:belongs_to).find_all { |reflection| !reflection.options[:polymorphic] && reflection.klass == join_to }
                # TODO warn if more than one reflection
                reflection = reflections.min_by { |r| r.options.size }
                reflection.name
              end

              joins = belongs_to_names.reverse.inject { |acc, elt| { elt => acc } }
              query = vertex.unscoped.joins(joins).group(qualified_primary_key(pivot)).select(qualified_primary_key(pivot), "COUNT(*)").to_sql

              result[:pivoted_totals] << { entity_name: vertex.name, totals: Hash[connection.execute(query).map { |record| [record["id"], record["count"]] }] }
            else
              # TODO print warning that we couldn't find a path from the pivot to the vertex
            end
          end
        end

        result
      end
    end
  end
end
