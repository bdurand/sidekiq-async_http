# frozen_string_literal: true

class AppConfig
  class << self
    def redis_url
      ENV.fetch("REDIS_URL", "redis://localhost:6379/1")
    end

    def max_connections
      ENV.fetch("MAX_CONNECTIONS", "500").to_i
    end

    def sidekiq_concurrency
      ENV.fetch("SIDEKIQ_CONCURRENCY", "26").to_i
    end

    def port
      ENV.fetch("PORT", "9292").to_i
    end
  end
end
