# frozen_string_literal: true
require "octokit"

github_token = ENV["GITHUB_TOKEN"]
repo = ENV["REPO"]
pr_number = ENV["PR_NUMBER"]
rails_paths_with_react_version = [
  "app/views/blob/*",
  "app/views/refs/*",
  "app/views/commit/_spoofed_commit_warning.html.erb",
  "app/views/code_navigation/_popover.html.erb",
  "app/views/diff/_split_directional_hunk_header.html.erb",
  "app/views/diff/_diff_context.html.erb",
  "app/views/files/*",
  "app/views/tree/*",
  "README.md",
  "docs/*"
]

class ReactReviewFileParser
  def initialize(repo, pr_number, github_token, file_paths)
    @repo = repo
    @pr_number = pr_number
    @github_token = github_token
    @files_with_react_version = get_file_list(file_paths)
  end

  def puts_message_in_files(files)
    files.each do |file|
      message = <<~HEREDOC.gsub("\n", "%0A").freeze
      There is a React version of this file (`#{file}`) that maybe needs a review. Please, ensure both version are in sync.

      If you need some help, please, contact us in the #repos-ux-refresh channel on Slack.

      Learn more about the Improve Repos Navigation and convert to React here:
        <https://github.com/github/repos/issues/1202/>
      HEREDOC

      puts "-----"
      puts "unowned modified file: #{file}"
      puts "::warning file=#{file}::#{message}"
      puts "-----"
    end
  end

  def octokit_client
    Octokit::Client.new(access_token: @github_token)
  end

  def get_pr_files
    response = octokit_client.pull_request_files(@repo, @pr_number)
    response.map { |file| file["filename"] }
  end

  def get_file_list(paths)
    paths.map { |path| Dir.glob(path) }.flatten.uniq
  end

  def get_files_need_react_review(files)
    files_need_react_review = []

    files.each do |file|
      files_need_react_review << file if files_with_react_version.include?(file)
    end

    files_need_react_review
  end

  def run
    pr_files = get_pr_files
    return unless pr_files
    files_need_react_review = get_files_need_react_review(pr_files)

    if files_need_react_review.any?
      puts "This PR modifies some files that need review its React version"
      puts_message_in_files(files_need_react_review)
      raise "React review found"
    else
      puts "Looks good! It looks this PR doesn't modify any view with a React version"
    end
  end
end

parser = ReactReviewFileParser.new(repo, pr_number, github_token, rails_paths_with_react_version)
parser.run
