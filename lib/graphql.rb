require "parslet"
require "active_support/core_ext/string/inflections"
require "active_support/core_ext/object/blank"

module GraphQL
  autoload(:Connection,       "graphql/connection")
  autoload(:Field,            "graphql/field")
  autoload(:Parser,           "graphql/parser")
  autoload(:Query,            "graphql/query")
  autoload(:Node,             "graphql/node")
  autoload(:Transform,        "graphql/transform")
  autoload(:VERSION,          "graphql/version")

  module Introspection
    autoload(:CallNode,           "graphql/introspection/call_node.rb")
    autoload(:FieldNode,          "graphql/introspection/field_node.rb")
    autoload(:FieldsConnection,   "graphql/introspection/fields_connection.rb")
    autoload(:TypeNode,           "graphql/introspection/type_node.rb")
  end

  module Syntax
    autoload(:Call,       "graphql/syntax/call")
    autoload(:Field,      "graphql/syntax/field")
    autoload(:Node,       "graphql/syntax/node")
  end

  module Types
    autoload(:ConnectionField,  "graphql/types/connection_field.rb")
    autoload(:CursorField,      "graphql/types/cursor_field.rb")
    autoload(:NumberField,      "graphql/types/number_field.rb")
    autoload(:ObjectField,      "graphql/types/object_field.rb")
    autoload(:StringField,      "graphql/types/string_field.rb")
  end

  TYPE_ALIASES = {}
  PARSER = Parser.new
  TRANSFORM = Transform.new

  class FieldNotDefinedError < RuntimeError
    def initialize(class_name, field_name)
      super("#{class_name}##{field_name} was requested, but it isn't defined.")
    end
  end
  class NodeNotDefinedError < RuntimeError
    def initialize(node_name)
      super("#{node_name} was requested but was not found")
    end
  end
  class SyntaxError < RuntimeError
    def initialize(line, col, string)
      lines = string.split("\n")
      super("Syntax Error at (#{line}, #{col}), check usage: #{string}")
    end
  end
end