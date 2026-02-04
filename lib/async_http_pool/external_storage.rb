# frozen_string_literal: true

module AsyncHttpPool
  # Handles external storage of large payloads.
  #
  # This class provides class methods for storing, fetching, and deleting
  # payloads from external storage. It is decoupled from the models
  # being stored (Request, Response, Error).
  #
  # All methods accept an explicit config parameter so this class has no
  # dependency on any module-level singleton state.
  #
  # @example Storing a large payload
  #   data = response.as_json
  #   stored_data = ExternalStorage.store(data, config)
  #
  # @example Fetching and deleting
  #   if ExternalStorage.storage_ref?(data)
  #     original_data = ExternalStorage.fetch(data, config)
  #     response = Response.load(original_data)
  #     ExternalStorage.delete(data, config)
  #   end
  class ExternalStorage
    # Key used in serialized JSON to indicate an external storage reference
    REFERENCE_KEY = "$ref"

    class << self
      # Store a hash externally if it exceeds the configured threshold.
      #
      # If no payload store is configured, or if the hash is below the
      # threshold, the original hash is returned unchanged.
      #
      # @param data [Hash] Hash to potentially store
      # @param config [Configuration] the pool configuration
      # @return [Hash] Reference hash if stored, original hash if not
      def store(data, config)
        store = config.payload_store
        return data unless store

        json_size = data.to_json.bytesize
        return data if json_size < config.payload_store_threshold

        key = store.generate_key
        store.store(key, data)

        {
          REFERENCE_KEY => {
            "store" => config.default_payload_store_name.to_s,
            "key" => key
          }
        }
      end

      # Check if a hash is a storage reference.
      #
      # @param data [Hash, Object] Data to check
      # @return [Boolean] true if this is a reference to external storage
      def storage_ref?(data)
        data.is_a?(Hash) && data.key?(REFERENCE_KEY)
      end

      # Fetch a hash from external storage.
      #
      # @param data [Hash] Reference hash containing storage location
      # @param config [Configuration] the pool configuration
      # @return [Hash] Original hash from storage
      # @raise [RuntimeError] If the store is not registered
      # @raise [RuntimeError] If the stored payload is not found
      def fetch(data, config)
        ref = data[REFERENCE_KEY]
        store_name = ref["store"].to_sym
        key = ref["key"]

        store = config.payload_store(store_name)
        raise "Payload store '#{store_name}' not registered" unless store

        stored_data = store.fetch(key)
        raise "Stored payload not found: #{store_name}/#{key}" unless stored_data

        stored_data
      end

      # Delete payload from external storage.
      #
      # This method is idempotent - it's safe to call on non-reference hashes,
      # already-deleted payloads, or nil values.
      #
      # @param data [Hash, nil] Reference hash (or regular hash, which is ignored)
      # @param config [Configuration] the pool configuration
      # @return [void]
      def delete(data, config)
        return unless data && storage_ref?(data)

        ref = data[REFERENCE_KEY]
        store_name = ref["store"].to_sym
        key = ref["key"]

        store = config.payload_store(store_name)
        store&.delete(key)
      end
    end
  end
end
