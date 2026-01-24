# frozen_string_literal: true

require "uri"
require "async/http"
require "protocol/http/headers"
require "protocol/http/body/buffered"

module Sidekiq
  module AsyncHttp
    # Builds Async::HTTP::Protocol::Request objects from Request objects.
    #
    # Encapsulates the logic for converting the library's Request objects
    # into the format required by the async-http library.
    class RequestBuilder
      # Default user agent string when none is configured.
      DEFAULT_USER_AGENT = "sidekiq-async_http"

      # @return [Configuration] the configuration object
      attr_reader :config

      # Initialize the builder.
      #
      # @param config [Configuration] the configuration object
      def initialize(config)
        @config = config
      end

      # Build an Async::HTTP::Protocol::Request from a Request object.
      #
      # @param request [Request] the request object
      # @return [Async::HTTP::Protocol::Request] the async HTTP request
      def build(request)
        uri = URI.parse(request.url)

        Async::HTTP::Protocol::Request.new(
          uri.scheme,
          uri.authority,
          request.http_method.to_s.upcase,
          uri.request_uri,
          nil,
          build_headers(request),
          build_body(request)
        )
      end

      private

      # Build Protocol::HTTP::Headers from request headers.
      #
      # @param request [Request] the request object
      # @return [Protocol::HTTP::Headers] the headers object
      def build_headers(request)
        headers = Protocol::HTTP::Headers.new

        request.headers.each do |key, value|
          headers.add(key, value)
        end

        add_default_user_agent(headers, request)

        headers
      end

      # Add default user agent header if not already present.
      #
      # @param headers [Protocol::HTTP::Headers] the headers object
      # @param request [Request] the request object
      # @return [void]
      def add_default_user_agent(headers, request)
        return if request.headers["user-agent"]

        user_agent = @config.user_agent&.to_s || DEFAULT_USER_AGENT
        headers.add("user-agent", user_agent)
      end

      # Build the request body if present.
      #
      # @param request [Request] the request object
      # @return [Protocol::HTTP::Body::Buffered, nil] the body or nil
      def build_body(request)
        return nil unless request.body

        body_bytes = request.body.to_s
        Protocol::HTTP::Body::Buffered.wrap([body_bytes])
      end
    end
  end
end
