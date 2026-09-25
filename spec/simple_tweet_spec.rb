# frozen_string_literal: true

RSpec.describe SimpleTweet do
  it "has a version number" do
    expect(SimpleTweet::VERSION).not_to be nil
  end

  let(:twitter_client) do
    SimpleTweet::V2::Client.new(
      consumer_key: "twitter_consumer_key",
      consumer_secret: "twitter_consumer_secret",
      access_token: "twitter_access_token",
      access_token_secret: "twitter_access_secret"
    )
  end
  let(:message) { "tweet!!" }
  let(:tweet_id) { "12345678901234567890" }
  let(:media_id) { "1234567890123456789" }
  let(:tweet_url) { SimpleTweet::V2::Client::TW_API_ORIGIN + SimpleTweet::V2::Client::TW_TWEET_PATH }
  let(:media_upload_url) { SimpleTweet::V2::Client::TW_API_ORIGIN + SimpleTweet::V2::Client::TW_MEDIA_UPLOAD_PATH }
  let(:media_initialize_url) do
    SimpleTweet::V2::Client::TW_API_ORIGIN + SimpleTweet::V2::Client::TW_MEDIA_INITIALIZE_PATH
  end
  let(:media_metadata_url) { SimpleTweet::V2::Client::TW_API_ORIGIN + SimpleTweet::V2::Client::TW_MEDIA_METADATA_PATH }

  let!(:stub_tweet_request) do
    stub_request(:post, tweet_url).to_return(
      body: {
        data: {
          edit_history_tweet_ids: [tweet_id],
          id: tweet_id,
          text: message
        }
      }.to_json,
      status: 201
    )
  end

  describe ".tweet" do
    context "tweet only message" do
      subject { twitter_client.tweet(message: message) }
      before { subject }

      it "will success tweet" do
        expect(stub_tweet_request).to have_been_requested
      end

      it "returns tweet response" do
        expect(JSON.parse(subject.body).dig("data", "text")).to eq(message)
      end
    end
  end

  describe ".tweet_with_media" do
    context "with an image" do
      let!(:stub_upload_request) do
        stub_request(:post, media_upload_url).to_return(
          body: { data: { id: media_id, media_key: "3_#{media_id}" } }.to_json,
          status: 200
        )
      end

      subject do
        twitter_client.tweet_with_media(
          message: message,
          media_type: "image/png",
          media: StringIO.new("dummy image")
        )
      end
      before { subject }

      it "uploads the image to the v2 endpoint as tweet_image" do
        expect(stub_upload_request).to have_been_requested
        expect(
          a_request(:post, media_upload_url).with { |req| req.body.include?("tweet_image") }
        ).to have_been_made
      end

      it "posts the tweet with the media_id taken from data.id" do
        expect(
          a_request(:post, tweet_url).with do |req|
            JSON.parse(req.body).dig("media", "media_ids") == [media_id]
          end
        ).to have_been_made
      end
    end

    context "with an image/jpg media_type" do
      before do
        stub_request(:post, media_upload_url).to_return(
          body: { data: { id: media_id } }.to_json,
          status: 200
        )
        twitter_client.tweet_with_media(
          message: message,
          media_type: "image/jpg",
          media: StringIO.new("dummy image")
        )
      end

      it "normalizes the media_type to image/jpeg" do
        expect(
          a_request(:post, media_upload_url).with { |req| req.body.include?("image/jpeg") }
        ).to have_been_made
      end
    end

    context "with a gif" do
      before do
        stub_request(:post, media_upload_url).to_return(
          body: { data: { id: media_id } }.to_json,
          status: 200
        )
        twitter_client.tweet_with_media(
          message: message,
          media_type: "image/gif",
          media: StringIO.new("dummy gif")
        )
      end

      it "uploads the gif as tweet_gif" do
        expect(
          a_request(:post, media_upload_url).with { |req| req.body.include?("tweet_gif") }
        ).to have_been_made
      end
    end

    context "with alt_text" do
      let(:alt_text) { "dancing cat" }
      let!(:stub_metadata_request) do
        stub_request(:post, media_metadata_url).to_return(
          body: { data: { id: media_id } }.to_json,
          status: 200
        )
      end

      before do
        stub_request(:post, media_upload_url).to_return(
          body: { data: { id: media_id } }.to_json,
          status: 200
        )
        twitter_client.tweet_with_media(
          message: message,
          media_type: "image/png",
          media: StringIO.new("dummy image"),
          alt_text: alt_text
        )
      end

      it "creates the media metadata with the v2 body" do
        expect(stub_metadata_request).to have_been_requested
        expect(
          a_request(:post, media_metadata_url).with do |req|
            JSON.parse(req.body) == { "id" => media_id, "metadata" => { "alt_text" => { "text" => alt_text } } }
          end
        ).to have_been_made
      end
    end

    context "when uploading the image fails with 4xx" do
      before do
        allow(twitter_client).to receive(:sleep)
        stub_request(:post, media_upload_url).to_return(
          body: { detail: "Unauthorized" }.to_json,
          status: 401
        )
      end

      it "raises UploadMediaError instead of tweeting with a nil media_id" do
        expect do
          twitter_client.tweet_with_media(
            message: message,
            media_type: "image/png",
            media: StringIO.new("dummy image")
          )
        end.to raise_error(SimpleTweet::UploadMediaError, "upload media failed")
        expect(stub_tweet_request).not_to have_been_requested
      end

      it "does not retry" do
        expect do
          twitter_client.tweet_with_media(
            message: message,
            media_type: "image/png",
            media: StringIO.new("dummy image")
          )
        end.to raise_error(SimpleTweet::UploadMediaError)
        expect(a_request(:post, media_upload_url)).to have_been_made.once
      end
    end

    context "when uploading the image fails with 5xx" do
      before do
        allow(twitter_client).to receive(:sleep)
        stub_request(:post, media_upload_url)
          .to_return(body: "", status: 503)
          .then
          .to_return(body: { data: { id: media_id } }.to_json, status: 200)
        twitter_client.tweet_with_media(
          message: message,
          media_type: "image/png",
          media: StringIO.new("dummy image")
        )
      end

      it "retries the upload and tweets" do
        expect(a_request(:post, media_upload_url)).to have_been_made.twice
        expect(
          a_request(:post, tweet_url).with do |req|
            JSON.parse(req.body).dig("media", "media_ids") == [media_id]
          end
        ).to have_been_made
      end
    end

    context "when the upload response is still processing" do
      let!(:stub_status_request) do
        stub_request(:get, media_upload_url)
          .with(query: { command: "STATUS", media_id: media_id })
          .to_return(
            body: { data: { id: media_id, processing_info: { state: "succeeded" } } }.to_json,
            status: 200
          )
      end

      before do
        allow(twitter_client).to receive(:sleep)
        stub_request(:post, media_upload_url).to_return(
          body: {
            data: { id: media_id, processing_info: { state: "pending", check_after_secs: 0 } }
          }.to_json,
          status: 200
        )
        twitter_client.tweet_with_media(
          message: message,
          media_type: "image/gif",
          media: StringIO.new("dummy gif")
        )
      end

      it "waits for the processing to succeed before tweeting" do
        expect(stub_status_request).to have_been_requested
        expect(stub_tweet_request).to have_been_requested
      end
    end

    context "when the upload response has no media_id" do
      before do
        stub_request(:post, media_upload_url).to_return(body: { data: {} }.to_json, status: 200)
      end

      it "raises UploadMediaError" do
        expect do
          twitter_client.tweet_with_media(
            message: message,
            media_type: "image/png",
            media: StringIO.new("dummy image")
          )
        end.to raise_error(SimpleTweet::UploadMediaError, "media_id not found in response")
      end
    end

    context "with max_retry" do
      let(:twitter_client) do
        SimpleTweet::V2::Client.new(
          consumer_key: "twitter_consumer_key",
          consumer_secret: "twitter_consumer_secret",
          access_token: "twitter_access_token",
          access_token_secret: "twitter_access_secret",
          max_retry: 1
        )
      end

      before do
        allow(twitter_client).to receive(:sleep)
        stub_request(:post, media_upload_url).to_return(body: "", status: 503)
      end

      it "retries as many times as given" do
        expect do
          twitter_client.tweet_with_media(
            message: message,
            media_type: "image/png",
            media: StringIO.new("dummy image")
          )
        end.to raise_error(SimpleTweet::UploadMediaError)
        expect(a_request(:post, media_upload_url)).to have_been_made.twice
      end
    end

    context "when the upload returns 2xx with errors and no data" do
      before do
        allow(twitter_client).to receive(:sleep)
        stub_request(:post, media_upload_url).to_return(
          body: { errors: [{ title: "Unsupported Media Type", detail: "media is not supported" }] }.to_json,
          status: 200
        )
      end

      it "raises UploadMediaError instead of tweeting" do
        expect do
          twitter_client.tweet_with_media(
            message: message,
            media_type: "image/png",
            media: StringIO.new("dummy image")
          )
        end.to raise_error(SimpleTweet::UploadMediaError, /upload media failed: media is not supported/)
        expect(stub_tweet_request).not_to have_been_requested
      end
    end

    context "when the upload returns 2xx with a body that is not JSON" do
      before do
        stub_request(:post, media_upload_url).to_return(body: "<html>error</html>", status: 200)
      end

      it "raises UploadMediaError" do
        expect do
          twitter_client.tweet_with_media(
            message: message,
            media_type: "image/png",
            media: StringIO.new("dummy image")
          )
        end.to raise_error(SimpleTweet::UploadMediaError, "upload media failed")
      end
    end

    context "when finalize returns 2xx with errors and no data" do
      before do
        allow(twitter_client).to receive(:sleep)
        stub_request(:post, media_initialize_url).to_return(
          body: { data: { id: media_id } }.to_json, status: 200
        )
        stub_request(:post, "#{media_upload_url}/#{media_id}/append").to_return(
          body: { data: { expires_at: 1 } }.to_json, status: 200
        )
        stub_request(:post, "#{media_upload_url}/#{media_id}/finalize").to_return(
          body: { errors: [{ title: "InternalError", detail: "finalize did not complete" }] }.to_json,
          status: 200
        )
      end

      it "raises UploadMediaError instead of tweeting with an unfinished media_id" do
        expect do
          twitter_client.tweet_with_media(
            message: message,
            media_type: "video/mp4",
            media: StringIO.new("dummy video")
          )
        end.to raise_error(SimpleTweet::UploadMediaError, /finalize failed: finalize did not complete/)
        expect(stub_tweet_request).not_to have_been_requested
      end
    end

    # 署名済みのreqをそのまま再署名すると、前回のAuthorizationのoauth_*が
    # 署名対象パラメータに混ざり、再送の署名が壊れる（oauth gemのRequestProxyが
    # auth_header_paramsを署名ベース文字列に含めるため）。
    # WebMockは署名を検証しないので、署名前のreqの状態を直接確かめる。
    context "when the same request object is signed again" do
      let(:seen_authorizations) { [] }

      before do
        stub_request(:post, media_upload_url).to_return(
          body: { data: { id: media_id } }.to_json, status: 200
        )
        seen = seen_authorizations
        fake_access_token = instance_double(OAuth::AccessToken)
        allow(fake_access_token).to receive(:sign!) do |req|
          seen << req["Authorization"]
          req["Authorization"] = "OAuth oauth_nonce=\"signed\""
        end
        twitter_client.instance_variable_set(:@client, fake_access_token)
      end

      it "drops the previous Authorization header before signing" do
        req = Net::HTTP::Post.new(SimpleTweet::V2::Client::TW_MEDIA_UPLOAD_PATH)
        req.body = ""
        twitter_client.send(:request, req)
        twitter_client.send(:request, req)

        expect(seen_authorizations).to eq([nil, nil])
      end
    end

    # WebMockはbody_streamを読んでbodyに詰め替えてしまい、再送時にstreamが
    # 読み切られたままになる問題を隠してしまうので、ここだけrequestを差し替えて確かめる。
    context "when a multipart request is retried" do
      let(:sent_bodies) { [] }

      before do
        allow(twitter_client).to receive(:sleep)
        bodies = sent_bodies
        responses = [
          instance_double(Net::HTTPResponse, code: "503"),
          instance_double(Net::HTTPResponse, code: "200", body: { data: { id: media_id } }.to_json)
        ]
        allow(twitter_client).to receive(:request) do |req|
          bodies << req.body_stream.read
          responses.shift
        end
        twitter_client.tweet_with_media(
          message: message,
          media_type: "image/png",
          media: StringIO.new("dummy image")
        )
      end

      it "rewinds the body stream so that the retried request sends the same body" do
        expect(sent_bodies.size).to eq(2)
        expect(sent_bodies.first).to include("dummy image")
        expect(sent_bodies.last).to eq(sent_bodies.first)
      end
    end

    context "with a video" do
      let(:append_url) { "#{media_upload_url}/#{media_id}/append" }
      let(:finalize_url) { "#{media_upload_url}/#{media_id}/finalize" }
      let!(:stub_initialize_request) do
        stub_request(:post, media_initialize_url).to_return(
          body: { data: { id: media_id, media_key: "7_#{media_id}", expires_after_secs: 86_400 } }.to_json,
          status: 200
        )
      end
      let!(:stub_append_request) do
        stub_request(:post, append_url).to_return(body: { data: { expires_at: 1 } }.to_json, status: 200)
      end
      let!(:stub_finalize_request) do
        stub_request(:post, finalize_url).to_return(
          body: { data: { id: media_id, processing_info: { state: "in_progress", check_after_secs: 0 } } }.to_json,
          status: 200
        )
      end
      let!(:stub_status_request) do
        stub_request(:get, media_upload_url)
          .with(query: { command: "STATUS", media_id: media_id })
          .to_return(
            body: { data: { id: media_id, processing_info: { state: "succeeded", progress_percent: 100 } } }.to_json,
            status: 200
          )
      end

      before do
        allow(twitter_client).to receive(:sleep)
        twitter_client.tweet_with_media(
          message: message,
          media_type: "video/mp4",
          media: StringIO.new("dummy video")
        )
      end

      it "goes through initialize, append, finalize and status" do
        expect(stub_initialize_request).to have_been_requested
        expect(stub_append_request).to have_been_requested
        expect(stub_finalize_request).to have_been_requested
        expect(stub_status_request).to have_been_requested
      end

      it "initializes the upload as tweet_video with the total bytes" do
        expect(
          a_request(:post, media_initialize_url).with do |req|
            JSON.parse(req.body) == {
              "media_type" => "video/mp4",
              "total_bytes" => "dummy video".bytesize,
              "media_category" => "tweet_video"
            }
          end
        ).to have_been_made
      end

      it "posts the tweet with the media_id" do
        expect(
          a_request(:post, tweet_url).with do |req|
            JSON.parse(req.body).dig("media", "media_ids") == [media_id]
          end
        ).to have_been_made
      end
    end
  end
end
