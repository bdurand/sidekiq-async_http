# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sidekiq::AsyncHttp::Request do
  # Define test worker classes
  class TestSuccessWorker
    include Sidekiq::Job
  end

  class TestErrorWorker
    include Sidekiq::Job
  end

  class ContextWorker
    include Sidekiq::Job
  end

  describe "#initialize" do
    it "creates a request with valid parameters" do
      request = described_class.new(
        method: :get,
        url: "https://api.example.com/users",
        headers: {"Authorization" => "Bearer token"},
        body: nil,
        timeout: 30
      )

      expect(request.method).to eq(:get)
      expect(request.url).to eq("https://api.example.com/users")
      expect(request.headers).to eq({"Authorization" => "Bearer token"})
      expect(request.body).to be_nil
      expect(request.timeout).to eq(30)
    end

    it "accepts a URI object for url" do
      uri = URI("https://api.example.com/users")
      request = described_class.new(method: :get, url: uri)

      expect(request.url).to eq(uri)
    end

    context "validation" do
      it "casts method to a symbol" do
        request = described_class.new(method: "POST", url: "https://example.com")
        expect(request.method).to eq(:post)
      end

      it "validates method is a valid HTTP method" do
        expect do
          described_class.new(method: :invalid, url: "https://example.com")
        end.to raise_error(ArgumentError, /method must be one of/)
      end

      it "accepts all valid HTTP methods" do
        %i[get post put patch delete].each do |method|
          expect do
            described_class.new(method: method, url: "https://example.com")
          end.not_to raise_error
        end
      end

      it "validates url is present" do
        expect do
          described_class.new(method: :get, url: nil)
        end.to raise_error(ArgumentError, "url is required")
      end

      it "validates url is not empty" do
        expect do
          described_class.new(method: :get, url: "")
        end.to raise_error(ArgumentError, "url is required")
      end

      it "validates url is a String or URI" do
        expect do
          described_class.new(method: :get, url: 123)
        end.to raise_error(ArgumentError, "url must be a String or URI, got: Integer")
      end
    end
  end
end
