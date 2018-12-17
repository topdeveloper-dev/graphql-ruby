# frozen_string_literal: true
require "spec_helper"

describe GraphQL::Tracing::NewRelicTracing do
  module NewRelicTest
    class Query < GraphQL::Schema::Object
      field :int, Integer, null: false

      def int
        1
      end
    end

    class SchemaWithoutTransactionName < GraphQL::Schema
      query(Query)
      use(GraphQL::Tracing::NewRelicTracing)
      if TESTING_INTERPRETER
        use GraphQL::Execution::Interpreter
      end
    end

    class SchemaWithTransactionName < GraphQL::Schema
      query(Query)
      use(GraphQL::Tracing::NewRelicTracing, set_transaction_name: true)
      if TESTING_INTERPRETER
        use GraphQL::Execution::Interpreter
      end
    end

    class SchemaWithScalarTrace < GraphQL::Schema
      query(Query)
      use(GraphQL::Tracing::NewRelicTracing, trace_scalars: true)
    end
  end

  before do
    NewRelic.clear_all
  end

  it "can leave the transaction name in place" do
    NewRelicTest::SchemaWithoutTransactionName.execute "query X { int }"
    assert_equal [], NewRelic::TRANSACTION_NAMES
  end

  it "can override the transaction name" do
    NewRelicTest::SchemaWithTransactionName.execute "query X { int }"
    assert_equal ["GraphQL/query.X"], NewRelic::TRANSACTION_NAMES
  end

  it "can override the transaction name per query" do
    # Override with `false`
    NewRelicTest::SchemaWithTransactionName.execute "{ int }", context: { set_new_relic_transaction_name: false }
    assert_equal [], NewRelic::TRANSACTION_NAMES
    # Override with `true`
    NewRelicTest::SchemaWithoutTransactionName.execute "{ int }", context: { set_new_relic_transaction_name: true }
    assert_equal ["GraphQL/query.anonymous"], NewRelic::TRANSACTION_NAMES
  end

  it "traces scalars when trace_scalars is true" do
    NewRelicTest::SchemaWithScalarTrace.execute "query X { int }"
    assert_includes NewRelic::EXECUTION_SCOPES, "GraphQL/Query/int"
  end
end
