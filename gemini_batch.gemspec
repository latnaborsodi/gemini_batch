Gem::Specification.new do |spec|
  spec.name          = 'gemini_batch'
  spec.version       = '0.1.0'
  spec.authors       = ['Tebez']
  spec.summary       = 'Google Gemini API batch client'
  spec.description   = 'Ruby client for Google Gemini API with sync and batch (JSONL) processing modes.'
  spec.license       = 'MIT'
  spec.required_ruby_version = '>= 3.0'

  spec.files         = Dir['lib/**/*.rb']
  spec.require_paths = ['lib']

  spec.add_dependency 'json'
  spec.add_development_dependency 'minitest', '~> 5.0'
  spec.add_development_dependency 'webmock', '~> 3.0'
end
