# frozen_string_literal: true

require 'octokit'
require 'json'
require 'erb'
require 'net/http'
require 'uri'
require 'pry'
require 'set'

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
    log('INFO', 'Processing issue')
    unless pmp_id_range_issue?
      log('INFO', 'Issue is not a pmp-id-range issue. Skipping')
      return
    end

    add_label_to_issue('alert:pmp-id-range')
    exhausted_tables = extract_exhausted_tables_in_description
    if exhausted_tables[:non_monolith]
      log('INFO', 'No monolith tables found in the issue description')
      add_missed_tableowner_issue_comment(exhausted_tables[:non_monolith])
    end

    return if exhausted_tables[:monolith].empty?

    tableowners = exhausted_tables[:monolith].map { |table| tableowner(table) }.compact.uniq
    return if tableowners.empty?

    tableowners.each do |tableowner|
      add_issue_comment(tableowner)
    end
  end

  private

  def issue
    @issue ||= octokit_client.issue(@repo, @issue_number)
  end

  def pmp_id_range_issue?
    issue[:title].include?('pmp-id-range')
  end

  def add_label_to_issue(label_name)
    octokit_client.add_labels_to_an_issue(@repo, @issue_number, [label_name])
  end

  def octokit_client
    @octokit_client ||= Octokit::Client.new(access_token: @github_token)
  end

  EXHAUSTED_DB_TABLE_REGEX = /{exhausted_table: (?<host>\w+)\.(?<db>\w+)\.(?<column>\w+)/.freeze

  def extract_exhausted_tables_in_description
    issue_description = issue[:body]
    lines = issue_description.lines.filter { |line| line.match?(EXHAUSTED_DB_TABLE_REGEX) }
    return if lines.empty?

    log('INFO', "DB tables found: #{lines}")
    monolith_tables = Set.new
    non_monolith_tables = Set.new
    lines.filter_map do |line|
      if monolith_cluster?(line)
        monolith_tables.add(line.match(EXHAUSTED_DB_TABLE_REGEX)[:db])
      else
        non_monolith_tables.add(line.match(EXHAUSTED_DB_TABLE_REGEX)[:db])
      end
    end

    { monolith: monolith_tables, non_monolith: non_monolith_tables }
  end

  CLUSTER_OUTSIDE_MONOLITH = [
    'tributary_production',
    'dependency_graph',
    'kolide_fleet_app_production'
  ]

  def monolith_cluster?(line)
    host = line.match(EXHAUSTED_DB_TABLE_REGEX)[:host]
    !CLUSTER_OUTSIDE_MONOLITH.include?(host)
  end

  TABLEOWNER_BASE_ENDPOINT = 'https://bones.githubapp.com'

  def tableowner(table)
    log('INFO', 'Requesting to Bones the info for table', table: table)
    uri = URI("#{TABLEOWNER_BASE_ENDPOINT}/monolith_tables/#{table}.json")
    response = Net::HTTP.get_response(uri)
    raise 'Invalid response from Bones' unless response.is_a?(Net::HTTPSuccess)

    parsed_json = JSON.parse(response.body, symbolize_names: true)
    raise "No service found for the #{parsed_json[:table_name]} table in [Bones](https://bones.githubapp.com/monolith_tables/#{parsed_json[:table_name]})" if parsed_json[:service].nil?

    data = {
      db_table: table,
      service: parsed_json[:service],
      github_team: parsed_json[:team]
    }

    log('INFO', 'Data found for table', table: table)
    log('INFO', JSON.pretty_generate(data), table: table)
    data
  end

  def message(tableowner)
    <<~HEREDOC
      :wave: Hi @github/#{tableowner[:github_team]},

      The [`#{tableowner[:service]}` service](https://catalog.githubapp.com/services/#{tableowner[:service]}), which you maintain, **has exhausted over 70% of its id range**. As id exhaustion can cause availability incidents, it is important that you track and prioritize work to remediate this situation. Please feel free to reach out to [#app-core](https://github.slack.com/archives/C01A96EDN4F) for support and next steps.

      If your team does not maintain the table, please update the ownership information in the [`db/tableowners.yaml`](https://github.com/github/github/blob/master/db/tableowners.yaml) file and mention the correct team in this issue..

      Thanks for your help! :heart:

    HEREDOC
  end

  def missed_tableowner_message(non_monolith_tables)
    <<~HEREDOC
      :wave: Hi @github/app-core,

      This alert was raised for the `#{non_monolith_tables.join(', ')}` non-monolith table(s). Please update the [GitHub action](https://github.com/github/nines/blob/main/.github/workflows/pmp-id-range.rb) to ignore the clusters outside the monolith.

      Thanks for your help! :heart:

    HEREDOC
  end

  def add_missed_tableowner_issue_comment(non_monolith_tables)
    octokit_client.add_comment(@repo, @issue_number, missed_tableowner_message(non_monolith_tables))
  end

  def add_issue_comment(tableowner)
    octokit_client.add_comment(@repo, @issue_number, message(tableowner))
    log('INFO', 'Commend created', table: tableowner[:db_table])
  end

  def log(level, msg, table: nil)
    log_text = {
      level: level,
      issue_number: @issue_number,
      msg: msg,
      table: table
    }.filter_map { |k, v| "#{k}=#{v}" unless v.nil? }.join(' ')

    puts log_text
  end
end

parser = PmpIdRangeIssue.new(repo, issue_number, github_token)
parser.run
