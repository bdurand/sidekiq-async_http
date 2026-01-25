# frozen_string_literal: true

# Serves the shared CSS stylesheet.
class StylesAction
  def call(_env)
    [
      200,
      {"Content-Type" => "text/css; charset=utf-8"},
      [File.read(File.join(__dir__, "../views/styles.css"))]
    ]
  end
end
