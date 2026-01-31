# frozen_string_literal: true

module Sidekiq::AsyncHttp
  # Mixin module for Sidekiq jobs that provides async HTTP functionality.
  #
  # Including this module in a Sidekiq job class adds methods for making asynchronous
  # HTTP requests that are processed outside the worker thread.
  #
  # @example Using inline callback
  #   class MyJob
  #     include Sidekiq::AsyncHttp::Job
  #
  #     callback do
  #       def on_complete(response)
  #         user_id = response.callback_args[:user_id]
  #         # Handle successful response
  #       end
  #
  #       def on_error(error)
  #         user_id = error.callback_args[:user_id]
  #         # Handle error
  #       end
  #     end
  #
  #     def perform(user_id)
  #       async_get("https://api.example.com/data", callback_args: {user_id: user_id})
  #     end
  #   end
  #
  # @example Using external callback service
  #   class MyCallbackService
  #     def on_complete(response)
  #       # Handle success
  #     end
  #
  #     def on_error(error)
  #       # Handle error
  #     end
  #   end
  #
  #   class MyJob
  #     include Sidekiq::AsyncHttp::Job
  #
  #     self.callback_service = MyCallbackService
  #
  #     def perform(user_id)
  #       async_get("https://api.example.com/data", callback_args: {user_id: user_id})
  #     end
  #   end
  #
  # This can also be included in ActiveJob classes if the queue adapter
  # is using Sidekiq.
  module Job
    class << self
      # Hook called when the module is included in a class.
      #
      # @param base [Class] the class including this module
      def included(base)
        if !(defined?(ActiveJob::Base) && base < ActiveJob::Base) && !base.include?(Sidekiq::Job)
          base.include(Sidekiq::Job)
        end

        base.extend(ClassMethods)
        base.async_http_client
      end
    end

    # Class methods added to the including job class.
    module ClassMethods
      # @return [Class] the callback service class
      attr_reader :callback_service_class

      # Configures the HTTP client for this job class.
      #
      # @param options [Hash] client configuration options
      # @option options [String] :base_url Base URL for relative requests
      # @option options [Hash] :headers Default headers
      # @option options [Float] :timeout Default timeout
      def async_http_client(**options)
        @async_http_client = Sidekiq::AsyncHttp::Client.new(**options)
      end

      # Defines an inline callback service for HTTP requests.
      #
      # The block should define `on_complete` and `on_error` methods that each
      # accept exactly one positional argument.
      #
      # @yield block defining the callback methods
      def callback(&block)
        callback_class = Class.new do
          class_eval(&block) if block_given?
        end

        validate_callback_class!(callback_class)

        const_set(:AsyncHttpCallback, callback_class)
        @callback_service_class = const_get(:AsyncHttpCallback)
      end

      # Sets the callback service class.
      #
      # @param service_class [Class] the callback service class
      # @raise [ArgumentError] if service_class does not have valid callback methods
      def callback_service=(service_class)
        validate_callback_class!(service_class)
        @callback_service_class = service_class
      end

      # Check if the class is an ActiveJob but not using Sidekiq as the queue adapter.
      #
      # @return [Boolean] true if Sidekiq is the queue adapter
      # @api private
      def asynchronous_http_requests_supported?
        if defined?(ActiveJob::Base) && self <= ActiveJob::Base
          queue_adapter_name == "sidekiq"
        else
          true
        end
      end

      private

      def validate_callback_class!(callback_class)
        validate_callback_method!(callback_class, :on_complete)
        validate_callback_method!(callback_class, :on_error)
      end

      def validate_callback_method!(callback_class, method_name)
        unless callback_class.method_defined?(method_name)
          raise ArgumentError.new("callback class must define ##{method_name} instance method")
        end

        method = callback_class.instance_method(method_name)
        # arity of 1 = exactly 1 required arg, -1 = any args (*args), -2 = 1 required + splat
        unless method.arity == 1 || method.arity == -1 || method.arity == -2
          raise ArgumentError.new("callback class ##{method_name} must accept exactly 1 positional argument")
        end
      end
    end

    # Makes an asynchronous HTTP request.
    #
    # @param method [Symbol] HTTP method (:get, :post, :put, :patch, :delete)
    # @param url [String] the request URL
    # @param options [Hash] additional request options
    # @option options [Class, String] :callback Callback service class to use (overrides class default)
    # @option options [#to_h] :callback_args Arguments to include in the Response/Error object.
    #   Must respond to to_h and contain only JSON-native types. Access via response.callback_args.
    # @option options [Boolean] :raise_error_responses If true, raises HttpError for non-2xx responses
    #   and calls on_error instead of on_complete. Defaults to false.
    #
    # @return [String] request ID
    def async_request(method, url, **options)
      options = options.dup
      callback = options.delete(:callback)
      callback_args = options.delete(:callback_args)
      raise_error_responses = options.delete(:raise_error_responses)
      raise_error_responses = Sidekiq::AsyncHttp.configuration.raise_error_responses if raise_error_responses.nil?

      callback ||= self.class.callback_service_class

      unless callback
        raise ArgumentError.new("No callback service configured. Use `callback do...end` or `self.callback_service=` or pass :callback option")
      end

      request = async_http_client.async_request(method, url, **options)
      request.execute(
        callback: callback,
        callback_args: callback_args,
        raise_error_responses: raise_error_responses
      )
    end

    # Convenience method for GET requests.
    #
    # @param url [String] the request URL
    # @param options [Hash] additional request options (see {#async_request})
    #
    # @return [String] request ID
    def async_get(url, **options)
      async_request(:get, url, **options)
    end

    # Convenience method for GET requests that raises HttpError for non-2xx responses.
    #
    # @param url [String] the request URL
    # @param options [Hash] additional request options (see {#async_request})
    #
    # @return [String] request ID
    def async_get!(url, **options)
      async_request(:get, url, **options.merge(raise_error_responses: true))
    end

    # Convenience method for POST requests.
    #
    # @param url [String] the request URL
    # @param options [Hash] additional request options (see {#async_request})
    #
    # @return [String] request ID
    def async_post(url, **options)
      async_request(:post, url, **options)
    end

    # Convenience method for POST requests that raises HttpError for non-2xx responses.
    #
    # @param url [String] the request URL
    # @param options [Hash] additional request options (see {#async_request})
    #
    # @return [String] request ID
    def async_post!(url, **options)
      async_request(:post, url, **options.merge(raise_error_responses: true))
    end

    # Convenience method for PUT requests.
    #
    # @param url [String] the request URL
    # @param options [Hash] additional request options (see {#async_request})
    #
    # @return [String] request ID
    def async_put(url, **options)
      async_request(:put, url, **options)
    end

    # Convenience method for PUT requests that raises HttpError for non-2xx responses.
    #
    # @param url [String] the request URL
    # @param options [Hash] additional request options (see {#async_request})
    #
    # @return [String] request ID
    def async_put!(url, **options)
      async_request(:put, url, **options.merge(raise_error_responses: true))
    end

    # Convenience method for PATCH requests.
    #
    # @param url [String] the request URL
    # @param options [Hash] additional request options (see {#async_request})
    #
    # @return [String] request ID
    def async_patch(url, **options)
      async_request(:patch, url, **options)
    end

    # Convenience method for PATCH requests that raises HttpError for non-2xx responses.
    #
    # @param url [String] the request URL
    # @param options [Hash] additional request options (see {#async_request})
    #
    # @return [String] request ID
    def async_patch!(url, **options)
      async_request(:patch, url, **options.merge(raise_error_responses: true))
    end

    # Convenience method for DELETE requests.
    #
    # @param url [String] the request URL
    # @param options [Hash] additional request options (see {#async_request})
    #
    # @return [String] request ID
    def async_delete(url, **options)
      async_request(:delete, url, **options)
    end

    # Convenience method for DELETE requests that raises HttpError for non-2xx responses.
    #
    # @param url [String] the request URL
    # @param options [Hash] additional request options (see {#async_request})
    #
    # @return [String] request ID
    def async_delete!(url, **options)
      async_request(:delete, url, **options.merge(raise_error_responses: true))
    end

    # Returns the HTTP client for this job instance.
    #
    # @return [Client] the configured client or a default client
    # @api private
    def async_http_client
      unless self.class.asynchronous_http_requests_supported?
        raise "Asynchronous HTTP requests are not supported with the #{self.class.queue_adapter_name} ActiveJob queue adapter"
      end

      self.class.instance_variable_get(:@async_http_client) || Sidekiq::AsyncHttp::Client.new
    end
  end
end
