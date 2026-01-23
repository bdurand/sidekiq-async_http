# frozen_string_literal: true

module Sidekiq::AsyncHttp
  # Middleware to handle continuation jobs for async HTTP requests.
  #
  # This middleware processes Sidekiq jobs that are continuations of async HTTP requests,
  # invoking the appropriate callbacks based on whether the request completed successfully
  # or resulted in an error.
  #
  # When processing a retry continuation (from a failed async HTTP request with no error worker),
  # this middleware re-raises the original exception. This allows Sidekiq's built-in
  # {Sidekiq::JobRetry} middleware to handle the retry logic, including:
  # - Exponential backoff with jitter
  # - Retry count tracking and limits
  # - Error metadata (error_message, error_class, failed_at, retried_at)
  # - Death handlers and dead job queue when retries are exhausted
  # - Integration with sidekiq_retries_exhausted callbacks
  class ContinuationMiddleware
    include Sidekiq::ServerMiddleware

    def call(worker, job, queue)
      continuation_type = job.dig("async_http_continuation")
      if continuation_type
        if continuation_type == "completion"
          Sidekiq::AsyncHttp.invoke_completion_callbacks(job["args"].first)
        elsif continuation_type == "error"
          Sidekiq::AsyncHttp.invoke_error_callbacks(job["args"].first)
        elsif continuation_type == "retry"
          # Re-raise the exception to trigger Sidekiq's standard retry mechanism
          error_data = job["async_http_error"] || {}

          # Clean up the continuation markers so the job runs normally after retry
          job.delete("async_http_continuation")
          job.delete("async_http_error")

          raise Error.load(error_data)
        end
      end

      yield
    end
  end
end
