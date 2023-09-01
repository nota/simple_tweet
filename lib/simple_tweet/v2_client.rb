# frozen_string_literal: true

require "json"

module SimpleTweet
  module V2
    # mediaのuploadはapi 1.1しか用意されていないため、それを使う。
    class Client < V1::Client
      TW_TWEET_PATH = "/2/tweets"
      UA = "SimpleTweet/#{SimpleTweet::VERSION}"

      def tweet(message:, media_ids: [])
        json = { text: message }
        json[:media] = { media_ids: media_ids } unless media_ids.empty?
        header = { "User-Agent": UA, "content-type": "application/json" }
        access_token.post(TW_TWEET_PATH, json.to_json, header)
      end
    end
  end
end
