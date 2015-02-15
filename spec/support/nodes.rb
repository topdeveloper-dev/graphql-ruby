require 'graphql'
require 'support/dummy_app.rb'

module Nodes
  class ApplicationNode < GraphQL::Node
    field :id,
      type: :number
    cursor :id

    class << self
      attr_accessor :model_class
      def node_for(m_class)
        @model_class = m_class
      end
    end
  end

  class LetterSelectionField < GraphQL::Types::StringField
    call :from, ->    (prev_value, chars) { prev_value[(chars.to_i)..-1] }
    call :for, ->     (prev_value, chars) { prev_value[0, (chars.to_i)] }
    call :select, ->  (prev_value, from_chars, for_chars) { prev_value[from_chars.to_i, for_chars.to_i] }
    def raw_value
      owner.content
    end
  end

  class ApplicationConnectionField < GraphQL::Types::ConnectionField
    call :first, -> (prev_items, first) { prev_items.first(first.to_i) }
    call :after, -> (prev_items, after) { prev_items.select {|i| i.id > after.to_i } }
  end

  class DateField < GraphQL::Types::ObjectField
    field_type "date"
    call :minus_days, -> (prev_value, minus_days) { prev_value - minus_days.to_i }
  end

  class DateNode < GraphQL::Node
    field :year,  type: :number
    field :month, type: :number
  end

  class PostNode < ApplicationNode
    node_for Post
    desc "A blog post entry"
    field :title,
      type: :string

    field :content,
      type: LetterSelectionField
    field :length,
      type: :number

    field :comments,
      type: ApplicationConnectionField

    field :published_at,
      type: DateField

    field :likes,
      type: :connection,
      connection_class_name: "Nodes::ThumbUpConnection",
      node_class_name: "Nodes::ThumbUpNode"

    def length
      target.content.length
    end
  end

  class CommentNode < ApplicationNode
    node_for Comment
    field :content
    field :letters,
      type: LetterSelectionField
  end

  # wraps a Like, for testing explicit name
  class ThumbUpNode < ApplicationNode
    node_for(Like)
    type "upvote"
    field :post_id
  end

  class StupidThumbUpNode < ThumbUpNode
    node_for(Like)
    def id
      target.id.to_s + target.id.to_s
    end
  end

  class ViewerNode < GraphQL::Node
    field :name

    def name
      "It's you again"
    end

    def cursor
      "viewer"
    end
  end

  class ContextNode < GraphQL::Node
    field :person_name

    def person_name
      context[:person_name]
    end

    def cursor
      "context"
    end
  end

  class ApplicationConnection < GraphQL::Connection
    field :count, type: :number
    def count
      items.count
    end
  end

  class CommentsConnection < ApplicationConnection
    field :viewer_name_length
    field :average_rating

    # just to test context:
    def viewer_name_length
      context[:person_name].length
    end

    def average_rating
      total_rating = items.map(&:rating).inject(&:+).to_f
      total_rating / items.size
    end
  end

  # Wraps Likes, for testing explicit naming
  class ThumbUpConnection < ApplicationConnection
    field :any

    def any
      items.any?
    end
  end

  class FindCall < GraphQL::RootCall
    def execute!(*ids)
      model_class = model_type
      items = ids.map { |id| model_class.find(id.to_i) }
      result_hash = {}
      result_hash["__type__"] = node_type
      items.each { |item| result_hash[item.id.to_s] = item }
      result_hash
    end
  end

  class PostCall < FindCall
    def model_type
      Post
    end
    def node_type
      PostNode
    end
  end

  class CommentCall < FindCall
    def model_type
      Comment
    end
    def node_type
      CommentNode
    end
  end

  class StupidThumbUpCall < FindCall
    def model_type
      Like
    end
    def node_type
      StupidThumbUpNode
    end
  end

  class ViewerCall < GraphQL::RootCall
    def execute!
      {
        "viewer" => nil,
        "__type__" => ViewerNode,
      }
    end
  end

  class ContextCall < GraphQL::RootCall
    def execute!
      {
        "context" => nil,
        "__type__" => ContextNode,
      }
    end
  end

  class LikePostCall < GraphQL::RootCall
    indentifier "upvote_post"

    def execute!(payload)
      post_id = payload["post"]["id"]
      like = Like.create(post_id: post_id)
      {
        "post" => Post.find(post_id),
        "upvote" => like
      }
    end
  end
end