# frozen_string_literal: true

# require 'pry'
require 'octokit'

github_token = ENV['GITHUB_TOKEN']
repo = ENV['REPO']
pr_number = ENV['PR_NUMBER']

# paths_with_multiple_implementations = {
#   "repos-ux-refresh": ['app/views/blob/*', 'app/views/refs/*', 'docs/*']
# }
#   'app/views/blob/*',
#   'app/views/refs/*',
#   'app/views/commit/_spoofed_commit_warning.html.erb',
#   'app/views/code_navigation/_popover.html.erb',
#   'app/views/diff/_split_directional_hunk_header.html.erb',
#   'app/views/diff/_diff_context.html.erb',
#   'app/views/files/*',
#   'app/views/tree/*',
#   'docs/*'
# ]

paths_with_multiple_implementations = [
  {
    name: 'repos_ux_refresh',
    files: ['app/views/blob/*', 'app/views/refs/*', 'docs/*'],
    slack_channel: 'repos-ux-refresh',
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

  def puts_message_in_files(files)
    files.each do |file|
      puts '-----'
      puts "unowned modified file: #{file}"
      puts "::warning file=#{file}::#{build_message(file)}"
      puts '-----'
    end
  end

  def build_message(file)
    slack_channel = @files_with_mult_implementations[file][:slack_channel]
    additional_message_text = @files_with_mult_implementations[file][:additional_message_text]

    message = base_message_text(file)

    if slack_channel
      message += "\nIf you need some help, please, contact us in the ##{slack_channel} channel on Slack.\n"
    end

    message += additional_message_text if additional_message_text

    message += "ola k ase\n"

    message.gsub("\n", '%0A')
  end

  def base_message_text(file)
    <<~HEREDOC
      The file (`#{file}`) has another implementation (View Component or React version) that needs review. Please, ensure both version are in sync.\n
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
    full_file_list = {}
    sections.each do |section|
      paths = section[:files]
      break unless paths

      slack_channel = section[:slack_channel]
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
end

parser = MultImplemntationFileParser.new(repo, pr_number, github_token, paths_with_multiple_implementations)
parser.run
