# frozen_string_literal: true

module AsyncHttpPool
  # Interface for observing request processing. A process observer can be registered with
  # a Processor and receive events as requests are processed. Observers will run on the main
  # processor thread and so should be lightweight and not do processing other than recording
  # metrics or similar.
  class ProcessorObserver
    def start
    end

    def stop
    end

    def capacity_exceeded
    end

    def request_start(request_task)
    end

    def request_end(request_task)
    end

    def request_error(error)
    end
  end
end
