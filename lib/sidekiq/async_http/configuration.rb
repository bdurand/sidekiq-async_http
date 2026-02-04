# frozen_string_literal: true

module Sidekiq
  module AsyncHttp
    # Configuration for the Sidekiq Async HTTP gem.
    #
    # Wraps AsyncHttpPool::Configuration with Sidekiq-aware defaults and adds
    # Sidekiq-specific options like worker queue/retry settings.
    #
    # Access the underlying pool configuration via the +http_pool+ attribute.
    class Configuration
      # @return [AsyncHttpPool::Configuration] the HTTP pool configuration
      attr_reader :http_pool

      # @return [Hash, nil] Sidekiq options to apply to RequestWorker and CallbackWorker
      attr_reader :sidekiq_options

      # Delegate pool attribute getters and setters to http_pool
      DELEGATED_ATTRS = %i[
        max_connections idle_connection_timeout request_timeout shutdown_timeout
        max_response_size heartbeat_interval orphan_threshold user_agent
        raise_error_responses max_redirects connection_pool_size connection_timeout
        proxy_url retries logger payload_store_threshold
      ].freeze

      DELEGATED_ATTRS.each do |attr|
        define_method(attr) { @http_pool.public_send(attr) }
        define_method(:"#{attr}=") { |value| @http_pool.public_send(:"#{attr}=", value) }
      end

      # @!method register_payload_store(name, adapter, **options)
      #   Register a payload store. Delegated to {http_pool}.
      # @!method payload_store(name = nil)
      #   Get a registered payload store. Delegated to {http_pool}.
      # @!method default_payload_store_name
      #   Get the default payload store name. Delegated to {http_pool}.
      # @!method payload_stores
      #   Get all registered payload stores. Delegated to {http_pool}.
      %i[register_payload_store payload_store default_payload_store_name payload_stores].each do |method|
        define_method(method) { |*args, **kwargs, &block| @http_pool.public_send(method, *args, **kwargs, &block) }
      end

      # Initializes a new Configuration with the specified options.
      #
      # @param sidekiq_options [Hash, nil] Sidekiq options to apply to RequestWorker and CallbackWorker
      # @param pool_options [Hash] Options passed through to AsyncHttpPool::Configuration.
      #   Sidekiq-aware defaults are applied for shutdown_timeout, user_agent, and logger
      #   if not explicitly provided.
      def initialize(sidekiq_options: nil, **pool_options)
        pool_options[:shutdown_timeout] ||= (Sidekiq.default_configuration[:timeout] || 25) - 2
        pool_options[:user_agent] ||= "Sidekiq-AsyncHttp"
        pool_options[:logger] ||= Sidekiq.logger

        @http_pool = AsyncHttpPool::Configuration.new(**pool_options)
        self.sidekiq_options = sidekiq_options
      end

      # Set Sidekiq worker options and apply them to RequestWorker and CallbackWorker.
      #
      # @param options [Hash, nil] Sidekiq options hash
      # @return [void]
      def sidekiq_options=(options)
        if options.nil?
          @sidekiq_options = nil
          return
        end

        unless options.is_a?(Hash)
          raise ArgumentError.new("sidekiq_options must be a Hash, got: #{options.class}")
        end

        @sidekiq_options = options
        apply_sidekiq_options(options)
      end

      # Convert to hash for inspection
      # @return [Hash] hash representation with string keys
      def to_h
        @http_pool.to_h.merge(
          "sidekiq_options" => sidekiq_options
        )
      end

      private

      def apply_sidekiq_options(options)
        Sidekiq::AsyncHttp::RequestWorker.sidekiq_options(options)
        Sidekiq::AsyncHttp::CallbackWorker.sidekiq_options(options)
      end
    end
  end
end
