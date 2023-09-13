# frozen_string_literal: true

require "json"
require "cgi"
require "oauth"
require "net/http/post/multipart"

module SimpleTweet
  module V2
    # Twitte API v2を叩くクライアント
    class Client
      TW_API_ORIGIN = "https://api.twitter.com"
      TW_UPLOAD_ORIGIN = "https://upload.twitter.com"
      TW_MEDIA_UPLOAD_PATH = "/1.1/media/upload.json"
      TW_METADATA_CREATE_PATH = "/1.1/media/metadata/create.json"
      TW_TWEET_PATH = "/2/tweets"
      UA = "SimpleTweet/#{SimpleTweet::VERSION}".freeze
      APPEND_PER = 5 * (1 << 20)

      def initialize(consumer_key:, consumer_secret:, access_token:, access_token_secret:, max_append_retry: 3)
        @consumer_key_ = consumer_key
        @consumer_secret_ = consumer_secret
        @access_token_ = access_token
        @access_token_secret_ = access_token_secret
        @max_append_retry_ = max_append_retry
      end

      # https://developer.twitter.com/en/docs/twitter-api/tweets/manage-tweets/migrate
      def tweet(message:, media_ids: [])
        json = { text: message } # : ::Hash[::Symbol, (::String|::Hash[::Symbol, ::Array[::String]])]
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

      def access_token(site: TW_API_ORIGIN)
        consumer = ::OAuth::Consumer.new(@consumer_key_, @consumer_secret_, site: site)
        ::OAuth::AccessToken.new(consumer, @access_token_, @access_token_secret_)
      end

      def request(req)
        @client ||= access_token(site: TW_UPLOAD_ORIGIN)
        @client.sign! req

        url = ::URI.parse(TW_UPLOAD_ORIGIN + TW_MEDIA_UPLOAD_PATH)
        https = ::Net::HTTP.new(
          url.host, # : ::String
          url.port
        )
        https.use_ssl = true

        https.start do |http|
          http.request req
        end
      end

      # https://developer.twitter.com/en/docs/twitter-api/v1/media/upload-media/api-reference/post-media-upload
      ## maybe todo: multiple image
      # ここはv1のAPIを叩いている。
      def upload_media(media_type:, media:)
        return upload_video(video: media) if media_type == "video/mp4"

        req = ::Net::HTTP::Post::Multipart.new(
          TW_MEDIA_UPLOAD_PATH,
          media: ::UploadIO.new(media, media_type),
          media_category: "tweet_image"
        )
        res = ::JSON.parse(request(req).body)
        [res["media_id_string"]]
      end

      def init(video:)
        init_req = ::Net::HTTP::Post::Multipart.new(
          TW_MEDIA_UPLOAD_PATH,
          command: "INIT",
          total_bytes: video.size,
          media_type: "video/mp4"
        )
        init_res = request(init_req)
        raise UploadMediaError.new("init failed", response: init_res) unless init_res.code == "202"

        ::JSON.parse(init_res.body)
      end

      def append(video:, media_id:, index:, retry_count: 0)
        append_req = ::Net::HTTP::Post::Multipart.new(
          TW_MEDIA_UPLOAD_PATH,
          command: "APPEND",
          media_id: media_id,
          media: video.read(APPEND_PER),
          segment_index: index
        )
        res = request(append_req)
        return if res.code == "204"
        raise UploadMediaError.new("append failed", response: res) unless retry_count <= @max_append_retry_

        append(video: video, media_id: media_id, index: index, retry_count: retry_count + 1)
      end

      def finalize(media_id:)
        finalize_req = ::Net::HTTP::Post::Multipart.new(
          TW_MEDIA_UPLOAD_PATH,
          command: "FINALIZE",
          media_id: media_id
        )
        finalize_res = request(finalize_req)
        raise UploadMediaError.new("finalize failed", response: finalize_res) unless finalize_res.code == "201"

        ::JSON.parse(finalize_res.body)
      end

      def status(media_id:)
        status_req = ::Net::HTTP::Post::Multipart.new(
          TW_MEDIA_UPLOAD_PATH,
          command: "STATUS",
          media_id: media_id
        )
        status_res = request(status_req)
        raise UploadMediaError.new("status failed", response: status_res) unless status_res.code == "200"

        ::JSON.parse(status_res.body)
      end

      # https://developer.twitter.com/en/docs/twitter-api/v1/media/upload-media/api-reference/post-media-upload-init
      def upload_video(video:)
        init_res = init(video: video)
        media_id = init_res["media_id_string"]

        chunks_needed = (video.size - 1) / APPEND_PER + 1
        chunks_needed.times do |i|
          append(video: video, media_id: media_id, index: i)
        end

        finalize_res = finalize(media_id: media_id)

        if finalize_res["processing_info"]
          retry_after = finalize_res["processing_info"]["check_after_secs"] || 5
          loop do
            sleep retry_after

            status_res = status(media_id: media_id)
            raise UploadMediaError if status_res["processing_info"].nil?
            break if status_res["processing_info"]["state"] == "succeeded"

            if status_res["processing_info"]["state"] == "in_progress"
              retry_after = status_res["processing_info"]["check_after_secs"] || 5
              next
            end

            # status_res_json["processing_info"]["state"] == "failed"
            raise UploadMediaError
          end
        end

        [media_id]
      end

      def create_media_metadata(media_id:, alt_text:)
        header = { "content-type": "application/json; charset=UTF-8" } # : ::Hash[::String, ::String]
        req = ::Net::HTTP::Post.new(TW_METADATA_CREATE_PATH, header)
        req.body = { media_id: media_id, alt_text: { text: alt_text } }.to_json
        res = request(req)
        raise UploadMediaError.new("create_media_metadata failed", response: res) if res.code != "200"

        res
      end
    end
  end
end
