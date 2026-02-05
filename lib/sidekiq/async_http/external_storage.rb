# frozen_string_literal: true

module Sidekiq
  module AsyncHttp
    # Sidekiq wrapper around AsyncHttpPool::ExternalStorage.
    #
    # Binds external storage operations to the module-level Sidekiq configuration
    # so callers don't need to pass config explicitly.
    class ExternalStorage
      class << self
        # Store a hash externally if it exceeds the configured threshold.
        #
        # @param data [Hash] Hash to potentially store
        # @return [Hash] Reference hash if stored, original hash if not
        def store(data)
          AsyncHttpPool::ExternalStorage.store(data, Sidekiq::AsyncHttp.configuration)
        end

        # Check if a hash is a storage reference.
        #
        # @param data [Hash, Object] Data to check
        # @return [Boolean] true if this is a reference to external storage
        def storage_ref?(data)
          AsyncHttpPool::ExternalStorage.storage_ref?(data)
        end

        # Fetch a hash from external storage.
        #
        # @param data [Hash] Reference hash containing storage location
        # @return [Hash] Original hash from storage
        def fetch(data)
          AsyncHttpPool::ExternalStorage.fetch(data, Sidekiq::AsyncHttp.configuration)
        end

        # Delete payload from external storage.
        #
        # @param data [Hash, nil] Reference hash (or regular hash, which is ignored)
        # @return [void]
        def delete(data)
          AsyncHttpPool::ExternalStorage.delete(data, Sidekiq::AsyncHttp.configuration)
        end
      end
    end
  end
end
