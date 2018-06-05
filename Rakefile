require "bundler/gem_tasks"
require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList['test/**/*_test.rb']
end

task :default => :test

task :compile do
  files = FileList['lib/**/*.rb'].reverse
  cmd = FileList['bin/bash_strict.rb']
  all = files + cmd
  to_reject = [
    %Q(require "bash_strict/version"),
    %Q(require "bash_strict"),
  ]

  lines = all.map do |file|
    File.new(file).readlines.map(&:rstrip)
  end.flatten
     .reject { |l| to_reject.include?(l) }
     .insert(0, "#!/usr/bin/env ruby\n###-- GENERATED CODE -- DO NOT EDIT --###")

  File.write("build/bash_strict", lines.join("\n"))
end
