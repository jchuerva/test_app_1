# frozen_string_literal: true

require 'octokit'
require 'json'
require 'erb'
require 'net/http'
require 'uri'
require 'datadog/statsd'
require 'resolv'

module Datadog
  def self.dogstats
    dogstatsd_host = ENV.fetch('DOGSTATSD_HOST')
    dogstatsd_ip = Resolv.getaddress(dogstatsd_host)

    # Across GitHub hosts we use this port instead of the default (8125)
    dogstatsd_port = ENV.fetch('DOGSTATSD_PORT', 28_125)

    # Always remember to tag your metrics with what application they're
    # coming from! More info in this all-hands talk:
    # https://githubber.tv/github/eng-all-hands-whats-different-about-observability-on-kubernetes
    Datadog::Statsd.new(
      dogstatsd_ip,
      dogstatsd_port,
      {
        namespace: 'nines',
        tags: ['application:nines', 'error: pmp-id-range']
      }
    )
  end
end

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
    db_tables = extract_tables_in_description
    return unless db_tables

    tableowners = db_tables.map { |table| tableowner(table) }.compact.uniq
    return if tableowners.empty?

    tableowners.each do |tableowner|
      add_issue_comment(tableowner)
    end
  end

  private

  def octokit_client
    Octokit::Client.new(access_token: @github_token)
  end

  DB_TABLE_REGEX = /(?<host>\w+)\.(?<db>\w+)\.(?<column>\w+) (?<type>[a-z]+)/.freeze

  def extract_tables_in_description
    binding.pry
    issue = octokit_client.issue(@repo, @issue_number)
    return unless issue[:title].include?('pmp-id-range')

    issue_description = issue[:body]

    lines = issue_description.lines.filter { |line| line.match?(DB_TABLE_REGEX) }
    return unless lines.empty?

    lines.map { |line| line.match(DB_TABLE_REGEX)[:db] }.uniq
  end

  # TABLEOWNER_BASE_ENDPOINT = 'https://bones.githubapp.com/'
  TABLEOWNER_BASE_ENDPOINT = 'http://localhost:3000/'

  def tableowner(table)
    uri = URI.parse("#{TABLEOWNER_BASE_ENDPOINT}/monolith_tables/#{table}.json")
    # header = { 'Content-Type' => 'text/json', 'Authorization' => "Token token=#{@github_token}" }
    # response = Net::HTTP.get_response(uri, header)
    response = Net::HTTP.get_response(uri)

    binding.pry
    if response.is_a?(Net::HTTPServerError)
      Datadog.dogstats.increment('nines.pmp-id-range', tags: ["db_table: #{table}"])
      return nil
    end

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
      :wave: Hi @github/#{tableowner[:github_team]},

      The [`#{tableowner[:service]}` service](https://catalog.githubapp.com/services/#{tableowner[:service]}), which you maintain, **has exhausted over 70%** of its id range. As id exhaustion can cause availability incidents, it is important that you track and prioritize work to remediate this situation. Please feel free to reach out to `#app-core` for support and next steps.

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
