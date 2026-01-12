# frozen_string_literal: true

module Sidekiq::AsyncHttp
  module ClassHelper
    extend self

    # Resolve a class from its name class name to the class object.
    #
    # @param class_name [String] the fully qualified class name
    # @return [Class] the class object
    # @raise [NameError] if class cannot be found
    def resolve_class_name(class_name)
      return class_name if class_name.is_a?(Class)

      class_name.split("::").reduce(Object) { |mod, name| mod.const_get(name) }
    end
  end
end
