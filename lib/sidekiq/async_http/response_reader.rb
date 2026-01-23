# frozen_string_literal: true

module Sidekiq
  module AsyncHttp
    # Reads and validates HTTP response bodies.
    #
    # Encapsulates the logic for reading async HTTP responses with size validation
    # and building Response objects from the raw response data.
    class ResponseReader
      # @return [Configuration] the configuration object
      attr_reader :config

      # Initialize the reader.
      #
      # @param config [Configuration] the configuration object
      def initialize(config)
        @config = config
      end

      # Read the response body with size validation.
      #
      # Reads the async HTTP response body asynchronously to completion, which allows
      # the connection to be reused. The async-http client handles connection pooling
      # and keep-alive internally. Using iteration instead of read() ensures non-blocking
      # I/O that yields to the reactor.
      #
      # @param async_response [Async::HTTP::Protocol::Response] the async HTTP response
      # @param headers_hash [Hash] the response headers
      # @return [String, nil] the response body or nil if no body present
      # @raise [ResponseTooLargeError] if body exceeds max_response_size
      def read_body(async_response, headers_hash)
        return nil unless async_response.body

        validate_content_length(headers_hash)
        read_body_chunks(async_response)
      end

      # Build a Response object from async response data.
      #
      # @param task [RequestTask] the original request task
      # @param response_data [Hash] the response data with :status, :headers, :body, :protocol
      # @return [Response] the response object
      def build_response(task, response_data)
        Response.new(
          status: response_data[:status],
          headers: response_data[:headers],
          body: response_data[:body],
          protocol: response_data[:protocol],
          duration: task.duration,
          request_id: task.id,
          url: task.request.url,
          http_method: task.request.http_method
        )
      end

      private

      # Validate content-length header doesn't exceed max size.
      #
      # @param headers_hash [Hash] the response headers
      # @raise [ResponseTooLargeError] if content-length exceeds max_response_size
      def validate_content_length(headers_hash)
        content_length = headers_hash["content-length"]&.to_i
        return unless content_length && content_length > @config.max_response_size

        raise ResponseTooLargeError.new(
          "Response body size (#{content_length} bytes) exceeds maximum allowed size (#{@config.max_response_size} bytes)"
        )
      end

      # Read body chunks while checking size.
      #
      # @param async_response [Async::HTTP::Protocol::Response] the async HTTP response
      # @return [String] the response body
      # @raise [ResponseTooLargeError] if body size exceeds max_response_size during read
      def read_body_chunks(async_response)
        chunks = []
        total_size = 0

        async_response.body.each do |chunk|
          total_size += chunk.bytesize

          if total_size > @config.max_response_size
            raise ResponseTooLargeError.new(
              "Response body size exceeded maximum allowed size (#{@config.max_response_size} bytes)"
            )
          end

          chunks << chunk
        end

        chunks.join
      end
    end
  end
end
