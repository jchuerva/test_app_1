# frozen_string_literal: true

require 'octokit'
require 'json'
require 'erb'
require 'net/http'
require 'uri'

github_token = ENV['GITHUB_TOKEN']
repo = ENV['REPO']
issue_number = ENV['ISSUE_NUMBER']

class PmpIdRangeIssue
  def initialize(repo, issue_number, github_token)
    @repo = repo
    @issue_number = issue_number
    @github_token = github_token
  end

  def octokit_client
    Octokit::Client.new(access_token: @github_token)
  end

  DB_TABLE_REGEX = /(?<host>\w+)\.(?<db>\w+)\.(?<column>\w+) (?<type>[a-z]+)/.freeze

  def extract_tables_in_description
    issue = octokit_client.issue(@repo, @issue_number)
    return unless issue[:title].include?('pmp-id-range')

    issue_description = issue[:body]

    lines = issue_description.lines.filter { |line| line.match?(DB_TABLE_REGEX) }
    return unless lines

    lines.map { |line| line.match(DB_TABLE_REGEX)[:db] }.uniq
  end

  TABLEOWNER_BASE_ENDPOINT = 'http://localhost:3000'

  def tableowner(table)
    uri = URI.parse("#{TABLEOWNER_BASE_ENDPOINT}/monolith_tables/#{table}.json")
    # header = { "Content-Type" => "text/json", "Authorization" => "Token token=#{@github_token}" }
    response = Net::HTTP.get_response(uri)
    return nil unless response.is_a?(Net::HTTPSuccess)

    response.body

    parsed_json = JSON.parse(response.body, symbolize_names: true)
    {
      db_table: table,
      service: parsed_json[:service],
      github_team: parsed_json[:team]
    }
  end

  def message(tableowner)
    <<~HEREDOC
      :wave: Hi `@github/#{tableowner[:github_team]}`,

      As maintainers of the service [`#{tableowner[:service]}`](https://catalog.githubapp.com/services/#{tableowner[:service]}), this issue might impact your. The `#{tableowner[:db_table]}` table **has exhaused over 70%**. Please add this issue in your team radar.

      If your team does not mainained the table, please update the [`db/tableowners.yaml`](https://github.com/github/github/blob/master/db/tableowners.yaml) file.

      Thanks for your help! :heart:

    HEREDOC
  end

  def add_issue_comment(tableowner)
    octokit_client.add_comment(@repo, @issue_number, message(tableowner))
  end

  def run
    db_tables = extract_tables_in_description
    return unless db_tables

    tableowners = db_tables.map { |table| tableowner(table) }.compact.uniq
    return if tableowners.empty?

    tableowners.each do |tableowner|
      add_issue_comment(tableowner)
    end
  end
end

parser = PmpIdRangeIssue.new(repo, issue_number, github_token)
parser.run
