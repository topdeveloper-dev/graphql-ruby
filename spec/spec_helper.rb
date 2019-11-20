# frozen_string_literal: true

require 'rubygems'
require 'bundler'
Bundler.require

# Print full backtrace for failiures:
ENV["BACKTRACE"] = "1"
# Set this env var to use Interpreter for fixture schemas.
# Eventually, interpreter will be the default.
TESTING_INTERPRETER = ENV["TESTING_INTERPRETER"]
TESTING_RESCUE_FROM = !TESTING_INTERPRETER

require "codeclimate-test-reporter"
CodeClimate::TestReporter.start

require "graphql"
require "rake"
require "graphql/rake_task"
require "benchmark"
require "pry"
require "minitest/autorun"
require "minitest/focus"
require "minitest/reporters"

Minitest::Reporters.use! Minitest::Reporters::DefaultReporter.new(color: true)

Minitest::Spec.make_my_diffs_pretty!

# Filter out Minitest backtrace while allowing backtrace from other libraries
# to be shown.
Minitest.backtrace_filter = Minitest::BacktraceFilter.new

# This is for convenient access to metadata in test definitions
assign_metadata_key = ->(target, key, value) { target.metadata[key] = value }
assign_metadata_flag = ->(target, flag) { target.metadata[flag] = true }
GraphQL::Schema.accepts_definitions(set_metadata: assign_metadata_key)
GraphQL::BaseType.accepts_definitions(metadata: assign_metadata_key)
GraphQL::BaseType.accepts_definitions(metadata2: assign_metadata_key)
GraphQL::Field.accepts_definitions(metadata: assign_metadata_key)
GraphQL::Argument.accepts_definitions(metadata: assign_metadata_key)
GraphQL::Argument.accepts_definitions(metadata_flag: assign_metadata_flag)
GraphQL::EnumType::EnumValue.accepts_definitions(metadata: assign_metadata_key)

# Can be used as a GraphQL::Schema::Warden for some purposes, but allows nothing
module NothingWarden
  def self.enum_values(enum_type)
    []
  end
end

# Use this when a schema requires a `resolve_type` hook
# but you know it won't be called
NO_OP_RESOLVE_TYPE = ->(type, obj, ctx) {
  raise "this should never be called"
}

# Load dependencies
['Mongoid', 'Rails'].each do |integration|
  begin
    Object.const_get(integration)
    Dir["#{File.dirname(__FILE__)}/integration/#{integration.downcase}/**/*.rb"].each do |f|
      require f
    end
  rescue NameError
    # ignore
  end
end

# Load support files
Dir["#{File.dirname(__FILE__)}/support/**/*.rb"].each do |f|
  require f
end

def star_trek_query(string, variables={}, context: {})
  StarTrek::Schema.execute(string, variables: variables, context: context)
end

def star_wars_query(string, variables={}, context: {})
  StarWars::Schema.execute(string, variables: variables, context: context)
end

def with_bidirectional_pagination
  prev_value = GraphQL::Relay::ConnectionType.bidirectional_pagination
  GraphQL::Relay::ConnectionType.bidirectional_pagination = true
  yield
ensure
  GraphQL::Relay::ConnectionType.bidirectional_pagination = prev_value
end

module TestTracing
  class << self
    def clear
      traces.clear
    end

    def with_trace
      clear
      yield
      traces
    end

    def traces
      @traces ||= []
    end

    def trace(key, data)
      data[:key] = key
      data[:path] ||= data.key?(:context) ? data[:context].path : nil
      result = yield
      data[:result] = result
      traces << data
      result
    end
  end
end

module NoOpTracer
  def trace(_key, _data)
    yield
  end
end

module NoOpTracer
  def trace(_key, _data)
    yield
  end
end

module NoOpInstrumentation
  module_function

  # Log the time of the query
  def before_query(_query)
  end

  def after_query(_query)
  end
end

class NoOpAnalyzer < GraphQL::Analysis::AST::Analyzer
  def result
    # no op
  end
end
