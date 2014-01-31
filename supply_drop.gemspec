require 'rake'

Gem::Specification.new do |s|
  s.name = "supply_drop"
  s.summary = "Masterless puppet with capistrano"
  s.description = "See http://github.com/pitluga/supply_drop"
  s.version = "0.18.0"
  s.authors = ["Tony Pitluga", "Paul Hinze", "Troy Howard"]
  s.email = ["tony.pitluga@gmail.com", "paul.t.hinze@gmail.com", "thoward37@gmail.com"]
  s.homepage = "http://github.com/pitluga/supply_drop"
  s.license = "MIT"
  s.files = FileList["README.md", "Rakefile", "lib/**/*.rb"]
  s.add_dependency('capistrano', '>= 3.0.1')
end
