# frozen_string_literal: true
module GraphQL
  module Execution
    # Execute multiple queries under the same multiplex "umbrella".
    # They can share a batching context and reduce redundant database hits.
    #
    # The flow is:
    #
    # - Multiplex instrumentation setup
    # - Query instrumentation setup
    # - Analyze the multiplex + each query
    # - Begin each query
    # - Resolve lazy values, breadth-first across all queries
    # - Finish each query (eg, get errors)
    # - Query instrumentation teardown
    # - Multiplex instrumentation teardown
    #
    # If one query raises an application error, all queries will be in undefined states.
    #
    # Validation errors and {GraphQL::ExecutionError}s are handled in isolation:
    # one of these errors in one query will not affect the other queries.
    #
    # @see {Schema#multiplex} for public API
    # @api private
    class Multiplex
      # Used internally to signal that the query shouldn't be executed
      # @api private
      NO_OPERATION = {}.freeze

      include Tracing::Traceable

      attr_reader :context, :queries, :schema, :max_complexity, :dataloader
      def initialize(schema:, queries:, context:, max_complexity:)
        @schema = schema
        @queries = queries
        @queries.each { |q| q.multiplex = self }
        @context = context
        @dataloader = @context[:dataloader] ||= @schema.dataloader_class.new
        @tracers = schema.tracers + (context[:tracers] || [])
        # Support `context: {backtrace: true}`
        if context[:backtrace] && !@tracers.include?(GraphQL::Backtrace::Tracer)
          @tracers << GraphQL::Backtrace::Tracer
        end
        @max_complexity = max_complexity
      end

      class << self
        # @param schema [GraphQL::Schema]
        # @param queries [Array<GraphQL::Query, Hash>]
        # @param context [Hash]
        # @param max_complexity [Integer, nil]
        # @return [Array<Hash>] One result per query
        def run_all(schema, query_options, context: {}, max_complexity: schema.max_complexity)
          queries = query_options.map do |opts|
            case opts
            when Hash
              GraphQL::Query.new(schema, nil, **opts)
            when GraphQL::Query
              opts
            else
              raise "Expected Hash or GraphQL::Query, not #{opts.class} (#{opts.inspect})"
            end
          end

          multiplex = self.new(schema: schema, queries: queries, context: context, max_complexity: max_complexity)
          multiplex.trace("execute_multiplex", { multiplex: multiplex }) do
            GraphQL::Execution::Instrumentation.apply_instrumenters(multiplex) do
              schema = multiplex.schema
              multiplex_analyzers = schema.multiplex_analyzers
              queries = multiplex.queries
              if multiplex.max_complexity
                multiplex_analyzers += [GraphQL::Analysis::AST::MaxQueryComplexity]
              end

              schema.analysis_engine.analyze_multiplex(multiplex, multiplex_analyzers)

              # Since this is basically the batching context,
              # share it for a whole multiplex
              multiplex.context[:interpreter_instance] ||= multiplex.schema.query_execution_strategy.new
              # Do as much eager evaluation of the query as possible
              results = []
              queries.each_with_index do |query, idx|
                multiplex.dataloader.append_job {
                  operation = query.selected_operation
                  result = if operation.nil? || !query.valid? || query.context.errors.any?
                    NO_OPERATION
                  else
                    begin
                      # The batching context is shared by the multiplex,
                      # so fetch it out and use that instance.
                      interpreter =
                        query.context.namespace(:interpreter)[:interpreter_instance] =
                        multiplex.context[:interpreter_instance]
                      interpreter.evaluate(query)
                    rescue GraphQL::ExecutionError => err
                      query.context.errors << err
                      NO_OPERATION
                    end
                  end
                  results[idx] = result
                }
              end

              multiplex.dataloader.run

              # Then, work through lazy results in a breadth-first way
              multiplex.dataloader.append_job {
                interpreter = multiplex.context[:interpreter_instance]
                interpreter.sync_lazies(multiplex: multiplex)
              }
              multiplex.dataloader.run

              # Then, find all errors and assign the result to the query object
              results.each_with_index do |data_result, idx|
                query = queries[idx]
                # Assign the result so that it can be accessed in instrumentation
                query.result_values = if data_result.equal?(NO_OPERATION)
                  if !query.valid? || query.context.errors.any?
                    # A bit weird, but `Query#static_errors` _includes_ `query.context.errors`
                    { "errors" => query.static_errors.map(&:to_h) }
                  else
                    data_result
                  end
                else
                  result = {
                    "data" => query.context.namespace(:interpreter)[:runtime].final_result
                  }

                  if query.context.errors.any?
                    error_result = query.context.errors.map(&:to_h)
                    result["errors"] = error_result
                  end

                  result
                end
                if query.context.namespace?(:__query_result_extensions__)
                  query.result_values["extensions"] = query.context.namespace(:__query_result_extensions__)
                end
                # Get the Query::Result, not the Hash
                results[idx] = query.result
              end

              results
            rescue Exception
              # TODO rescue at a higher level so it will catch errors in analysis, too
              # Assign values here so that the query's `@executed` becomes true
              queries.map { |q| q.result_values ||= {} }
              raise
            end
          end
        end
      end
    end
  end
end
