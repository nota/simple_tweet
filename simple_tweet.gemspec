# frozen_string_literal: true

require_relative "lib/simple_tweet/version"

Gem::Specification.new do |spec|
  spec.name = "simple_tweet"
  spec.version = SimpleTweet::VERSION
  spec.authors = ["Kugayama Nana"]
  spec.email = ["nna@nna774.net"]

  spec.summary = "simple_tweet provides tweet, tweet_with_media"
  spec.description = ""
  spec.homepage = "https://github.com/nota/simple_tweet"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  # spec.metadata["changelog_uri"] = "TODO: Put your gem's CHANGELOG.md URL here."

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (f == __FILE__) || f.match(%r{\A(?:(?:bin|test|spec|features)/|\.(?:git|travis|circleci)|appveyor)})
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "multipart-post", ">= 2.2.3"
  spec.add_dependency "oauth", "~> 1.1.0"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
