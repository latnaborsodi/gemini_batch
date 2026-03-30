# frozen_string_literal: true

require 'minitest/autorun'
require 'webmock/minitest'
require_relative '../lib/gemini_batch'

class ClientSyncTest < Minitest::Test
  def setup
    @client = GeminiBatch::Client.new(
      api_key: 'test-key',
      model: 'gemini-2.5-flash'
    )
  end

  def test_process_single_returns_parsed_json
    stub_request(:post, "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=test-key")
      .to_return(
        status: 200,
        headers: { 'Content-Type' => 'application/json' },
        body: JSON.generate({
          candidates: [{
            content: {
              parts: [{ text: '{"triples":[{"property":"Teljesítmény","value":"25","measurement":"kW"}]}' }]
            }
          }],
          usageMetadata: { totalTokenCount: 150 }
        })
      )

    result = @client.generate('Extract tech info from: Kazán 25 kW teljesítmény')

    assert_equal 150, result[:tokens_used]
    parsed = result[:parsed]
    assert_equal 1, parsed['triples'].size
    assert_equal 'Teljesítmény', parsed['triples'][0]['property']
  end

  def test_process_single_handles_api_error
    stub_request(:post, "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=test-key")
      .to_return(status: 500, body: '{"error":{"message":"Internal error"}}')

    assert_raises(GeminiBatch::ApiError) do
      @client.generate('test prompt')
    end
  end

  def test_process_sync_iterates_items
    stub_request(:post, "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=test-key")
      .to_return(
        status: 200,
        headers: { 'Content-Type' => 'application/json' },
        body: JSON.generate({
          candidates: [{ content: { parts: [{ text: '{"result":"ok"}' }] } }],
          usageMetadata: { totalTokenCount: 100 }
        })
      )

    items = [{ id: 1, text: 'A' }, { id: 2, text: 'B' }]
    results = @client.process_sync(items) { |item| "Process: #{item[:text]}" }

    assert_equal 2, results.size
    assert_equal 'ok', results[1][:parsed]['result']
    assert_equal 'ok', results[2][:parsed]['result']
  end
end
