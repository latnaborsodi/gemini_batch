# frozen_string_literal: true

module GeminiBatch
  class Configuration
    attr_accessor :api_key, :model, :temperature, :max_output_tokens,
                  :response_mime_type, :poll_interval, :max_polls

    def initialize
      @api_key = ENV['GEMINI_API_KEY']
      @model = 'gemini-2.5-flash'
      @temperature = 0.1
      @max_output_tokens = 8192
      @response_mime_type = 'application/json'
      @poll_interval = 30
      @max_polls = 720  # 6 óra @ 30 sec
    end
  end
end
