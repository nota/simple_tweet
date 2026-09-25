# frozen_string_literal: true

require "json"

module SimpleTweet
  module V2
    # X API v2のレスポンスを読み解く。
    # v2は2xxでもbodyにerrorsだけが入っている事があるので、
    # HTTPの成功と操作の成功を分けて判定する。
    module ResponseParser
      DETAIL_MAX_LENGTH = 200

      module_function

      # dataが無ければ失敗として扱う。
      def data_of(res, error_kind_message)
        data = parsed_body(res, error_kind_message)["data"]
        raise UploadMediaError.new(error_message(res, error_kind_message), response: res) unless data.is_a?(::Hash)

        data
      end

      # dataを読まないリクエスト用。errorsだけが返っていたら失敗として扱う。
      def ensure_no_errors(res, error_kind_message)
        parsed = safe_parse(res) || {}
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

      def parsed_body(res, error_kind_message)
        parsed = safe_parse(res)
        raise UploadMediaError.new(error_message(res, error_kind_message), response: res) unless parsed.is_a?(::Hash)

        parsed
      end

      # Xが何を返したかを利用側まで持っていく。status codeも載せないと、
      # 認証・権限・リクエスト内容のどれで落ちたのかが分からない。
      def error_message(res, error_kind_message)
        detail = error_detail(res)
        "#{error_kind_message}: #{res.code}#{detail.nil? ? "" : " #{detail}"}"
      end

      def error_detail(res)
        structured_detail(res) || raw_body_detail(res)
      end

      def structured_detail(res)
        parsed = safe_parse(res)
        return nil unless parsed.is_a?(::Hash)

        first_error_detail(parsed["errors"]) || parsed["detail"] || parsed["title"]
      end

      def first_error_detail(errors)
        return nil unless errors.is_a?(::Array)

        first = errors.first
        return nil unless first.is_a?(::Hash)

        first["detail"] || first["title"] || first["message"]
      end

      # JSONで読めない時（HTMLのエラーページ等）は生のbodyを短く載せる
      def raw_body_detail(res)
        body = res.body.to_s.strip.gsub(/\s+/, " ")
        body.empty? ? nil : body[0, DETAIL_MAX_LENGTH]
      end

      def safe_parse(res)
        body = res.body.to_s
        return nil if body.strip.empty?

        ::JSON.parse(body)
      rescue ::JSON::ParserError
        nil
      end
    end
  end
end
