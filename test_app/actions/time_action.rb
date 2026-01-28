# frozen_string_literal: true

# Returns the current time as JSON.
#
# This endpoint is used by the Faraday adapter test to have a simple
# target URL that returns a predictable response.
class TimeAction
  def call(_env)
    [
      200,
      {"Content-Type" => "application/json; charset=utf-8"},
      [JSON.generate({time: Time.now.iso8601})]
    ]
  end
end
