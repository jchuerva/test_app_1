# frozen_string_literal: true

# require 'pry'
require 'octokit'

github_token = ENV['GITHUB_TOKEN']
repo = ENV['REPO']
pr_number = ENV['PR_NUMBER']

class PRFilesFormat
  def initialize(repo, pr_number, github_token)
    @repo = repo
    @pr_number = pr_number
    @github_token = github_token
  end

  def jest_compatible_files?(files)
    files.any? { |file| file.end_with?(".js", ".ts") }
  end

  def run
    pr_files = get_pr_files
    return unless pr_files
    puts jest_compatible_files?(pr_files)
  end

  private
  def octokit_client
    Octokit::Client.new(access_token: @github_token)
  end

  def get_pr_files
    response = octokit_client.pull_request_files(@repo, @pr_number)
    response.map { |file| file['filename'] }
  end
end

parser = PRFilesFormat.new(repo, pr_number, github_token)
parser.run
