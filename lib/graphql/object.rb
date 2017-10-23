# frozen_string_literal: true
require "graphql/object/build_type"
require "graphql/object/field"
require "graphql/object/instrumentation"
require "graphql/object/resolvers"

module GraphQL
  class Object < GraphQL::SchemaMember
    attr_reader :object

    def initialize(object, context)
      @object = object
      @context = context
    end

    class << self
      def implements(*new_interfaces)
        new_interfaces.each do |int|
          if int.is_a?(Class) && int < GraphQL::Interface
            int.fields.each do |field|
              if int.method_defined?(field.name)
                method = int.instance_method(field.name)
                define_method(field.name, method)
              end
            end
          end
        end
        interfaces.concat(new_interfaces)
      end

      # TODO inheritance?
      def interfaces
        @interfaces ||= []
      end

      # Define a field on this object
      def field(*args, &block)
        fields << GraphQL::Object::Field.new(*args, &block)
      end

      # Fields defined on this class
      # TODO should this inherit?
      def fields
        @fields ||= []
      end

      # TODO this caching will not work with rebooting
      # @return [GraphQL::ObjectType]
      def to_graphql
        @to_graphql ||= BuildType.build_object_type(self)
      end
    end
  end
end
