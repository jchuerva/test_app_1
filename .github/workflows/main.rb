require 'octokit'
require 'json'

github_token = ENV['GITHUB_TOKEN']
repo = ENV['REPO']
pr_number = ENV['PR_NUMBER']

class UnownedFileParser
  FAIL_MESSAGE = build_fail_message

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
      https://thehub.github.com/engineering/development-and-ops/dotcom/serviceowners
    HEREDOC

    message.gsub("\n", '%0C').freeze
  end

  def puts_message_in_files(files)
  failed_message =

    files.each do |file|
      puts "::warning file=#{file}::#{failed_message}"
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
    serviceownes_no_match = File.read('docs/serviceowners_no_matches.txt')

    files.each do |file|
      unowned_files << file if serviceownes_no_match.include?(file)
    end

    unowned_files
  end

  def run
    files = get_pr_files
    return unless files
    unowned_files = get_unowned_files(files)

    if unowned_files
      puts_message_in_files(unowned_files)
      raise "Unowned files found"
    else
      puts 'Looks good! All files modified have an owner!'
    end
  end
end

parser = UnownedFileParser.new(repo, pr_number, github_token)
parser.run