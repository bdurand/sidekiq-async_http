# frozen_string_literal: true

module Sidekiq::AsyncHttp
  # Sidekiq worker that invokes callback services for HTTP request results.
  #
  # This worker receives serialized Response or Error data and invokes the
  # appropriate callback service method (on_complete or on_error).
  class CallbackWorker
    include Sidekiq::Job

    # Perform the callback invocation.
    #
    # @param result_data [Hash] Serialized Response or Error data
    # @param result_type [String] "response" or "error" indicating the type of result
    # @param callback_service_name [String] Fully qualified callback service class name
    def perform(result_data, result_type, callback_service_name)
      # Deserialize based on explicit type
      result = if result_type == "response"
        Response.load(result_data)
      else
        Error.load(result_data)
      end

      # Invoke global callbacks first
      if result.is_a?(Response)
        Sidekiq::AsyncHttp.invoke_completion_callbacks(result)
      else
        Sidekiq::AsyncHttp.invoke_error_callbacks(result)
      end

      # Instantiate and invoke callback service
      callback_service_class = ClassHelper.resolve_class_name(callback_service_name)
      callback_service = callback_service_class.new

      if result.is_a?(Response)
        callback_service.on_complete(result)
      else
        callback_service.on_error(result)
      end
    end
  end
end
