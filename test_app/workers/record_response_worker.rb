# frozen_string_literal: true

class RecordResponseWorker
  include Sidekiq::Job

  def perform(response_data, *args)
    payload = {
      response: response_data,
      args: args
    }
    Sidekiq.redis.setx("last_response", 60, JSON.pretty_generate(payload))
  end
end
