require "octokit"
require "json"

REPO = "jchuerva/test_app_1'"

FAILED_MESSAGE = <<HEREDOC
  This file currently does not belong to a service. To fix this, please do one of the following:
    * Find a service that makes sense for this file and update SERVICEOWNERS accordingly
    * Create a new service and assign this file to it

  Learn more about service maintainership here:
  https://thehub.github.com/engineering/development-and-ops/dotcom/serviceowners
HEREDOC

def print_message_in_files(files)
  files.each do |file|
    print "::warning file=#{file}::#{FAILED_MESSAGE}"
  end
end

def get_pr_files
  client = Octokit::Client.new(access_token: GITHUB_TOKEN)
  response = client.pull_request_files(REPO, PR_NUMBER)
  response.map { |file| file["filename"] }
end

files = get_pr_files

return unless files
binding.pry

serviceownes_no_match = File.read("serviceowners_no_matches.txt")
unowned_files = []

files.each do |file|
  if serviceownes_no_match.include?(file)
    unowned_files << file
  end

  if unowned_files
    print_message_in_files(unowned_files)
  else
    print "Looks good! All files modified have an owner!"
  end
end