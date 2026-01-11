module TestWorkers
  class Worker
    include Sidekiq::Job

    def perform(*args)
    end
  end

  class SuccessWorker
    include Sidekiq::Job

    def perform(response, *args)
    end
  end

  class ErrorWorker
    include Sidekiq::Job

    def perform(error, *args)
    end
  end
end
