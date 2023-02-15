# frozen_string_literal: true

require_relative "simple_tweet/version"
require "cgi"
require "oauth"
require "json"
require "net/http/post/multipart"

module SimpleTweet
  class Error < ::StandardError; end
  class UploadMediaError < Error; end

  # Client provides only tweet
  class Client
    TW_API_ORIGIN = "https://api.twitter.com"
    TW_UPLOAD_ORIGIN = "https://upload.twitter.com"
    TW_MEDIA_UPLOAD_PATH = "/1.1/media/upload.json"
    APPEND_PER = 5 * (1 << 20)

    def initialize(consumer_key:, consumer_secret:, access_token:, access_token_secret:, max_append_retry: 3)
      @consumer_key_ = consumer_key
      @consumer_secret_ = consumer_secret
      @access_token_ = access_token
      @access_token_secret_ = access_token_secret
      @max_append_retry_ = max_append_retry
    end

    # https://developer.twitter.com/en/docs/twitter-api/v1/tweets/post-and-engage/api-reference/post-statuses-update
    def tweet(message:, media_ids: [])
      path = "/1.1/statuses/update.json?status=#{::CGI.escape(message)}"
      path += "&media_ids=#{media_ids.join(",")}" unless media_ids.empty?
      Tweet.from_response(access_token.post(path))
    end

    # media_type is mime_type
    def tweet_with_media(message:, media_type:, media:)
      media_ids = upload_media(media_type: media_type, media: media)
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
      https = ::Net::HTTP.new(url.host, url.port)
      https.use_ssl = true

      https.start do |http|
        http.request req
      end
    end

    # https://developer.twitter.com/en/docs/twitter-api/v1/media/upload-media/api-reference/post-media-upload
    ## maybe todo: multiple image
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
      raise UploadMediaError unless init_res.code == "202"

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
      return if request(append_req).code == "204"
      raise UploadMediaError unless retry_count <= @max_append_retry_

      append(video: video, media_id: media_id, index: index, retry_count: retry_count + 1)
    end

    def finalize(media_id:)
      finalize_req = ::Net::HTTP::Post::Multipart.new(
        TW_MEDIA_UPLOAD_PATH,
        command: "FINALIZE",
        media_id: media_id
      )
      finalize_res = request(finalize_req)
      raise UploadMediaError unless finalize_res.code == "201"

      ::JSON.parse(finalize_res.body)
    end

    def status(media_id:)
      status_req = ::Net::HTTP::Post::Multipart.new(
        TW_MEDIA_UPLOAD_PATH,
        command: "STATUS",
        media_id: media_id
      )
      status_res = request(status_req)
      raise UploadMediaError unless status_res.code == "200"

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
  end

  # Twitter::Tweetに近いinterfaceを提供する。
  ## 使ってない部分のhashの中身のhashとかは正規化されてないので、必要になったら足す必要がある。
  ### todo: entities, media, ...
  ## 逆に、本体とuserのところだけHashから変換している。
  Tweet = ::Struct.new(
    :created_at,
    :id,
    :id_str,
    :text,
    :truncated,
    :entities,
    :source,
    :in_reply_to_status_id,
    :in_reply_to_status_id_str,
    :in_reply_to_user_id,
    :in_reply_to_user_id_str,
    :in_reply_to_screen_name,
    :user,
    :geo,
    :coordinates,
    :place,
    :contributors,
    :is_quote_status,
    :retweet_count,
    :favorite_count,
    :favorited,
    :retweeted,
    :lang,
    :extended_entities,
    :possibly_sensitive,
    :quoted_status_id,
    :quoted_status_id_str,
    :quoted_status,
    keyword_init: true
  )
  User = ::Struct.new(
    :id,
    :id_str,
    :name,
    :screen_name,
    :location,
    :description,
    :url,
    :entities,
    :protected,
    :followers_count,
    :friends_count,
    :listed_count,
    :created_at,
    :favourites_count,
    :utc_offset,
    :time_zone,
    :geo_enabled,
    :verified,
    :statuses_count,
    :lang,
    :contributors_enabled,
    :is_translator,
    :is_translation_enabled,
    :profile_background_color,
    :profile_background_image_url,
    :profile_background_image_url_https,
    :profile_background_tile,
    :profile_image_url,
    :profile_image_url_https,
    :profile_banner_url,
    :profile_link_color,
    :profile_sidebar_border_color,
    :profile_sidebar_fill_color,
    :profile_text_color,
    :profile_use_background_image,
    :has_extended_profile,
    :default_profile,
    :default_profile_image,
    :following,
    :follow_request_sent,
    :notifications,
    :translator_type,
    :withheld_in_countries,
    keyword_init: true
  )

  # Tweet is like Twitter::Tweet
  class Tweet
    def self.from_response(response)
      return nil unless response.code == "200"

      res = ::JSON.parse(response.body)
      tw = Tweet.new(**res)
      tw.created_at = ::Time.parse(tw.created_at).utc
      tw.user = User.new(**res["user"])
      tw
    end

    def uri
      "https://twitter.com/#{user.screen_name}/status/#{id}"
    end
    alias url uri

    def to_h
      super.map do |k, v|
        if k == :user
          [k.to_s, v.to_h]
        else
          [k.to_s, v]
        end
      end.to_h
    end
  end

  # User is
  class User
    def protected?
      protected
    end

    def to_h
      super.transform_keys(&:to_s)
    end
  end
end
