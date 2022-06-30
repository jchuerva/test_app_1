# frozen_string_literal: true

require 'pry'
require 'octokit'

github_token = ENV['GITHUB_TOKEN']
repo = ENV['REPO']
pr_number = ENV['PR_NUMBER']

PATHS_TO_MONITOR = [
  {
    name: 'repos_ux_refresh',
    files: ['app/views/blob/*', 'app/views/refs/*', 'docs/*'],
    # slack_channel: 'repos-ux-refresh',
    additional_message_text: 'Learn more about the Improve Repos Navigation and convert to React here: <https://github.com/github/repos/issues/1202/>'
  }
]

class MultImplemntationFileParser
  def initialize(repo, pr_number, github_token, file_paths)
    @repo = repo
    @pr_number = pr_number
    @github_token = github_token
    @files_with_mult_implementations = build_file_list(file_paths)
  end

  def run
    pr_files = get_pr_files
    return unless pr_files

    files_need_review = get_files_need_review(pr_files)

    if files_need_review.any?
      puts 'This PR modifies some files that need review its other implementation (View Component or React version)'
      puts_message_in_files(files_need_review)
      raise 'React review found'
    else
      puts "Looks good! It looks this PR doesn't modify any view with multiple implementations"
    end
  end

  private

  def puts_message_in_files(files)
    files.each do |file|
      puts '-----'
      puts "unowned modified file: #{file}"
      puts "::warning file=#{file}::#{file_message(file)}"
      puts '-----'
    end
  end

  def file_message(file)
    file_data = @files_with_mult_implementations[file]
    additional_message_text = file_data[:additional_message_text]

    message = base_text_message(file)
    message += additional_message_text

    message.gsub("\n", '%0A')
  end

  def base_text_message(file)
    slack_channel = @files_with_mult_implementations[file][:slack_channel]

    <<~HEREDOC
      The file (`#{file}`) has a new implementation (View Component or React) that may need to change to ensure both versions are in sync.\n

      "If you need some help, please, contact us in the ##{slack_channel} channel on Slack.\n"
    HEREDOC
  end

  def octokit_client
    Octokit::Client.new(access_token: @github_token)
  end

  def get_pr_files
    response = octokit_client.pull_request_files(@repo, @pr_number)
    response.map { |file| file['filename'] }
  end

  def build_file_list(sections)
    ensure_path_format

    full_file_list = {}
    sections.each do |section|
      paths = section[:files]
      exit unless paths

      slack_channel = section[:slack_channel]
      exit unless slack_channel

      additional_message_text = section[:additional_message_text]

      paths.each do |path|
        files = Dir.glob(path)
        files.each do |file|
          full_file_list[file] = { slack_channel: slack_channel, additional_message_text: additional_message_text }
        end
      end
    end
    full_file_list
  end

  def get_files_need_review(files)
    files.filter_map { |file| file if @files_with_mult_implementations[file] }
  end
end

def input_valid_format?
  PATHS_TO_MONITOR.each do |section|
    raise 'Invalid format' if section.key?(:files) || section.key?(:slack_channel)
  end
end

raise 'Invalid format' unless input_valid_format?

parser = MultImplemntationFileParser.new(repo, pr_number, github_token, PATHS_TO_MONITOR)
parser.run
