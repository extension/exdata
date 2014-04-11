# -*- encoding: utf-8 -*-
require File.expand_path('../lib/getdata/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["Jason Adam Young"]
  gem.email         = ["jayoung@extension.org"]
  gem.description = <<-EOF
    exdata isa gem utility to facilitate the retrieval of data snaphosts of 
    eXtension production data for use in development
  EOF
  gem.summary       = %q{Post logs from a capistrano deploy to the deployment server, as well as a custom deploy-tracking application.}
  gem.homepage      = %q{https://github.com/extension/exdata}
  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.name          = "exdata"
  gem.require_paths = ["lib"]
  gem.version       = GetData::VERSION
  gem.add_dependency('highline', '>= 1.6.20')
  gem.add_dependency('net-ssh', '>= 2.8.0')
  gem.add_dependency('net-scp', '>= 1.1.2')
  gem.add_dependency('rest-client', '>= 1.6.7')
  gem.add_dependency('toml', '~> 0.0.3')
  gem.add_dependency('mysql2', '~> 0.2')
  gem.add_dependency('thor', '>= 0.16.0')
end
