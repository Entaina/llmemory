# frozen_string_literal: true

module Release
  RELEASE_FILES = %w[lib/llmemory/version.rb Gemfile.lock CHANGELOG.txt].freeze
  DEFAULT_NOTES_PATH = File.expand_path("../../tmp/release_notes.txt", __dir__)

  module_function

  def resolve_notes_path(arg)
    path = arg.to_s.strip
    path = DEFAULT_NOTES_PATH if path.empty?
    File.expand_path(path)
  end

  def build_changelog_entry(version, date, notes_body)
    body = notes_body.strip
    body = body.sub(/\A#+\s*[^\n]*\n+/, "") # drop optional leading markdown title

    <<~ENTRY

      ## [#{version}] - #{date}

      #{body}
    ENTRY
  end

  def allowed_dirty_path?(path, notes_path)
    RELEASE_FILES.include?(path) || File.expand_path(path) == File.expand_path(notes_path)
  end
end

namespace :release do
  desc "Show commits and diff stat since the last tag (helper before writing release notes)"
  task :since_tag do
    last_tag = `git describe --tags --abbrev=0 2>/dev/null`.strip
    range = last_tag.empty? ? "HEAD" : "#{last_tag}..HEAD"
    puts "Last tag: #{last_tag.empty? ? '(none)' : last_tag}"
    puts "Range: #{range}\n\n"
    puts "Commits:"
    puts(`git log #{range} --oneline`.strip)
    puts "\nDiff stat:"
    puts(`git diff #{range} --stat`.strip)
  end

  desc "Bump version (patch|minor|major). Requires tmp/release_notes.txt or notes path. Checks: branch=main, clean tree, tests pass. Then: version, CHANGELOG, commit, push, tag"
  task :bump, [:bump_type, :notes_file] => [] do |_t, args|
    require_relative "../llmemory/version"

    current_branch = `git rev-parse --abbrev-ref HEAD`.strip
    abort "Current branch must be main (got: #{current_branch})" unless current_branch == "main"

    notes_path = Release.resolve_notes_path(args[:notes_file])

    status_lines = `git status --porcelain --untracked-files=normal`.strip.lines
    other_changes = status_lines.reject do |line|
      path = line.sub(/\A..\s+/, "").strip.split(" -> ").last
      Release.allowed_dirty_path?(path, notes_path)
    end
    unless other_changes.empty?
      abort "Working tree has uncommitted changes outside release files. Commit or stash them first.\n#{other_changes.join}"
    end

    unless File.exist?(notes_path)
      abort <<~MSG
        Release notes file not found: #{notes_path}

        1. Inspect changes since the last tag:
             bundle exec rake release:since_tag

        2. Write a changelog entry (user-visible changes, not raw commits) to:
             tmp/release_notes.txt

           Use sections such as Added / Changed / Fixed / Removed / Notes.
           Follow the style of recent entries in CHANGELOG.txt (e.g. v0.2.7).

        3. Re-run:
             bundle exec rake release:bump[#{args[:bump_type] || 'patch'}]
             bundle exec rake release:bump[#{args[:bump_type] || 'patch'},path/to/notes.txt]
      MSG
    end

    notes_body = File.read(notes_path).strip
    abort "Release notes file is empty: #{notes_path}" if notes_body.empty?

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
    puts "  Release notes: #{notes_path}"

    version_file = File.expand_path("../llmemory/version.rb", __dir__)
    content = File.read(version_file)
    content = content.sub(/VERSION = "[^"]+"/, %(VERSION = "#{new_version_s}"))
    File.write(version_file, content)
    puts "  Updated lib/llmemory/version.rb"

    sh "bundle install"
    puts "  Updated Gemfile.lock"

    changelog_path = File.expand_path("../../CHANGELOG.txt", __dir__)
    changelog_content = File.exist?(changelog_path) ? File.read(changelog_path) : ""
    today = Time.now.strftime("%Y-%m-%d")
    new_entry = Release.build_changelog_entry(new_version_s, today, notes_body)

    header = "# Changelog\n\n"
    if changelog_content.empty?
      changelog_content = header + new_entry
    else
      changelog_content = header + changelog_content unless changelog_content.start_with?(header)
      changelog_content = changelog_content.sub(/(# Changelog\n\n)/m, "\\1#{new_entry.lstrip}")
    end
    File.write(changelog_path, changelog_content)
    puts "  Updated CHANGELOG.txt"

    sh "git add lib/llmemory/version.rb Gemfile.lock CHANGELOG.txt"
    sh "git commit -m 'Release v#{new_version_s}'"
    sh "git push"
    sh "git tag v#{new_version_s}"
    sh "git push origin v#{new_version_s}"

    default_notes = Release::DEFAULT_NOTES_PATH
    File.delete(notes_path) if File.expand_path(notes_path) == File.expand_path(default_notes) && File.exist?(notes_path)
    puts "\nDone. Released v#{new_version_s}"
  end
end
