# frozen_string_literal: true

RSpec.describe SimpleTweet do
  it "has a version number" do
    expect(SimpleTweet::VERSION).not_to be nil
  end

  describe "tweet text" do
    let(:twitter_client) do
      SimpleTweet::Client.new(
        consumer_key: "twitter_consumer_key",
        consumer_secret: "twitter_consumer_secret",
        access_token: "twitter_access_token",
        access_token_secret: "twitter_access_secret"
      )
    end
    let(:message) { "tweet!!" }
    let!(:stub_tweet_request) do
      stub_request(
        :post,
        SimpleTweet::Client::TW_API_ORIGIN + "/1.1/statuses/update.json?status=#{::CGI.escape(message)}"
      ).to_return(
        body: { text: message, created_at: Time.now, user: {} }.to_json,
        status: 200,
        headers: { "Content-Type" => "application/json" }
      )
    end

    subject do
      twitter_client.tweet(message: message)
    end

    it "post tweet request" do
      expect(subject.text).to eq(message)
    end
  end
end
