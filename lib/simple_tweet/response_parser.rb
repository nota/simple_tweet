# frozen_string_literal: true

require "json"

module SimpleTweet
  module V2
    # X API v2のレスポンスを読み解く。
    # v2は2xxでもbodyにerrorsだけが入っている事があるので、
    # HTTPの成功と操作の成功を分けて判定する。
    module ResponseParser
      module_function

      # dataが無ければ失敗として扱う。
      def data_of(res, error_kind_message)
        data = parsed_body(res, error_kind_message)["data"]
        raise UploadMediaError.new(error_message(res, error_kind_message), response: res) unless data.is_a?(::Hash)

        data
      end

      # dataを読まないリクエスト用。errorsだけが返っていたら失敗として扱う。
      def ensure_no_errors(res, error_kind_message)
        parsed = parsed_body(res, error_kind_message, allow_empty: true)
        errors = parsed["errors"]
        return if parsed["data"].is_a?(::Hash) || !errors.is_a?(::Array) || errors.empty?

        raise UploadMediaError.new(error_message(res, error_kind_message), response: res)
      end

      # v1.1のmedia_id_stringと違い、v2はdata.idに入っている。
      def media_id_from(data, res)
        media_id = data["id"]
        unless media_id.is_a?(::String) && !media_id.empty?
          raise UploadMediaError.new("media_id not found in response", response: res)
        end

        media_id
      end

      def parsed_body(res, error_kind_message, allow_empty: false)
        body = res.body.to_s
        return {} if allow_empty && body.strip.empty?

        parsed = ::JSON.parse(body) # : untyped
        raise UploadMediaError.new(error_kind_message, response: res) unless parsed.is_a?(::Hash)

        parsed
      rescue ::JSON::ParserError
        return {} if allow_empty

        raise UploadMediaError.new(error_kind_message, response: res)
      end

      def error_message(res, error_kind_message)
        parsed = parsed_body(res, error_kind_message, allow_empty: true)
        detail = parsed.dig("errors", 0, "detail") || parsed.dig("errors", 0, "title") || parsed["detail"]
        detail.nil? ? error_kind_message : "#{error_kind_message}: #{detail}"
      end
    end
  end
end
