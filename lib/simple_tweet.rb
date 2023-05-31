# frozen_string_literal: true

require_relative "simple_tweet/version"
require_relative "simple_tweet/v1_client"
require "cgi"
require "oauth"
require "json"
require "net/http/post/multipart"

module SimpleTweet
  class Error < ::StandardError; end
  class UploadMediaError < Error; end

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
