# frozen_string_literal: true
require 'graphql/schema/member/accepts_definition'
require 'graphql/schema/member/base_dsl_methods'
require 'graphql/schema/member/cached_graphql_definition'
require 'graphql/schema/member/graphql_type_names'
require 'graphql/schema/member/type_system_helpers'
require "graphql/relay/type_extensions"

module GraphQL
  # The base class for things that make up the schema,
  # eg objects, enums, scalars.
  #
  # @api private
  class Schema
    class Member
      include GraphQLTypeNames
      extend CachedGraphQLDefinition
      extend GraphQL::Relay::TypeExtensions
      extend BaseDSLMethods
      extend TypeSystemHelpers
    end
  end
end

require 'graphql/schema/member/has_arguments'
require 'graphql/schema/member/has_fields'
require 'graphql/schema/member/instrumentation'
require 'graphql/schema/member/build_type'
