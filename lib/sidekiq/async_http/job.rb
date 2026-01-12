# frozen_string_literal: true

module Sidekiq::AsyncHttp
  module Job
    def self.included(base)
      base.include(Sidekiq::Job) unless base.include?(Sidekiq::Job)
      base.extend(ClassMethods)
    end

    module ClassMethods
      def client(**options)
        @client = Sidekiq::AsyncHttp::Client.new(**options)
      end

      def success_callback(&block)
        success_callback_block = block

        worker_class = Class.new do
          include Sidekiq::Job

          define_method(:perform) do |response_data, *args|
            response = Sidekiq::AsyncHttp::Response.from_h(response_data)
            success_callback_block.call(response, *args)
          end
        end

        const_set(:SuccessCallback, worker_class)
      end

      def error_callback(&block)
        error_callback_block = block

        worker_class = Class.new do
          include Sidekiq::Job

          define_method(:perform) do |error_data, *args|
            error = Sidekiq::AsyncHttp::Error.from_h(error_data)
            error_callback_block.call(error, *args)
          end
        end

        const_set(:ErrorCallback, worker_class)
      end
    end

    def client
      self.class.instance_variable_get(:@client) || Sidekiq::AsyncHttp::Client.new
    end

    def async_request(method, url, **options)
      options = options.dup
      success_worker ||= options.delete(:success_worker)
      error_worker ||= options.delete(:error_worker)

      success_worker ||= self.class.const_get(:SuccessCallback) if self.class.const_defined?(:SuccessCallback)
      error_worker ||= self.class.const_get(:ErrorCallback) if self.class.const_defined?(:ErrorCallback)

      request_task = client.async_request(method, url, **options)
      request_task.perform(success_worker: success_worker, error_worker: error_worker)
    end

    def async_get(url, **options)
      async_request(:get, url, **options)
    end

    def async_post(url, **options)
      async_request(:post, url, **options)
    end

    def async_put(url, **options)
      async_request(:put, url, **options)
    end

    def async_patch(url, **options)
      async_request(:patch, url, **options)
    end

    def async_delete(url, **options)
      async_request(:delete, url, **options)
    end
  end
end
