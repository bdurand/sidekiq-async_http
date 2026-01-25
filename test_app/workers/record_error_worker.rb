# frozen_string_literal: true

class RecordErrorWorker
  include Sidekiq::Job

  def perform(error_data, *args)
    payload = {
      error: error_data,
      args: args
    }
    Sidekiq.redis.setx("last_error", 60, JSON.pretty_generate(payload))
  end
end
