# frozen_string_literal: true

module Sidekiq::AsyncHttp
  class AsyncRequest
    attr_reader :id, :request, :enqueued_at

    def initialize(request)
      @id = SecureRandom.uuid
      @request = request
      @job = nil
      @success_worker_class = nil
      @error_worker_class = nil
      @enqueued_at = nil
    end

    def perform(sidekiq_job:, success_worker:, error_worker: nil)
      @job = sidekiq_job
      @success_worker_class = success_worker
      @error_worker_class = error_worker
      @enqueued_at = Time.now.to_f
    end

    def job_worker_class
      @job["class"]
    end

    def job_args
      @job["args"]
    end

    def reenqueue_job
      Sidekiq::Client.push(@job)
    end

    def retry_job
      @job["retry_count"] = (@job["retry_count"] || 0) + 1
      Sidekiq::Client.push(@job)
    end

    def success(response)
    end

    def error(error)
    end
  end
end
