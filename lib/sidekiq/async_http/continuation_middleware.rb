# frozen_string_literal: true

module Sidekiq::AsyncHttp
  # Middleware to handle continuation jobs for async HTTP requests.
  #
  # This middleware processes Sidekiq jobs that are continuations of async HTTP requests,
  # invoking the appropriate callbacks based on whether the request completed successfully
  # or resulted in an error.
  class ContinuationMiddleware
    include Sidekiq::ServerMiddleware

    def call(worker, job, queue)
      deserialize_response_arg(job)

      continuation_type = job.dig("async_http_continuation")
      if continuation_type
        if continuation_type == "completion" && job["args"].first.is_a?(Response)
          Sidekiq::AsyncHttp.invoke_completion_callbacks(job["args"].first)
        elsif continuation_type == "error" && job["args"].first.is_a?(Error)
          Sidekiq::AsyncHttp.invoke_error_callbacks(job["args"].first)
        end
      end

      yield
    end

    private

    def deserialize_response_arg(job)
      first_arg = job["args"].first
      first_arg_class_name = first_arg["_sidekiq_async_http_class"] if first_arg.is_a?(Hash)
      if first_arg_class_name == "Sidekiq::AsyncHttp::Response"
        job["args"][0] = Sidekiq::AsyncHttp::Response.load(first_arg)
      elsif first_arg_class_name == "Sidekiq::AsyncHttp::Error"
        job["args"][0] = Sidekiq::AsyncHttp::Error.load(first_arg)
      end
    end
  end
end
