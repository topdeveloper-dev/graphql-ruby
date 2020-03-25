# frozen_string_literal: true

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Tests for appoptics_apm tracing
#
# if any of these tests fail, please file an issue at
# https://github.com/appoptics/appoptics-apm-ruby
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

require 'spec_helper'

describe GraphQL::Tracing::AppOpticsTracing do
  module AppOpticsTest
    class Schema < GraphQL::Schema
      def self.id_from_object(_object = nil, _type = nil, _context = {})
        SecureRandom.uuid
      end

      class Address < GraphQL::Schema::Object
        global_id_field :id
        field :street, String, null: true
        field :number, Integer, null: true
      end

      class Company < GraphQL::Schema::Object
        global_id_field :id
        field :name, String, null: true
        field :address, Schema::Address, null: true

        def address
          OpenStruct.new(
            id: AppOpticsTest::Schema.id_from_object,
            street: 'MyStreetName',
            number: 'MyStreetNumber'
          )
        end
      end

      class Query < GraphQL::Schema::Object
        field :int, Integer, null: false
        def int; 1; end

        field :company, Company, null: true do
          argument :id, ID, required: true
        end

        def company(id:)
          OpenStruct.new(
            id: id,
            name: 'MyName')
        end
      end

      query Query
      use GraphQL::Tracing::AppOpticsTracing
    end
  end

  before do
    load 'spec/support/appoptics.rb'

    $appoptics_tracing_spans = []
    $appoptics_tracing_kvs = []
    $appoptics_tracing_name = nil
    AppOpticsAPM::Config[:graphql] = { :enabled => true,
                                       :remove_comments => true,
                                       :sanitize_query => true,
                                       :transaction_name => true
    }
  end

  it 'calls AppOpticsAPM::SDK.trace with names and kvs' do
    query = 'query Query { int }'
    AppOpticsTest::Schema.execute(query)

    assert_equal $appoptics_tracing_name, 'graphql.query.Query'
    refute $appoptics_tracing_spans.find { |name| name !~ /^graphql\./ }
    assert_equal $appoptics_tracing_kvs.compact.size, $appoptics_tracing_spans.compact.size
    assert_equal($appoptics_tracing_kvs[0][:Spec], 'graphql')
    assert_equal($appoptics_tracing_kvs[0][:InboundQuery], query)
  end

  it 'uses type + field keys' do
    query = <<-QL
    query { company(id: 1) # there is a comment here
            { id name address
               { street }
            }
          }
   # and another one here
   QL

    AppOpticsTest::Schema.execute(query)

    assert_equal $appoptics_tracing_name, 'graphql.query.company'
    refute $appoptics_tracing_spans.find { |name| name !~ /^graphql\./ }
    assert_equal $appoptics_tracing_kvs.compact.size, $appoptics_tracing_spans.compact.size
    assert_includes($appoptics_tracing_spans, 'graphql.Query.company')
    assert_includes($appoptics_tracing_spans, 'graphql.Company.address')
  end

  # case: appoptics_apm didn't get required
  it 'should not barf, when AppOpticsAPM is undefined' do
    Object.send(:remove_const, :AppOpticsAPM)
    query = 'query Query { int }'

    begin
      AppOpticsTest::Schema.execute(query)
    rescue StandardError => e
      msg = e.message.split("\n").first
      flunk "failed: It raised '#{msg}' when AppOpticsAPM is undefined."
    end
  end

  # case: appoptics may have encountered a compile or service key problem
  it 'should not barf, when appoptics is present but not loaded' do
    AppOpticsAPM.stub(:loaded, false) do
      query = 'query Query { int }'

      begin
        AppOpticsTest::Schema.execute(query)
      rescue StandardError => e
        msg = e.message.split("\n").first
        flunk "failed: It raised '#{msg}' when AppOpticsAPM is not loaded."
      end
    end
  end

  # case: using appoptics_apm < 4.12.0, without default graphql configs
  it 'creates traces by default when it cannot find configs for graphql' do
    AppOpticsAPM::Config.clear

    query = 'query Query { int }'
    AppOpticsTest::Schema.execute(query)

    refute $appoptics_tracing_spans.empty?, 'failed: no traces were created'
  end

  it 'should not create traces when disabled' do
    AppOpticsAPM::Config[:graphql][:enabled] = false

    query = 'query Query { int }'
    AppOpticsTest::Schema.execute(query)

    assert $appoptics_tracing_spans.empty?, 'failed: traces were created'
  end
end
