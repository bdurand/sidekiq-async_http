# frozen_string_literal: true

module Sidekiq
  module AsyncHttp
    # Sidekiq implementation of TaskHandler.
    #
    # Handles task lifecycle operations using Sidekiq for job management:
    # - Completion and error callbacks are triggered via CallbackWorker
    # - Large payloads are stored via ExternalStorage before enqueuing
    # - Job retry uses Sidekiq::Client.push
    class SidekiqTaskHandler < TaskHandler
      # @return [Hash] The Sidekiq job hash containing class, jid, args, etc.
      #   Exposed for TaskMonitor crash recovery serialization.
      attr_reader :sidekiq_job

      # @param sidekiq_job [Hash] The Sidekiq job hash with "class", "jid", "args", etc.
      def initialize(sidekiq_job)
        @sidekiq_job = sidekiq_job
      end

      # Trigger the completion callback with the response.
      #
      # Stores the response via ExternalStorage (for large payloads) and
      # enqueues a CallbackWorker to invoke the callback asynchronously.
      #
      # @param response [Response] the HTTP response object
      # @param callback [String] callback class name
      # @return [void]
      def on_complete(response, callback)
        data = ExternalStorage.store(response.as_json)
        CallbackWorker.perform_async(data, "response", callback)
      end

      # Trigger the error callback with the error.
      #
      # Stores the error via ExternalStorage (for large payloads) and
      # enqueues a CallbackWorker to invoke the callback asynchronously.
      #
      # @param error [Error] the error object
      # @param callback [String] callback class name
      # @return [void]
      def on_error(error, callback)
        data = ExternalStorage.store(error.as_json)
        CallbackWorker.perform_async(data, "error", callback)
      end

      # Re-enqueue the original Sidekiq job for retry.
      #
      # @return [String] the job ID
      def retry
        Sidekiq::Client.push(@sidekiq_job)
      end

      # Return the job ID from the Sidekiq job.
      #
      # @return [String] job ID
      def job_id
        @sidekiq_job["jid"]
      end

      # Return the worker class from the Sidekiq job.
      #
      # @return [Class] worker class
      def worker_class
        ClassHelper.resolve_class_name(@sidekiq_job["class"])
      end
    end
  end
end
