# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/gemini_batch'

class RequestBuilderTest < Minitest::Test
  def setup
    @builder = GeminiBatch::RequestBuilder.new(model: 'gemini-2.5-flash')
  end

  def test_add_items_and_generate_jsonl
    @builder.add(key: 'product-1', prompt: 'Extract from: Kazán 25 kW')
    @builder.add(key: 'product-2', prompt: 'Extract from: Szivattyú 3 bar')

    jsonl = @builder.to_jsonl
    lines = jsonl.strip.split("\n")
    assert_equal 2, lines.size

    first = JSON.parse(lines[0])
    assert_equal 'product-1', first['key']
    assert_equal 'Extract from: Kazán 25 kW', first.dig('request', 'contents', 0, 'parts', 0, 'text')
  end

  def test_add_with_system_prompt
    @builder.system_prompt = 'You are a tech extractor'
    @builder.add(key: 'p1', prompt: 'Test')

    jsonl = @builder.to_jsonl
    line = JSON.parse(jsonl.strip)
    assert_equal 'You are a tech extractor', line.dig('request', 'system_instruction', 'parts', 0, 'text')
  end

  def test_generation_config_included
    @builder.add(key: 'p1', prompt: 'Test')

    jsonl = @builder.to_jsonl
    line = JSON.parse(jsonl.strip)
    config = line.dig('request', 'generationConfig')
    assert config
    assert_equal 'application/json', config['responseMimeType']
  end

  def test_empty_builder_raises
    assert_raises(GeminiBatch::Error) { @builder.to_jsonl }
  end

  def test_count
    @builder.add(key: 'a', prompt: 'A')
    @builder.add(key: 'b', prompt: 'B')
    assert_equal 2, @builder.count
  end
end
