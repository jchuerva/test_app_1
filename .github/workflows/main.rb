require "octokit"
require "json"

github_token = ENV["GITHUB_TOKEN"]
repo = ENV["REPO"]
pr_number = ENV["PR_NUMBER"]


def puts_message_in_files(files)
  message <<~EOF
    This file currently does not belong to a service. To fix this, please do one of the following:
    
      * Find a service that makes sense for this file and update SERVICEOWNERS accordingly
      * Create a new service and assign this file to it
    
    Learn more about service maintainership here:
    https://thehub.github.com/engineering/development-and-ops/dotcom/serviceowners
  EOF

  failed_message = message.gsub("\n", "%0C")
  
  files.each do |file|
    puts "::warning file=#{file}::#{failed_message}"
  end
end

def octokit_client(token)
  Octokit::Client.new(access_token: token)
end

def get_pr_files(client, repo, pr_number)
  response = client.pull_request_files(repo, pr_number)
  response.map { |file| file["filename"] }
end

def get_unowned_files(files)
  unowned_files = []
  serviceownes_no_match = File.read("docs/serviceowners_no_matches.txt")

  files.each do |file|
    if serviceownes_no_match.include?(file)
      unowned_files << file
    end
  end

  unowned_files
end

client = octokit_client(github_token)
files = get_pr_files(client, repo, pr_number)

return unless files

unowned_files = get_unowned_files(files)

if unowned_files
  puts_message_in_files(unowned_files)
  fail
else
  puts "Looks good! All files modified have an owner!"
end
