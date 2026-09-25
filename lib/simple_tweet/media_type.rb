# frozen_string_literal: true

module SimpleTweet
  module V2
    # media_type から、Xに送る media_type と media_category を決める。
    module MediaType
      VIDEO = "video/mp4"
      # v2のmedia_typeはenumで検証されるので、よくある別名を正規化しておく。
      ALIASES = {
        "image/jpg" => "image/jpeg"
      }.freeze
      # media_categoryはsimple uploadでは必須。
      CATEGORIES = {
        "video/mp4" => "tweet_video",
        "image/gif" => "tweet_gif"
      }.freeze
      DEFAULT_CATEGORY = "tweet_image"

      module_function

      def normalize(media_type)
        ALIASES.fetch(media_type, media_type)
      end

      def category(media_type)
        CATEGORIES.fetch(media_type, DEFAULT_CATEGORY)
      end

      def video?(media_type)
        media_type == VIDEO
      end
    end
  end
end
