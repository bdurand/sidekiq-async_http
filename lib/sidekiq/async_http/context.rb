# frozen_string_literal: true

module Sidekiq::AsyncHttp
  class Context
    class Middleware
      include Sidekiq::ServerMiddleware

      def call(worker, job, queue)
        Sidekiq::AsyncHttp::Context.with_job(job) do
          yield
        end
      end
    end

    class << self
      def current_job
        job = Thread.current[:sidekiq_async_http_current_job]
        deep_copy(job) if job
      end

      def with_job(job)
        previous_job = Thread.current[:sidekiq_async_http_current_job]
        Thread.current[:sidekiq_async_http_current_job] = job
        yield
      ensure
        Thread.current[:sidekiq_async_http_current_job] = previous_job
      end

      private

      def deep_copy(obj)
        Marshal.load(Marshal.dump(obj))
      end
    end
  end
end
