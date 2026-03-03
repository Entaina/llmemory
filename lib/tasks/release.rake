# frozen_string_literal: true

namespace :release do
  desc "Bump version (patch|minor|major). Checks: branch=main, no uncommitted changes, tests pass. Then: Gemfile.lock, CHANGELOG, commit, push, tag"
  task :bump, [:bump_type] => [] do |_t, args|
    require_relative "../llmemory/version"

    # Pre-flight checks
    current_branch = `git rev-parse --abbrev-ref HEAD`.strip
    abort "Current branch must be main (got: #{current_branch})" unless current_branch == "main"

    # Allow only release-related files to be modified (we'll commit them)
    release_files = %w[lib/llmemory/version.rb Gemfile.lock CHANGELOG.txt]
    status_lines = `git status --porcelain`.strip.lines
    other_changes = status_lines.reject do |line|
      path = line.sub(/\A..\s+/, "").strip
      release_files.include?(path)
    end
    abort "Working tree has uncommitted changes outside release files. Commit or stash them first." unless other_changes.empty?

    puts "Running tests..."
    sh "bundle exec rspec"
    puts "Tests passed.\n\n"

    bump_type = (args[:bump_type] || "patch").to_s.downcase
    unless %w[patch minor major].include?(bump_type)
      abort "Bump type must be: patch, minor, or major"
    end

    seg = Gem::Version.new(Llmemory::VERSION).segments
    new_version = case bump_type
    when "patch" then Gem::Version.new("#{seg[0]}.#{seg[1] || 0}.#{(seg[2] || 0) + 1}")
    when "minor" then Gem::Version.new("#{seg[0]}.#{(seg[1] || 0) + 1}.0")
    when "major" then Gem::Version.new("#{(seg[0] || 0) + 1}.0.0")
    end
    new_version_s = new_version.to_s

    puts "Bumping #{Llmemory::VERSION} -> #{new_version_s} (#{bump_type})"

    # 1. Update version.rb
    version_file = File.expand_path("../llmemory/version.rb", __dir__)
    content = File.read(version_file)
    content = content.sub(/VERSION = "[^"]+"/, %(VERSION = "#{new_version_s}"))
    File.write(version_file, content)
    puts "  Updated lib/llmemory/version.rb"

    # 2. bundle install
    sh "bundle install"
    puts "  Updated Gemfile.lock"

    # 3. Update CHANGELOG.txt
    changelog_path = File.expand_path("../../CHANGELOG.txt", __dir__)
    changelog_content = if File.exist?(changelog_path)
      File.read(changelog_path)
    else
      ""
    end

    today = Time.now.strftime("%Y-%m-%d")
    last_tag = `git describe --tags --abbrev=0 2>/dev/null`.strip
    commits = if last_tag.empty?
      `git log --oneline`.strip
    else
      `git log #{last_tag}..HEAD --oneline`.strip
    end

    new_entry = <<~CHANGELOG

      ## [#{new_version_s}] - #{today}

      ### Changes
      #{commits.lines.map { |l| "- #{l.strip}" }.join("\n")}
    CHANGELOG

    header = "# Changelog\n\n"
    if changelog_content.empty?
      changelog_content = header + new_entry
    else
      changelog_content = header + changelog_content unless changelog_content.start_with?(header)
      changelog_content = changelog_content.sub(/(# Changelog\n\n)/m, "\\1#{new_entry.lstrip}")
    end
    File.write(changelog_path, changelog_content)
    puts "  Updated CHANGELOG.txt"

    # 4. Commit
    sh "git add lib/llmemory/version.rb Gemfile.lock CHANGELOG.txt"
    sh "git commit -m 'Release v#{new_version_s}'"

    # 5. Push
    sh "git push"

    # 6. Tag
    sh "git tag v#{new_version_s}"

    # 7. Push tag
    sh "git push origin v#{new_version_s}"

    puts "\nDone. Released v#{new_version_s}"
  end
end
