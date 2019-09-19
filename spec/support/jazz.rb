# frozen_string_literal: true

# Here's the "application"
module Jazz
  module Models
    Instrument = Struct.new(:name, :family)
    Ensemble = Struct.new(:name)
    Musician = Struct.new(:name, :favorite_key)
    Key = Struct.new(:root, :sharp, :flat) do
      def self.from_notation(key_str)
        key, sharp_or_flat = key_str.split("")
        sharp = sharp_or_flat == "♯"
        flat = sharp_or_flat == "♭"
        Models::Key.new(key, sharp, flat)
      end

      def to_notation
        "#{root}#{sharp ? "♯" : ""}#{flat ? "♭" : ""}"
      end
    end

    def self.reset
      @data = {
        "Instrument" => [
          Models::Instrument.new("Banjo", :str),
          Models::Instrument.new("Flute", "WOODWIND"),
          Models::Instrument.new("Trumpet", "BRASS"),
          Models::Instrument.new("Piano", "KEYS"),
          Models::Instrument.new("Organ", "KEYS"),
          Models::Instrument.new("Drum Kit", "PERCUSSION"),
        ],
        "Ensemble" => [
          Models::Ensemble.new("Bela Fleck and the Flecktones"),
          Models::Ensemble.new("Robert Glasper Experiment"),
          Models::Ensemble.new("Spinal Tap"),
        ],
        "Musician" => [
          Models::Musician.new("Herbie Hancock", Models::Key.from_notation("B♭")),
        ],
      }
    end

    def self.data
      @data || reset
    end
  end

  class BaseArgument < GraphQL::Schema::Argument
    def initialize(*args, custom: nil, **kwargs)
      @custom = custom
      super(*args, **kwargs)
    end

    def to_graphql
      arg_defn = super
      arg_defn.metadata[:custom] = @custom
      arg_defn
    end
  end

  # A custom field class that supports the `upcase:` option
  class BaseField < GraphQL::Schema::Field
    argument_class BaseArgument
    attr_reader :upcase

    def initialize(*args, **options, &block)
      @upcase = options.delete(:upcase)
      super(*args, **options, &block)
    end

    def resolve_field(*)
      result = super
      if @upcase && result
        result.upcase
      else
        result
      end
    end

    def resolve(*)
      result = super
      if @upcase && result
        result.upcase
      else
        result
      end
    end
  end

  class BaseObject < GraphQL::Schema::Object
    # Use this overridden field class
    field_class BaseField

    class << self
      def config(key, value)
        configs[key] = value
      end

      def configs
        @configs ||= {}
      end

      def to_graphql
        type_defn = super
        configs.each do |k, v|
          type_defn.metadata[k] = v
        end
        type_defn
      end
    end
  end

  module BaseInterface
    include GraphQL::Schema::Interface
    # Use this overridden field class
    field_class BaseField

    # These methods are available to child interfaces
    definition_methods do
      def upcased_field(*args, **kwargs, &block)
        field(*args, upcase: true, **kwargs, &block)
      end
    end
  end

  class BaseEnumValue < GraphQL::Schema::EnumValue
    def initialize(*args, custom_setting: nil, **kwargs, &block)
      @custom_setting = custom_setting
      super(*args, **kwargs, &block)
    end

    def to_graphql
      enum_value_defn = super
      enum_value_defn.metadata[:custom_setting] = @custom_setting
      enum_value_defn
    end
  end

  class BaseEnum < GraphQL::Schema::Enum
    enum_value_class BaseEnumValue
  end

  # Some arbitrary global ID scheme
  # *Type suffix is removed automatically
  module GloballyIdentifiableType
    include BaseInterface
    description "A fetchable object in the system"
    field(
      name: :id,
      type: ID,
      null: false,
      description: "A unique identifier for this object",
    )
    upcased_field :upcased_id, ID, null: false, resolver_method: :id # upcase: true added by helper

    def id
      GloballyIdentifiableType.to_id(@object)
    end

    def self.to_id(object)
      "#{object.class.name.split("::").last}/#{object.name}"
    end

    def self.find(id)
      class_name, object_name = id.split("/")
      Models.data[class_name].find { |obj| obj.name == object_name }
    end
  end

  module NamedEntity
    include BaseInterface
    field :name, String, null: false
  end

  # test field inheritance
  class ObjectWithUpcasedName < BaseObject
    # Test extra arguments:
    field :upcase_name, String, null: false, upcase: true

    def upcase_name
      object.name # upcase is applied by the superclass
    end
  end

  module HasMusicians
    include BaseInterface
    field :musicians, "[Jazz::Musician]", null: false
  end

  # Here's a new-style GraphQL type definition
  class Ensemble < ObjectWithUpcasedName
    # Test string type names
    # This method should override inherited one
    field :name, "String", null: false, resolver_method: :overridden_name
    implements GloballyIdentifiableType, NamedEntity, HasMusicians
    description "A group of musicians playing together"
    config :config, :configged
    field :formed_at, String, null: true, hash_key: "formedAtDate"

    def overridden_name
      @object.name.sub("Robert Glasper", "ROBERT GLASPER")
    end

    def self.authorized?(object, context)
      # Spinal Tap is top-secret, don't show it to anyone.
      obj_name = object.is_a?(Hash) ? object[:name] : object.name
      obj_name != "Spinal Tap"
    end
  end

  class Family < BaseEnum
    description "Groups of musical instruments"
    # support string and symbol
    value "STRING", "Makes a sound by vibrating strings", value: :str, custom_setting: 1
    value :WOODWIND, "Makes a sound by vibrating air in a pipe"
    value :BRASS, "Makes a sound by amplifying the sound of buzzing lips"
    value "PERCUSSION", "Makes a sound by hitting something that vibrates"
    value "DIDGERIDOO", "Makes a sound by amplifying the sound of buzzing lips", deprecation_reason: "Merged into BRASS"
    value "KEYS" do
      description "Neither here nor there, really"
    end
    value "SILENCE", "Makes no sound", value: false
  end

  # Lives side-by-side with an old-style definition
  using GraphQL::DeprecatedDSL # for ! and types[]

  class InstrumentType < BaseObject
    implements NamedEntity
    implements GloballyIdentifiableType

    field :upcased_id, ID, null: false

    def upcased_id
      GloballyIdentifiableType.to_id(object).upcase
    end

    field :family, Family, null: false
  end

  class Key < GraphQL::Schema::Scalar
    description "A musical key"
    def self.coerce_input(val, ctx)
      Models::Key.from_notation(val)
    end

    def self.coerce_result(val, ctx)
      val.to_notation
    end
  end

  class Musician < BaseObject
    implements GloballyIdentifiableType
    implements NamedEntity
    description "Someone who plays an instrument"
    field :instrument, InstrumentType, null: false do
      description "An object played in order to produce music"
    end
    field :favorite_key, Key, null: true
    # Test lists with nullable members:
    field :inspect_context, [String, null: true], null: false
    field :add_error, String, null: false, extras: [:execution_errors]

    def inspect_context
      [
        @context.custom_method,
        @context[:magic_key],
        @context[:normal_key],
        nil,
      ]
    end

    def add_error(execution_errors:)
      execution_errors.add("this has a path")
      "done"
    end
  end

  # Since this is not a legacy input type, this test can be removed
  class LegacyInputType < GraphQL::Schema::InputObject
    argument :int_value, Int, required: true
  end

  class InspectableInput < GraphQL::Schema::InputObject
    argument :ensemble_id, ID, required: false, loads: Ensemble
    argument :string_value, String, required: true, description: "Test description kwarg"
    argument :nested_input, InspectableInput, required: false
    argument :legacy_input, LegacyInputType, required: false

    def helper_method
      [
        # Context is available in the InputObject
        context[:message],
        # ~~A GraphQL::Query::Arguments instance is available~~ not anymore
        self[:string_value],
        # Legacy inputs have underscored method access too
        legacy_input ? legacy_input.int_value : "-",
        # Access by method call is available
        "(#{nested_input ? nested_input.helper_method : "-"})",
      ].join(", ")
    end
  end

  class InspectableKey < BaseObject
    field :root, String, null: false
    field :is_sharp, Boolean, null: false, method: :sharp
    field :is_flat, Boolean, null: false, method: :flat
  end

  class PerformingAct < GraphQL::Schema::Union
    possible_types Musician, Ensemble

    def self.resolve_type(object, context)
      GraphQL::Execution::Lazy.new do
        if object.is_a?(Models::Ensemble)
          Ensemble
        else
          Musician
        end
      end
    end
  end

  class HashKeyTest < BaseObject
    field :falsey, Boolean, null: false
  end

  # Another new-style definition, with method overrides
  class Query < BaseObject
    field :ensembles, [Ensemble], null: false
    field :find, GloballyIdentifiableType, null: true do
      argument :id, ID, required: true
    end
    field :instruments, [InstrumentType], null: false do
      argument :family, Family, required: false
    end
    field :inspect_input, [String], null: false do
      argument :input, InspectableInput, required: true, custom: :ok
    end
    field :inspect_key, InspectableKey, null: false do
      argument :key, Key, required: true
    end
    field :now_playing, PerformingAct, null: false

    def now_playing; Models.data["Ensemble"].first; end

    # For asserting that the object is initialized once:
    field :object_id, String, null: false
    field :inspect_context, [String], null: false
    field :hashyEnsemble, Ensemble, null: false

    field :echo_json, GraphQL::Types::JSON, null: false do
      argument :input, GraphQL::Types::JSON, required: true
    end

    field :echo_first_json, GraphQL::Types::JSON, null: false do
      argument :input, [GraphQL::Types::JSON], required: true
    end

    field :upcase_check_1, String, null: true, resolver_method: :upcase_check, extras: [:upcase]
    field :upcase_check_2, String, null: false, upcase: false, resolver_method: :upcase_check, extras: [:upcase]
    field :upcase_check_3, String, null: false, upcase: true, resolver_method: :upcase_check, extras: [:upcase]
    field :upcase_check_4, String, null: false, upcase: "why not?", resolver_method: :upcase_check, extras: [:upcase]
    def upcase_check(upcase:)
      upcase.inspect
    end

    def ensembles
      # Filter out the unauthorized one to avoid an error later
      Models.data["Ensemble"].select { |e| e.name != "Spinal Tap" }
    end

    def find(id:)
      if id == "MagicalSkipId"
        context.skip
      else
        GloballyIdentifiableType.find(id)
      end
    end

    def instruments(family: nil)
      objs = Models.data["Instrument"]
      if family
        objs = objs.select { |i| i.family == family }
      end
      objs
    end

    # This is for testing input object behavior
    def inspect_input(input:)
      [
        input.class.name,
        input.helper_method,
        # Access by method
        input.string_value,
        # Access by key:
        input[:string_value],
        input.key?(:string_value).to_s,
        # ~~Access by legacy key~~ # not anymore
        input[:string_value],
        input.ensemble,
        input.key?(:ensemble).to_s,
      ]
    end

    def inspect_key(key:)
      key
    end

    def inspect_context
      [
        context.custom_method,
        context[:magic_key],
        context[:normal_key],
      ]
    end

    def hashy_ensemble
      # Both string and symbol keys are supported:

      {
        name: "The Grateful Dead",
        "musicians" => [
          OpenStruct.new(name: "Jerry Garcia"),
        ],
        "formedAtDate" => "May 5, 1965",
      }
    end

    def echo_json(input:)
      input
    end

    def echo_first_json(input:)
      input.first
    end

    field :hash_by_string, HashKeyTest, null: false
    field :hash_by_sym, HashKeyTest, null: false

    def hash_by_string
      {"falsey" => false}
    end

    def hash_by_sym
      {falsey: false}
    end

    field :named_entities, [NamedEntity, null: true], null: false

    def named_entities
      [Models.data["Ensemble"].first, nil]
    end

    field :default_value_test, String, null: false do
      if TESTING_INTERPRETER
        argument :arg_with_default, InspectableInput, required: false, default_value: { string_value: "S" }
      else
        argument :arg_with_default, InspectableInput, required: false, default_value: { "stringValue" => "S" }
      end
    end

    def default_value_test(arg_with_default:)
      "#{arg_with_default.class.name} -> #{arg_with_default.to_h}"
    end

    field :complex_hash_key, String, null: false, hash_key: :'foo bar/fizz-buzz'
  end

  class EnsembleInput < GraphQL::Schema::InputObject
    argument :name, String, required: true
  end

  class AddInstrument < GraphQL::Schema::Mutation
    null true
    description "Register a new musical instrument in the database"

    argument :name, String, required: true
    argument :family, Family, required: true

    field :instrument, InstrumentType, null: false
    # This is meaningless, but it's to test the conflict with `Hash#entries`
    field :entries, [InstrumentType], null: false
    # Test `extras` injection

    field :ee, String, null: false
    extras [:execution_errors]

    def resolve(name:, family:, execution_errors:)
      instrument = Jazz::Models::Instrument.new(name, family)
      Jazz::Models.data["Instrument"] << instrument
      {instrument: instrument, entries: Jazz::Models.data["Instrument"], ee: execution_errors.class.name}
    end
  end

  class AddEnsembleRelay < GraphQL::Schema::RelayClassicMutation
    argument :ensemble, EnsembleInput, required: true
    field :ensemble, Ensemble, null: false

    def resolve(ensemble:)
      ens = Models::Ensemble.new(ensemble.name)
      Models.data["Ensemble"] << ens
      { ensemble: ens }
    end
  end

  class AddSitar < GraphQL::Schema::RelayClassicMutation
    null true
    description "Get Sitar to musical instrument"

    field :instrument, InstrumentType, null: false

    def resolve
      instrument = Models::Instrument.new("Sitar", :str)
      {instrument: instrument}
    end
  end

  class HasExtras < GraphQL::Schema::RelayClassicMutation
    null true
    description "Test extras in RelayClassicMutation"

    argument :int, Integer, required: false
    extras [:ast_node]

    field :node_class, String, null: false
    field :int, Integer, null: true

    def resolve(int: nil, ast_node:)
      {
        int: int,
        node_class: ast_node.class.name,
      }
    end
  end

  class StripsExtras < GraphQL::Schema::RelayClassicMutation
    extras [:lookahead]
    def resolve_with_support(lookahead: , **rest)
      context[:has_lookahead] = !!lookahead
      super(**rest)
    end
  end

  class HasExtrasStripped < StripsExtras
    field :int, Integer, null: false

    def resolve
      {
        int: 51,
      }
    end
  end


  class RenameNamedEntity < GraphQL::Schema::RelayClassicMutation
    argument :named_entity_id, ID, required: true, loads: NamedEntity
    argument :new_name, String, required: true

    field :named_entity, NamedEntity, null: false

    def resolve(named_entity:, new_name:)
      # doesn't actually update the "database"
      dup_named_entity = named_entity.dup
      dup_named_entity.name = new_name

      {
        named_entity: dup_named_entity
      }
    end
  end

  class RenamePerformingAct < GraphQL::Schema::RelayClassicMutation
    argument :performing_act_id, ID, required: true, loads: PerformingAct
    argument :new_name, String, required: true

    field :performing_act, PerformingAct, null: false

    def resolve(performing_act:, new_name:)
      # doesn't actually update the "database"
      dup_performing_act = performing_act.dup
      dup_performing_act.name = new_name

      {
        performing_act: dup_performing_act
      }
    end
  end

  class RenameEnsemble < GraphQL::Schema::RelayClassicMutation
    argument :ensemble_id, ID, required: true, loads: Ensemble
    argument :new_name, String, required: true

    field :ensemble, Ensemble, null: false

    def resolve(ensemble:, new_name:)
      # doesn't actually update the "database"
      dup_ensemble = ensemble.dup
      dup_ensemble.name = new_name
      {
        ensemble: dup_ensemble,
      }
    end
  end

  class UpvoteEnsembles < GraphQL::Schema::RelayClassicMutation
    argument :ensemble_ids, [ID], required: true, loads: Ensemble

    field :ensembles, [Ensemble], null: false

    def resolve(ensembles:)
      {
        ensembles: ensembles
      }
    end
  end

  class UpvoteEnsemblesAsBands < GraphQL::Schema::RelayClassicMutation
    argument :ensemble_ids, [ID], required: true, loads: Ensemble, as: :bands

    field :ensembles, [Ensemble], null: false

    def resolve(bands:)
      {
        ensembles: bands
      }
    end
  end

  class UpvoteEnsemblesIds < GraphQL::Schema::RelayClassicMutation
    argument :ensembles_ids, [ID], required: true, loads: Ensemble

    field :ensembles, [Ensemble], null: false

    def resolve(ensembles:)
      {
        ensembles: ensembles
      }
    end
  end

  class RenameEnsembleAsBand < RenameEnsemble
    argument :ensemble_id, ID, required: true, loads: Ensemble, as: :band

    def resolve(band:, new_name:)
      super(ensemble: band, new_name: new_name)
    end
  end

  class Mutation < BaseObject
    field :add_ensemble, Ensemble, null: false do
      argument :input, EnsembleInput, required: true
    end

    field :add_instrument, mutation: AddInstrument
    field :add_ensemble_relay, mutation: AddEnsembleRelay
    field :add_sitar, mutation: AddSitar
    field :rename_ensemble, mutation: RenameEnsemble
    field :rename_named_entity, mutation: RenameNamedEntity
    field :rename_performing_act, mutation: RenamePerformingAct
    field :upvote_ensembles, mutation: UpvoteEnsembles
    field :upvote_ensembles_as_bands, mutation: UpvoteEnsemblesAsBands
    field :upvote_ensembles_ids, mutation: UpvoteEnsemblesIds
    field :rename_ensemble_as_band, mutation: RenameEnsembleAsBand
    field :has_extras, mutation: HasExtras
    field :has_extras_stripped, mutation: HasExtrasStripped

    def add_ensemble(input:)
      ens = Models::Ensemble.new(input.name)
      Models.data["Ensemble"] << ens
      ens
    end

    field :prepare_input, Integer, null: false do
      argument :input, Integer, required: true, prepare: :square, as: :squared_input
    end

    def prepare_input(squared_input:)
      # Test that `square` is called
      squared_input
    end

    def square(value)
      value ** 2
    end
  end

  class MetadataPlugin
    def self.use(schema_defn, value:)
      schema_defn.target.metadata[:plugin_key] = value
    end
  end

  class CustomContext < GraphQL::Query::Context
    def [](key)
      if key == :magic_key
        "magic_value"
      else
        super
      end
    end

    def custom_method
      "custom_method"
    end
  end

  module Introspection
    class TypeType < GraphQL::Introspection::TypeType
      def self.authorized?(_obj, ctx)
        if ctx[:cant_introspect]
          raise GraphQL::ExecutionError, "You're not allowed to introspect here"
        else
          super
        end
      end

      def name
        n = object.graphql_name
        n && n.upcase
      end
    end

    class NestedType < GraphQL::Introspection::TypeType
      def name
        object.name.upcase
      end

      class DeeplyNestedType < GraphQL::Introspection::TypeType
        def name
          object.name.upcase
        end
      end
    end

    class SchemaType < GraphQL::Introspection::SchemaType
      graphql_name "__Schema"

      field :is_jazzy, Boolean, null: false

      def is_jazzy
        true
      end
    end

    class DynamicFields < GraphQL::Introspection::DynamicFields
      field :__typename_length, Int, null: false, extras: [:irep_node]
      field :__ast_node_class, String, null: false, extras: [:ast_node]

      def __typename_length(irep_node: nil)
        __typename(irep_node: irep_node).length
      end

      def __ast_node_class(ast_node:)
        ast_node.class.name
      end
    end

    class EntryPoints < GraphQL::Introspection::EntryPoints
      field :__classname, String, "The Ruby class name of the root object", null: false

      def __classname
        if context.interpreter?
          object.object.class.name
        else
          object.class.name
        end
      end
    end
  end

  # New-style Schema definition
  class Schema < GraphQL::Schema
    query(Query)
    mutation(Mutation)
    context_class CustomContext
    introspection(Introspection)
    use MetadataPlugin, value: "xyz"
    def self.resolve_type(type, obj, ctx)
      class_name = obj.class.name.split("::").last
      ctx.schema.types[class_name] || raise("No type for #{obj.inspect}")
    end

    def self.object_from_id(id, ctx)
      GloballyIdentifiableType.find(id)
    end
    if TESTING_INTERPRETER
      use GraphQL::Execution::Interpreter
      use GraphQL::Analysis::AST
    end
  end

  class SchemaWithoutIntrospection < GraphQL::Schema
    query(Query)

    disable_introspection_entry_points
  end
end
