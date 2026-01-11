# frozen_string_literal: true

module Sidekiq
  module AsyncHttp
    # Immutable error object representing an exception from an HTTP request
    class Error
      # Valid error types
      ERROR_TYPES = %i[timeout connection ssl protocol unknown].freeze

      attr_reader :class_name, :message, :backtrace, :request_id, :error_type

      def initialize(class_name:, message:, backtrace:, request_id:, error_type:)
        @class_name = class_name
        @message = message
        @backtrace = backtrace
        @request_id = request_id
        @error_type = error_type
        freeze
      end

      # Create a new Error with modified attributes (similar to Data#with)
      # @param attributes [Hash] attributes to change
      # @return [Error] new error object with modified attributes
      def with(**attributes)
        self.class.new(
          class_name: attributes.fetch(:class_name, class_name),
          message: attributes.fetch(:message, message),
          backtrace: attributes.fetch(:backtrace, backtrace),
          request_id: attributes.fetch(:request_id, request_id),
          error_type: attributes.fetch(:error_type, error_type)
        )
      end

      # Create an Error from an exception using pattern matching
      #
      # @param exception [Exception] the exception to convert
      # @param request_id [String] the request ID
      # @return [Error] the error object
      def self.from_exception(exception, request_id:)
        error_type = case exception
        in Async::TimeoutError
          :timeout
        in OpenSSL::SSL::SSLError
          :ssl
        in Errno::ECONNREFUSED | Errno::ECONNRESET | Errno::EHOSTUNREACH
          :connection
        else
          # Check for protocol errors without requiring the constant
          if exception.class.name&.include?("Protocol::Error")
            :protocol
          else
            :unknown
          end
        end

        new(
          class_name: exception.class.name,
          message: exception.message,
          backtrace: exception.backtrace || [],
          request_id: request_id,
          error_type: error_type
        )
      end

      # Convert to hash with string keys for serialization
      # @return [Hash] hash representation
      def to_h
        {
          "class_name" => class_name,
          "message" => message,
          "backtrace" => backtrace,
          "request_id" => request_id,
          "error_type" => error_type.to_s
        }
      end

      # Reconstruct an Error from a hash
      # @param hash [Hash] hash representation
      # @return [Error] reconstructed error
      def self.from_h(hash)
        new(
          class_name: hash["class_name"],
          message: hash["message"],
          backtrace: hash["backtrace"],
          request_id: hash["request_id"],
          error_type: hash["error_type"].to_sym
        )
      end

      # Get the actual Exception class constant from the class_name
      # @return [Class, nil] the exception class or nil if not found
      def error_class
        ClassHelper.resolve_class_name(class_name)
      end
    end
  end
end
