# frozen_string_literal: true

module Sidekiq::AsyncHttp
  # Sidekiq worker for making HTTP requests.
  #
  # This worker is used when calling Sidekiq::AsyncHttp.request() outside of a Sidekiq job.
  # It allows async HTTP requests to be enqueued and processed through the standard
  # Sidekiq job lifecycle.
  class RequestWorker
    include Sidekiq::Job

    # Perform the HTTP request.
    #
    # @param request_data [Hash] Serialized request data with keys:
    #   - "http_method" [String] HTTP method (get, post, put, patch, delete)
    #   - "url" [String] The request URL
    #   - "headers" [Hash] Request headers
    #   - "body" [String, nil] Request body
    #   - "timeout" [Numeric, nil] Request timeout
    #   - "max_redirects" [Integer, nil] Maximum redirects to follow
    # @param callback_service_name [String] Fully qualified callback service class name
    # @param raise_error_responses [Boolean, nil] Whether to treat non-2xx responses as errors;
    #   defaults to the global config if nil
    # @param callback_args [Hash, nil] Arguments to pass to the callback
    # @param request_id [String, nil] Unique request ID for tracking
    # @return [void]
    def perform(request_data, callback_service_name, raise_error_responses, callback_args, request_id)
      request = Request.load(request_data)
      sidekiq_job = Sidekiq::AsyncHttp::Context.current_job

      request.execute(
        callback: callback_service_name,
        raise_error_responses: raise_error_responses,
        callback_args: callback_args,
        sidekiq_job: sidekiq_job,
        request_id: request_id
      )
    end
  end
end
