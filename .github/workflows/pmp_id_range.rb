# frozen_string_literal: true

require 'octokit'
require 'json'
require 'erb'
require 'net/http'
require 'uri'
require 'pry'

github_token = ENV['GITHUB_TOKEN']
repo = ENV['REPO']
issue_number = ENV['ISSUE_NUMBER']

class PmpIdRangeIssue
  def initialize(repo, issue_number, github_token)
    @repo = repo
    @issue_number = issue_number
    @github_token = github_token
  end

  def run
    add_label_to_issue('alert:pmp-id-range')
    db_tables = extract_exhausted_tables_in_description
    return unless db_tables

    tableowners = db_tables.map { |table| tableowner(table) }.compact.uniq
    return if tableowners.empty?

    tableowners.each do |tableowner|
      add_issue_comment(tableowner)
    end
  end

  private

  def add_label_to_issue(label_name)
    octokit_client.add_labels_to_an_issue(@repo, @issue_number, [label_name])
  end

  def octokit_client
    Octokit::Client.new(access_token: @github_token)
  end

  EXHAUSTED_DB_TABLE_REGEX = /{exhausted_table: (?<host>\w+)\.(?<db>\w+)\.(?<column>\w+)/.freeze

  def extract_exhausted_tables_in_description
    issue = octokit_client.issue(@repo, @issue_number)
    return unless issue[:title].include?('pmp-id-range')

    issue_description = issue[:body]

    lines = issue_description.lines.filter { |line| line.match?(EXHAUSTED_DB_TABLE_REGEX) }
    return if lines.empty?

    lines.map { |line| line.match(EXHAUSTED_DB_TABLE_REGEX)[:db] }.uniq
  end

  TABLEOWNER_BASE_ENDPOINT = 'https://bones.githubapp.com'

  def tableowner(table)
    uri = URI("#{TABLEOWNER_BASE_ENDPOINT}/monolith_tables/#{table}2.json")
    response = Net::HTTP.get_response(uri)
    raise 'Invalid response from Bones' unless response.is_a?(Net::HTTPSuccess)

    parsed_json = JSON.parse(response.body, symbolize_names: true)
    return nil if parsed_json[:service].nil?

    {
      db_table: table,
      service: parsed_json[:service],
      github_team: parsed_json[:team]
    }
  end

  def message(tableowner)
    <<~HEREDOC
      :wave: Hi @github/#{tableowner[:github_team]},

      The [`#{tableowner[:service]}` service](https://catalog.githubapp.com/services/#{tableowner[:service]}), which you maintain, **has exhausted over 70% of its id range**. As id exhaustion can cause availability incidents, it is important that you track and prioritize work to remediate this situation. Please feel free to reach out to [#app-core](https://github.slack.com/archives/C01A96EDN4F) for support and next steps.

      If your team does not maintain the table, please update the ownership information in the [`db/tableowners.yaml`](https://github.com/github/github/blob/master/db/tableowners.yaml) file and mention the correct team in this issue..

      Thanks for your help! :heart:

    HEREDOC
  end

  def add_issue_comment(tableowner)
    octokit_client.add_comment(@repo, @issue_number, message(tableowner))
  end
end

parser = PmpIdRangeIssue.new(repo, issue_number, github_token)
parser.run
