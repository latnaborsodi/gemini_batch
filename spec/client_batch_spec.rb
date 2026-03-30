# frozen_string_literal: true

require 'minitest/autorun'
require 'webmock/minitest'
require_relative '../lib/gemini_batch'

class ClientBatchTest < Minitest::Test
  def setup
    @client = GeminiBatch::Client.new(api_key: 'test-key', model: 'gemini-2.5-flash')
  end

  def test_build_request_returns_request_builder
    builder = @client.build_request
    assert_instance_of GeminiBatch::RequestBuilder, builder
  end

  def test_build_request_with_system_prompt
    builder = @client.build_request(system_prompt: 'Extract tech info')
    assert_equal 'Extract tech info', builder.system_prompt
  end

  def test_upload_creates_file
    stub_request(:post, "https://generativelanguage.googleapis.com/upload/v1beta/files?key=test-key")
      .to_return(
        status: 200,
        headers: { 'X-Goog-Upload-URL' => 'https://generativelanguage.googleapis.com/upload/resume/123' }
      )

    stub_request(:put, "https://generativelanguage.googleapis.com/upload/resume/123")
      .to_return(
        status: 200,
        body: JSON.generate({ file: { name: 'files/abc123', uri: 'https://generativelanguage.googleapis.com/v1beta/files/abc123' } })
      )

    result = @client.send(:upload_file, "test jsonl content\n")
    assert_equal 'files/abc123', result[:name]
  end
end
