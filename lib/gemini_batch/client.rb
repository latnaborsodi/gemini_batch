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

    def build_request(system_prompt: nil, **generation_config)
      builder = RequestBuilder.new(
        model: @model,
        temperature: generation_config[:temperature] || @config.temperature,
        max_output_tokens: generation_config[:max_output_tokens] || @config.max_output_tokens,
        response_mime_type: generation_config[:response_mime_type] || @config.response_mime_type
      )
      builder.system_prompt = system_prompt
      builder
    end

    def submit_batch(builder)
      jsonl = builder.to_jsonl
      file_info = upload_file(jsonl)
      batch_info = create_batch(file_info[:uri])
      {
        batch_name: batch_info['name'],
        file_name: file_info[:name],
        count: builder.count
      }
    end

    def check_batch_status(batch_name)
      url = "#{API_BASE}/v1beta/#{batch_name}?key=#{@api_key}"
      response = http_get(url)

      state = response['state'] || response.dig('metadata', 'state') || ''
      case state.to_s.upcase
      when 'JOB_STATE_SUCCEEDED', 'SUCCEEDED' then :succeeded
      when 'JOB_STATE_FAILED', 'FAILED' then :failed
      else :processing
      end
    end

    def retrieve_batch_results(batch_name)
      url = "#{API_BASE}/v1beta/#{batch_name}?key=#{@api_key}"
      batch_response = http_get(url)

      output_file = extract_output_file(batch_response)
      raise Error, "No output file found in batch response" unless output_file

      file_content = download_file(output_file)
      parse_batch_results(file_content)
    end

    def wait_until_done(batch_name, poll_interval: nil, max_polls: nil)
      interval = poll_interval || @config.poll_interval
      max = max_polls || @config.max_polls

      max.times do
        status = check_batch_status(batch_name)
        return status if status != :processing
        sleep(interval)
      end

      raise TimeoutError, "Batch #{batch_name} did not complete within #{max * interval} seconds"
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
      http.open_timeout = 60

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

    def upload_file(jsonl_content)
      init_url = "#{API_BASE}/upload/v1beta/files?key=#{@api_key}"
      uri = URI(init_url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      init_request = Net::HTTP::Post.new(uri)
      init_request['X-Goog-Upload-Protocol'] = 'resumable'
      init_request['X-Goog-Upload-Command'] = 'start'
      init_request['X-Goog-Upload-Header-Content-Length'] = jsonl_content.bytesize.to_s
      init_request['X-Goog-Upload-Header-Content-Type'] = 'application/jsonl'
      init_request['Content-Type'] = 'application/json'
      init_request.body = JSON.generate({ file: { displayName: "batch_#{Time.now.strftime('%Y%m%d_%H%M%S')}.jsonl" } })

      init_response = http.request(init_request)
      upload_url = init_response['X-Goog-Upload-URL']
      raise ApiError, "Failed to initiate upload: #{init_response.body}" unless upload_url

      upload_uri = URI(upload_url)
      upload_http = Net::HTTP.new(upload_uri.host, upload_uri.port)
      upload_http.use_ssl = true

      upload_request = Net::HTTP::Put.new(upload_uri)
      upload_request['X-Goog-Upload-Command'] = 'upload, finalize'
      upload_request['X-Goog-Upload-Offset'] = '0'
      upload_request['Content-Type'] = 'application/jsonl'
      upload_request.body = jsonl_content

      upload_response = upload_http.request(upload_request)
      result = JSON.parse(upload_response.body)
      file = result['file'] || result

      { name: file['name'], uri: file['uri'] }
    end

    def create_batch(file_uri)
      url = "#{API_BASE}/v1beta/models/#{@model}:batchGenerateContent?key=#{@api_key}"
      body = { requests_file_uri: file_uri }
      http_post(url, body)
    end

    def http_get(url)
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 60

      request = Net::HTTP::Get.new(uri)
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

    def download_file(file_path)
      url = "#{API_BASE}/v1beta/#{file_path}?key=#{@api_key}&alt=media"
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 300

      request = Net::HTTP::Get.new(uri)
      response = http.request(request)

      raise ApiError, "Failed to download file: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      response.body
    end

    def extract_output_file(batch_response)
      batch_response['outputFile'] ||
        batch_response.dig('metadata', 'outputFile') ||
        batch_response.dig('response', 'outputFile')
    end

    def parse_batch_results(jsonl_content)
      results = {}
      jsonl_content.each_line do |line|
        next if line.strip.empty?

        entry = JSON.parse(line)
        key = entry['key']
        response_body = entry.dig('response', 'candidates', 0, 'content', 'parts', 0, 'text') || ''
        tokens = entry.dig('response', 'usageMetadata', 'totalTokenCount') || 0

        clean_text = response_body.gsub(/\A```json\s*\n?/, '').gsub(/\n?```\s*\z/, '').strip
        parsed = begin
          JSON.parse(clean_text)
        rescue JSON::ParserError
          nil
        end

        results[key] = { parsed: parsed, raw_text: response_body, tokens_used: tokens }
      end
      results
    end
  end
end
