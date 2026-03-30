# frozen_string_literal: true

require_relative 'gemini_batch/configuration'
require_relative 'gemini_batch/request_builder'
require_relative 'gemini_batch/client'

module GeminiBatch
  class Error < StandardError; end
  class ApiError < Error; end
  class TimeoutError < Error; end

  def self.configuration
    @configuration ||= Configuration.new
  end

  def self.configure
    yield(configuration)
  end
end
