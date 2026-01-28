# frozen_string_literal: true

# Serves the Faraday adapter test page.
class FaradayAction
  def call(_env)
    [
      200,
      {"Content-Type" => "text/html; charset=utf-8"},
      [File.read(File.join(__dir__, "../views/faraday.html"))]
    ]
  end
end
