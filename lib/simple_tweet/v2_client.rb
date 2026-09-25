# frozen_string_literal: true

require "json"
require "cgi"
require "stringio"
require "oauth"
require "net/http/post/multipart"

module SimpleTweet
  module V2
    # Twitte API v2を叩くクライアント
    class Client
      TW_API_ORIGIN = "https://api.twitter.com"
      TW_MEDIA_UPLOAD_PATH = "/2/media/upload"
      TW_MEDIA_INITIALIZE_PATH = "/2/media/upload/initialize"
      TW_MEDIA_METADATA_PATH = "/2/media/metadata"
      TW_TWEET_PATH = "/2/tweets"
      UA = "SimpleTweet/#{SimpleTweet::VERSION}".freeze
      APPEND_PER = 5 * (1 << 20)
      SUCCESS_STATUS_CODE = /^2\d\d$/
      # 4xxはリトライしても結果が変わらないので、一時的な失敗だけ再送する。
      RETRYABLE_STATUS_CODE = /^(5\d\d|429)$/
      DEFAULT_MAX_RETRY = 3
      # 再送の待ち時間は指数で伸ばすが、max_retryを大きくした時に伸びすぎないよう頭を打たせる。
      BACKOFF_MAX_SECS = 30
      # 処理中を表すstate。succeededでもこれらでもない場合は失敗扱いにする。
      PROCESSING_STATES = %w[pending in_progress].freeze
      DEFAULT_CHECK_AFTER_SECS = 5
      # check_after_secsに0が入っていてもXを叩き続けないようにする。
      MIN_CHECK_AFTER_SECS = 1

      def initialize(consumer_key:, consumer_secret:, access_token:, access_token_secret:, max_retry: DEFAULT_MAX_RETRY)
        @consumer_key_ = consumer_key
        @consumer_secret_ = consumer_secret
        @access_token_ = access_token
        @access_token_secret_ = access_token_secret
        @max_retry_ = max_retry
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

      def access_token
        consumer = ::OAuth::Consumer.new(@consumer_key_, @consumer_secret_, site: TW_API_ORIGIN)
        ::OAuth::AccessToken.new(consumer, @access_token_, @access_token_secret_)
      end

      def request(req)
        @client ||= access_token
        # 署名済みのreqを再送する場合、前回のAuthorizationヘッダのoauth_*が
        # 署名対象パラメータに混ざってしまうので、署名し直す前に消す。
        req.delete("Authorization")
        @client.sign! req

        url = ::URI.parse(TW_API_ORIGIN)
        https = ::Net::HTTP.new(
          url.host, # : ::String
          url.port
        )
        https.use_ssl = true

        https.start do |http|
          http.request req
        end
      end

      def request_with_retry(req:, error_kind_message:, expected_status_code: SUCCESS_STATUS_CODE,
                             retry_count: @max_retry_)
        res = request(req)
        return res if expected_status_code === res.code # rubocop:disable Style/CaseEquality
        unless retry_count.positive? && RETRYABLE_STATUS_CODE === res.code
          raise UploadMediaError.new(ResponseParser.error_message(res, error_kind_message), response: res)
        end

        @client = nil # reset client
        sleep backoff_secs(retry_count)
        # multipartのbodyはstreamなので、読み切った状態のまま再送すると空のbodyになる。
        req.body_stream.rewind if req.body_stream.respond_to?(:rewind)
        request_with_retry(
          req: req,
          expected_status_code: expected_status_code,
          error_kind_message: error_kind_message,
          retry_count: retry_count - 1
        )
      end

      def backoff_secs(retry_count)
        secs = 1 << (@max_retry_ - retry_count)
        return BACKOFF_MAX_SECS if secs > BACKOFF_MAX_SECS

        secs
      end

      def json_request(path, body)
        header = {
          "User-Agent" => UA,
          "content-type" => "application/json; charset=UTF-8"
        } # : ::Hash[::String, ::String]
        req = ::Net::HTTP::Post.new(path, header)
        req.body = body.to_json
        req
      end

      # https://docs.x.com/x-api/media/upload-media
      ## maybe todo: multiple image
      def upload_media(media_type:, media:)
        media_type = MediaType.normalize(media_type)
        return upload_video(video: media, media_type: media_type) if MediaType.video?(media_type)

        req = ::Net::HTTP::Post::Multipart.new(
          TW_MEDIA_UPLOAD_PATH,
          media: ::UploadIO.new(media, media_type),
          media_category: MediaType.category(media_type)
        )
        res = request_with_retry(req: req, error_kind_message: "upload media failed")
        data = ResponseParser.data_of(res, "upload media failed")
        media_id = ResponseParser.media_id_from(data, res)
        # gifなどはこのレスポンスにもprocessing_infoが入ることがある。
        wait_for_processing(media_id: media_id, processing_info: data["processing_info"])
        [media_id]
      end

      # https://docs.x.com/x-api/media/media-upload-initialize
      def init(video:, media_type: MediaType::VIDEO)
        init_req = json_request(
          TW_MEDIA_INITIALIZE_PATH,
          {
            media_type: media_type,
            total_bytes: video.size,
            media_category: MediaType.category(media_type)
          }
        )
        init_res = request_with_retry(req: init_req, error_kind_message: "init failed")
        ResponseParser.media_id_from(ResponseParser.data_of(init_res, "init failed"), init_res)
      end

      # https://docs.x.com/x-api/media/media-upload-append
      def append(video:, media_id:, index:)
        req = ::Net::HTTP::Post::Multipart.new(
          "#{TW_MEDIA_UPLOAD_PATH}/#{media_id}/append",
          media: ::UploadIO.new(::StringIO.new(video.read(APPEND_PER)), "application/octet-stream", "chunk"),
          segment_index: index
        )
        res = request_with_retry(req: req, error_kind_message: "append failed")
        ResponseParser.ensure_no_errors(res, "append failed")
        res
      end

      # https://docs.x.com/x-api/media/media-upload-finalize
      def finalize(media_id:)
        req = ::Net::HTTP::Post.new("#{TW_MEDIA_UPLOAD_PATH}/#{media_id}/finalize", { "User-Agent" => UA })
        req.body = ""
        # finalizeが成功していても、processing_infoが返る場合がある(upload_video中で処理)。
        res = request_with_retry(req: req, error_kind_message: "finalize failed")
        ResponseParser.data_of(res, "finalize failed")
      end

      # https://docs.x.com/x-api/media/get-media-upload-status
      # これはGET
      def status(media_id:)
        uri = ::URI.parse(TW_API_ORIGIN + TW_MEDIA_UPLOAD_PATH)
        uri.query = ::URI.encode_www_form(command: "STATUS", media_id: media_id)
        req = ::Net::HTTP::Get.new(uri)
        res = request_with_retry(req: req, error_kind_message: "status failed")
        ResponseParser.data_of(res, "status failed")
      end

      # https://docs.x.com/x-api/media/quickstart/media-upload-chunked
      def upload_video(video:, media_type: MediaType::VIDEO)
        media_id = init(video: video, media_type: media_type)

        chunks_needed = (video.size - 1) / APPEND_PER + 1
        chunks_needed.times do |i|
          append(video: video, media_id: media_id, index: i)
        end

        finalize_res = finalize(media_id: media_id)
        wait_for_processing(media_id: media_id, processing_info: finalize_res["processing_info"])

        [media_id]
      end

      def wait_for_processing(media_id:, processing_info:)
        return if processing_info.nil?

        info = processing_info
        loop do
          state = info["state"]
          break if state == "succeeded"
          raise UploadMediaError, "media processing failed: #{state.inspect}" unless PROCESSING_STATES.include?(state)

          sleep(check_after_secs(info))
          info = status(media_id: media_id)["processing_info"]
          raise UploadMediaError, "processing_info not found in status response" if info.nil?
        end
      end

      def check_after_secs(processing_info)
        secs = processing_info["check_after_secs"]
        return DEFAULT_CHECK_AFTER_SECS unless secs.is_a?(::Numeric)
        return MIN_CHECK_AFTER_SECS if secs < MIN_CHECK_AFTER_SECS

        secs
      end

      # https://docs.x.com/x-api/media/create-media-metadata
      def create_media_metadata(media_id:, alt_text:)
        req = json_request(TW_MEDIA_METADATA_PATH, { id: media_id, metadata: { alt_text: { text: alt_text } } })
        res = request_with_retry(req: req, error_kind_message: "create_media_metadata failed")
        ResponseParser.ensure_no_errors(res, "create_media_metadata failed")
        res
      end
    end
  end
end
