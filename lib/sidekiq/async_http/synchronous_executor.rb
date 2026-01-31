# frozen_string_literal: true

module Sidekiq::AsyncHttp
  # Handles synchronous/inline execution of HTTP requests.
  #
  # Used when Sidekiq::Testing.inline! is enabled or when
  # synchronous: true is passed to Request#execute.
  class SynchronousExecutor
    # @param task [RequestTask] the request task to execute
    def initialize(task)
      @task = task
      @config = Sidekiq::AsyncHttp.configuration
    end

    # Execute the request synchronously.
    # @return [void]
    def call
      Async do
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        begin
          http_client = Async::HTTP::Internet.new(retries: 3)
          timeout = @task.request.timeout || @config.request_timeout

          response_data = Async::Task.current.with_timeout(timeout) do
            headers = @task.request.headers.to_h.merge("x-request-id" => @task.id)
            headers["user-agent"] ||= @config.user_agent if @config.user_agent
            body = Protocol::HTTP::Body::Buffered.wrap([@task.request.body.to_s]) if @task.request.body

            async_response = http_client.call(@task.request.http_method, @task.request.url, headers, body)
            headers_hash = async_response.headers.to_h.transform_values(&:to_s)

            # Read body
            body_content = read_response_body(async_response, headers_hash)

            {
              status: async_response.status,
              headers: headers_hash,
              body: body_content
            }
          end

          end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          duration = end_time - start_time

          # Build response
          response = Response.new(
            status: response_data[:status],
            headers: response_data[:headers],
            body: response_data[:body],
            duration: duration,
            request_id: @task.id,
            url: @task.request.url,
            http_method: @task.request.http_method,
            callback_args: @task.callback_args
          )

          # Check if we should raise an error for non-2xx responses
          if @task.raise_error_responses && !response.success?
            http_error = HttpError.new(response)
            invoke_callback(http_error, :error)
          else
            invoke_callback(response, :response)
          end
        rescue => e
          end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          duration = end_time - start_time

          error = RequestError.from_exception(
            e,
            request_id: @task.id,
            duration: duration,
            url: @task.request.url,
            http_method: @task.request.http_method,
            callback_args: @task.callback_args
          )
          invoke_callback(error, :error)
        ensure
          http_client&.close
        end
      end
    end

    private

    # Read the response body with size validation.
    #
    # @param async_response [Async::HTTP::Protocol::Response] the async HTTP response
    # @param headers_hash [Hash] the response headers
    # @return [String, nil] the response body
    def read_response_body(async_response, headers_hash)
      return nil unless async_response.body

      # Validate content-length
      content_length = headers_hash["content-length"]&.to_i
      if content_length && content_length > @config.max_response_size
        raise ResponseTooLargeError.new(
          "Response body size (#{content_length} bytes) exceeds maximum allowed size (#{@config.max_response_size} bytes)"
        )
      end

      # Read chunks
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

      body = chunks.join.force_encoding(Encoding::ASCII_8BIT)

      # Apply charset encoding
      charset = extract_charset(headers_hash)
      if charset
        begin
          encoding = Encoding.find(charset)
          body.force_encoding(encoding)
        rescue ArgumentError
          # Invalid charset, keep binary
        end
      end

      body
    end

    # Extract charset from Content-Type header.
    def extract_charset(headers_hash)
      content_type = headers_hash["content-type"]
      return nil unless content_type

      match = content_type.match(/;\s*charset\s*=\s*([^;\s]+)/i)
      return nil unless match

      charset = match[1].strip
      charset.gsub(/\A["']|["']\z/, "")
    end

    # Invoke callback synchronously.
    #
    # @param result [Response, Error] the result to pass to callback
    # @param type [Symbol] :response or :error
    def invoke_callback(result, type)
      callback_class = @task.callback.is_a?(Class) ? @task.callback : ClassHelper.resolve_class_name(@task.callback)
      callback = callback_class.new

      if type == :response
        Sidekiq::AsyncHttp.invoke_completion_callbacks(result)
        callback.on_complete(result)
      else
        Sidekiq::AsyncHttp.invoke_error_callbacks(result)
        callback.on_error(result)
      end
    end
  end
end
