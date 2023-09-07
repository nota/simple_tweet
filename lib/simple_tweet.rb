# frozen_string_literal: true

require_relative "simple_tweet/version"
require_relative "simple_tweet/v2_client"

module SimpleTweet
  class Error < ::StandardError; end
  class UploadMediaError < Error; end
end
