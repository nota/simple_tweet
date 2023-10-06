# frozen_string_literal: true

RSpec.describe SimpleTweet do
  it "has a version number" do
    expect(SimpleTweet::VERSION).not_to be nil
  end

  describe ".tweet" do
    let(:twitter_client) do
      SimpleTweet::V2::Client.new(
        consumer_key: "twitter_consumer_key",
        consumer_secret: "twitter_consumer_secret",
        access_token: "twitter_access_token",
        access_token_secret: "twitter_access_secret"
      )
    end
    let(:message) { "tweet!!" }

    context "tweet only message" do
      let(:tweet_id) { "12345678901234567890" }
      let!(:stub_tweet_request) do
        stub_request(
          :post,
          SimpleTweet::V2::Client::TW_API_ORIGIN + SimpleTweet::V2::Client::TW_TWEET_PATH
        ).to_return(
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
end
