# frozen_string_literal: true

module Sidekiq::AsyncHttp
  # Build an HTTP request for asynchronous execution.
  class Request
    attr_accessor :base_url, :headers, :timeout, :open_timeout, :read_timeout, :write_timeout

    def initialize(base_url: nil, headers: {}, timeout: 30, open_timeout: nil, read_timeout: nil, write_timeout: nil)
      @base_url = base_url
      @headers = HttpHeaders.new(headers)
      @timeout = timeout
      @open_timeout = open_timeout
      @read_timeout = read_timeout
      @write_timeout = write_timeout
    end

    def async_request(method, uri, body: nil, json: nil, headers: {}, params: {})
      full_uri = URI.join(@base_url, uri)
      if params.any?
        query_string = URI.encode_www_form(params)
        full_uri.query = [full_uri.query, query_string].compact.join("&")
      end
      full_uri.to_s

      merged_headers = headers.any? ? @headers.merge(headers) : @headers

      if json
        raise ArgumentError, "Cannot provide both body and json" if body

        JSON.generate(json)
        merged_headers.merge({"Content-Type" => "application/json encoding=utf-8"})
      end

      AsyncRequest.new(self)
    end

    def async_get(uri, **kwargs)
      async_request(:get, uri, **kwargs)
    end

    def async_post(uri, **kwargs)
      async_request(:post, uri, **kwargs)
    end

    def async_put(uri, **kwargs)
      async_request(:put, uri, **kwargs)
    end

    def async_patch(uri, **kwargs)
      async_request(:patch, uri, **kwargs)
    end

    def async_delete(uri, **kwargs)
      async_request(:delete, uri, **kwargs)
    end
  end
end
