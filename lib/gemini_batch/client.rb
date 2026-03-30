# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'

module GeminiBatch
  class Client
    API_BASE = 'https://generativelanguage.googleapis.com'

    attr_reader :api_key, :model, :config

    def initialize(api_key: nil, model: nil, **overrides)
      @config = Configuration.new
      @config.api_key = api_key || @config.api_key
      @config.model = model || @config.model
      overrides.each { |k, v| @config.send(:"#{k}=", v) if @config.respond_to?(:"#{k}=") }

      raise Error, 'GEMINI_API_KEY is required' unless @config.api_key

      @api_key = @config.api_key
      @model = @config.model
    end

    # Egyetlen prompt feldolgozása (sync)
    def generate(prompt, system_prompt: nil, **generation_config)
      body = build_generate_body(prompt, system_prompt: system_prompt, **generation_config)
      url = "#{API_BASE}/v1beta/models/#{@model}:generateContent?key=#{@api_key}"

      response = http_post(url, body)
      parse_generate_response(response)
    end

    # Több item feldolgozása egyenként (sync mód)
    def process_sync(items, sleep_between: 0.5, system_prompt: nil, **generation_config, &block)
      results = {}
      items.each_with_index do |item, idx|
        prompt = block.call(item)
        key = item[:id] || item['id'] || idx
        results[key] = generate(prompt, system_prompt: system_prompt, **generation_config)
        sleep(sleep_between) if idx < items.size - 1
      rescue ApiError => e
        results[key] = { error: e.message, parsed: nil, raw_text: nil, tokens_used: 0 }
      end
      results
    end

    private

    def build_generate_body(prompt, system_prompt: nil, **overrides)
      body = {
        contents: [{ parts: [{ text: prompt }] }],
        generationConfig: {
          temperature: overrides[:temperature] || @config.temperature,
          maxOutputTokens: overrides[:max_output_tokens] || @config.max_output_tokens,
          responseMimeType: overrides[:response_mime_type] || @config.response_mime_type
        }
      }

      if system_prompt
        body[:system_instruction] = { parts: [{ text: system_prompt }] }
      end

      body
    end

    def http_post(url, body)
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 120
      http.open_timeout = 30

      request = Net::HTTP::Post.new(uri)
      request['Content-Type'] = 'application/json'
      request.body = JSON.generate(body)

      response = http.request(request)

      unless response.is_a?(Net::HTTPSuccess)
        error_msg = begin
          JSON.parse(response.body).dig('error', 'message')
        rescue
          response.body
        end
        raise ApiError, "Gemini API error (#{response.code}): #{error_msg}"
      end

      JSON.parse(response.body)
    end

    def parse_generate_response(response)
      text = response.dig('candidates', 0, 'content', 'parts', 0, 'text') || ''
      tokens = response.dig('usageMetadata', 'totalTokenCount') || 0

      # Strip markdown code block if present
      clean_text = text.gsub(/\A```json\s*\n?/, '').gsub(/\n?```\s*\z/, '').strip

      parsed = begin
        JSON.parse(clean_text)
      rescue JSON::ParserError
        nil
      end

      { parsed: parsed, raw_text: text, tokens_used: tokens }
    end
  end
end
