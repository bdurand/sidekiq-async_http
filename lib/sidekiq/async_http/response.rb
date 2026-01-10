# frozen_string_literal: true

require "json"

module Sidekiq
  module AsyncHttp
    # Immutable response object representing an HTTP response
    class Response
      # @return [Integer] HTTP status code
      attr_reader :status

      # @return [HttpHeaders] response headers
      attr_reader :headers

      # @return [String] response body
      attr_reader :body

      # @return [Float] request duration in seconds
      attr_reader :duration

      # @return [String] request ID
      attr_reader :request_id

      # @return [String] HTTP protocol version
      attr_reader :protocol

      # @return [String] request URL
      attr_reader :url

      # @return [Symbol] HTTP method
      attr_reader :method

      # Initialize a Response from an Async::HTTP::Response
      #
      # @param async_response [Async::HTTP::Response] the async HTTP response object
      # @param duration [Float] request duration in seconds
      # @param request_id [String] the request ID
      # @param url [String] the request URL
      # @param method [Symbol] the HTTP method
      def initialize(async_response, duration:, request_id:, url:, method:)
        @status = async_response.status
        @headers = HttpHeaders.new(async_response.headers)
        @body = async_response.read
        @duration = duration
        @request_id = request_id
        @protocol = async_response.protocol
        @url = url
        @method = method
        freeze
      end

      # Check if response is successful (2xx status)
      # @return [Boolean]
      def success?
        status >= 200 && status < 300
      end

      # Check if response is a redirect (3xx status)
      # @return [Boolean]
      def redirect?
        status >= 300 && status < 400
      end

      # Check if response is a client error (4xx status)
      # @return [Boolean]
      def client_error?
        status >= 400 && status < 500
      end

      # Check if response is a server error (5xx status)
      # @return [Boolean]
      def server_error?
        status >= 500 && status < 600
      end

      # Check if response is any error (4xx or 5xx status)
      # @return [Boolean]
      def error?
        status >= 400 && status < 600
      end

      # Parse response body as JSON
      # @return [Hash, Array] parsed JSON
      # @raise [RuntimeError] if Content-Type is not application/json
      # @raise [JSON::ParserError] if body is not valid JSON
      def json
        content_type = headers["content-type"]
        unless content_type&.include?("application/json")
          raise "Response Content-Type is not application/json (got: #{content_type.inspect})"
        end

        JSON.parse(body)
      end

      # Convert to hash with string keys for serialization
      # @return [Hash] hash representation
      def to_h
        {
          "status" => status,
          "headers" => headers.to_h,
          "body" => body,
          "duration" => duration,
          "request_id" => request_id,
          "protocol" => protocol,
          "url" => url,
          "method" => method.to_s
        }
      end

      # Reconstruct a Response from a hash
      # @param hash [Hash] hash representation
      # @return [Response] reconstructed response
      def self.from_h(hash)
        # Create a mock async response object
        mock_response = Struct.new(:status, :headers, :protocol).new(
          hash["status"],
          hash["headers"],
          hash["protocol"]
        )

        # Define read method on the mock
        def mock_response.read
          @body
        end
        mock_response.instance_variable_set(:@body, hash["body"])

        new(
          mock_response,
          duration: hash["duration"],
          request_id: hash["request_id"],
          url: hash["url"],
          method: hash["method"].to_sym
        )
      end
    end
  end
end
