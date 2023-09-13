# frozen_string_literal: true

require_relative "simple_tweet/version"
require_relative "simple_tweet/v2_client"

module SimpleTweet
  class Error < ::StandardError; end

  # UploadMediaError is
  class UploadMediaError < Error
    attr_reader :response

    def initialize(message = nil, response: nil)
      super(message)
      @response = response
    end
  end
end
