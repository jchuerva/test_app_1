# frozen_string_literal: true

require 'octokit'
require 'json'
require 'erb'

github_token = ENV['GITHUB_TOKEN']
repo = ENV['REPO']
pr_number = ENV['PR_NUMBER']

class UnownedFileParser
  def initialize(repo, pr_number, github_token)
    @repo = repo
    @pr_number = pr_number
    @github_token = github_token
  end

  def self.build_fail_message
    message = <<~HEREDOC
      This file currently does not belong to a service. To fix this, please do one of the following:

        * Find a service that makes sense for this file and update SERVICEOWNERS accordingly
        * Create a new service and assign this file to it

      Learn more about service maintainership here:
       <https://thehub.github.com/engineering/development-and-ops/dotcom/serviceowners/service-oriented-maintainership/>
    HEREDOC

    message.gsub("\n", '%0A').freeze
  end

  FAIL_MESSAGE = build_fail_message

  def puts_message_in_files(files)
    puts 'This PR touches some unowned files'
    files.each do |file|
      puts "::warning file=#{file}::#{FAIL_MESSAGE}"
    end
  end

  def octokit_client
    Octokit::Client.new(access_token: @github_token)
  end

  def get_pr_files
    response = octokit_client.pull_request_files(@repo, @pr_number)
    response.map { |file| file['filename'] }
  end

  def get_unowned_files(files)
    unowned_files = []
    serviceownes_no_match = File.read('docs/serviceowners_no_matches.txt').lines.map(&:chomp)

    files.each do |file|
      unowned_files << file if serviceownes_no_match.include?(file)
    end

    unowned_files
  end

  def run
    files = get_pr_files
    return unless files

    unowned_files = get_unowned_files(files)

    if unowned_files.any?
      puts_message_in_files(unowned_files)
    else
      puts 'Looks good! All files modified have an owner!'
    end
  end
end

parser = UnownedFileParser.new(repo, pr_number, github_token)
parser.run
