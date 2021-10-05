#!/bin/bash

API_URL="https://api.github.com/repos/jchuerva/test_app_1/pulls/${PR_NUMBER}/files"
FILES=$(curl -s -X GET -H "Authorization: Bearer ${GITHUB_TOKEN}" $API_URL | jq -r '.[] | .filename')
for file in $FILES
do
  if grep -Fxq "$file" docs/serviceowners_no_matches.txt
  then
    UNOWNED_FILES+=($file)
  fi
done
if [ $UNOWNED_FILES ]
then
  FAILED_MESSAGE=" \
  This file currently does not belong to a service. To fix this, please do one of the following:%0A \
  %0A \
    * Find a service that makes sense for this file and update SERVICEOWNERS accordingly%0A \
    * Create a new service and assign this file to it%0A \
  %0A \
  Learn more about service maintainership here:%0A \
  https://thehub.github.com/engineering/development-and-ops/dotcom/serviceowners \
  "
  echo "This PR touch some unowned files"
  for file in $UNOWNED_FILES
  do
    echo "   - $file"
    echo "::warning file=$file::${FAILED_MESSAGE}"
  done
  exit 1
else
  echo "Looks good! All files modified have an owner!"
fi