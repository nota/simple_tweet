# frozen_string_literal: true

require "json"
require "net/http"

module SimpleTweet
  module V2
    # mediaのuploadはapi 1.1しか用意されていないため、それを使う。
    class Client < V1::Client
      TW_TWEET_PATH = "/2/tweets"
      TW_METADATA_CREATE_PATH = "/1.1/media/metadata/create.json"
      UA = "SimpleTweet/#{SimpleTweet::VERSION}".freeze

      def tweet(message:, media_ids: [])
        json = { text: message }
        json[:media] = { media_ids: media_ids } unless media_ids.empty?
        header = { "User-Agent": UA, "content-type": "application/json" }
        access_token.post(TW_TWEET_PATH, json.to_json, header)
      end

      def tweet_with_media(message:, media_type:, media:, alt_text: nil)
        media_ids = upload_media(media_type: media_type, media: media)
        unless alt_text.nil?
          media_ids.each do |media_id|
            create_media_metadata(media_id: media_id, alt_text: alt_text)
          end
        end
        tweet(message: message, media_ids: media_ids)
      end

      private

      def create_media_metadata(media_id:, alt_text:)
        header = { "content-type": "application/json; charset=UTF-8" }
        req = ::Net::HTTP::Post.new(TW_METADATA_CREATE_PATH, header)
        req.body = { media_id: media_id, alt_text: { text: alt_text } }.to_json
        res = request(req)
        throw UploadMediaError, "create_media_metadata failed: #{res.code} #{res.body}" if res.code != "200"
        res
      end
    end
  end
end
