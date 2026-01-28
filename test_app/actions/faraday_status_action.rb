# frozen_string_literal: true

# Returns the last Faraday response stored in Redis.
#
# Used by the Faraday test page for polling to display the response.
class FaradayStatusAction
  def call(_env)
    response = FaradayRequestWorker.get_response

    [
      200,
      {"Content-Type" => "application/json; charset=utf-8"},
      [JSON.generate({response: response})]
    ]
  end
end
