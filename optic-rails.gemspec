# frozen_string_literal: true

$:.push File.expand_path("lib", __dir__)

# Maintain your gem's version:
require "optic/rails/version"

# Describe your gem and declare its dependencies:
Gem::Specification.new do |s|
  s.name        = "optic-rails"
  s.version     = Optic::Rails::VERSION
  s.authors     = ["Anton Vaynshtok"]
  s.email       = ["avaynshtok@gmail.com"]
  s.homepage    = "https://www.sutrolabs.com/"
  s.summary     = "optic.watch for Rails"
  s.description = "optic.watch is the easiest way to get notified when business metrics change. This gem intelligently collects metrics from your production database using ActiveRecord to automatically understand your data."
  s.license     = "MIT"

  s.files = Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]

  s.add_runtime_dependency "action_cable_client", "~> 2.0", ">= 2.0.2"
  s.add_runtime_dependency "eventmachine", "~> 1.0"
  s.add_runtime_dependency "rails", "~> 5.0"
end
