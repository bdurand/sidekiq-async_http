# frozen_string_literal: true

require "spec_helper"

RSpec.describe SidekiqAsyncHttpRequests do
  describe "VERSION" do
    it "has a version number" do
      expect(SidekiqAsyncHttpRequests::VERSION).to eq(File.read(File.join(__dir__, "../VERSION")).strip)
    end
  end
end
