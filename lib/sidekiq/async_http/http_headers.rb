# frozen_string_literal: true

module Sidekiq::AsyncHttp
  # Case insensitive HTTP headers.
  class HttpHeaders
    def initialize(headers = {})
      @headers = {}
      headers.each do |key, value|
        @headers[key.to_s.downcase] = value
      end
    end

    def [](key)
      @headers[key.to_s.downcase]
    end

    def []=(key, value)
      @headers[key.to_s.downcase] = value
    end

    def merge(other_headers)
      new_headers = dup
      other_headers.each do |key, value|
        new_headers[key] = value
      end
      new_headers
    end

    def to_h
      @headers.dup
    end
  end
end
