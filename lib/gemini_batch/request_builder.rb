# frozen_string_literal: true

require 'json'

module GeminiBatch
  class RequestBuilder
    attr_accessor :system_prompt
    attr_reader :count

    def initialize(model:, temperature: 0.1, max_output_tokens: 8192, response_mime_type: 'application/json')
      @model = model
      @temperature = temperature
      @max_output_tokens = max_output_tokens
      @response_mime_type = response_mime_type
      @system_prompt = nil
      @items = []
      @count = 0
    end

    def add(key:, prompt:)
      @items << { key: key.to_s, prompt: prompt }
      @count += 1
    end

    def to_jsonl
      raise Error, 'No items added to builder' if @items.empty?
      @items.map { |item| JSON.generate(build_line(item)) }.join("\n") + "\n"
    end

    private

    def build_line(item)
      request = {
        contents: [{ parts: [{ text: item[:prompt] }] }],
        generationConfig: {
          temperature: @temperature,
          maxOutputTokens: @max_output_tokens,
          responseMimeType: @response_mime_type
        }
      }

      if @system_prompt
        request[:system_instruction] = { parts: [{ text: @system_prompt }] }
      end

      { key: item[:key], request: request }
    end
  end
end
