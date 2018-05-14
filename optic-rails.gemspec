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
  s.summary     = "Rails plugin for Optic."
  s.description = "Rails plugin for Optic."
  s.license     = "MIT"

  s.files = Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]

  s.add_dependency "rails", "~> 5.2.0.rc2"

  s.add_development_dependency "sqlite3"
end
