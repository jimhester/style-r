#!/bin/bash

# this was adapted from the automatic rebase action at https://github.com/cirrus-actions/rebase/blob/master/entrypoint.sh

set -e

# Workaround unitl new Actions support neutral strategy
# See how it was before: https://developer.github.com/actions/creating-github-actions/accessing-the-runtime-environment/#exit-codes-and-statuses
NEUTRAL_EXIT_CODE=0

# skip if no /rebase
echo "Checking if comment contains '/style' command..."
(jq -r ".comment.body" "$GITHUB_EVENT_PATH" | grep -Fq "/style") || exit $NEUTRAL_EXIT_CODE

# skip if not a PR
echo "Checking if issue is a pull request..."
(jq -r ".issue.pull_request.url" "$GITHUB_EVENT_PATH") || exit $NEUTRAL_EXIT_CODE

if [[ "$(jq -r ".action" "$GITHUB_EVENT_PATH")" != "created" ]]; then
	echo "This is not a new comment event!"
	exit $NEUTRAL_EXIT_CODE
fi

PR_NUMBER=$(jq -r ".issue.number" "$GITHUB_EVENT_PATH")
echo "Collecting information about PR #$PR_NUMBER of $GITHUB_REPOSITORY..."

if [[ -z "$GITHUB_TOKEN" ]]; then
	echo "Set the GITHUB_TOKEN env variable."
	exit 1
fi

URI=https://api.github.com
API_HEADER="Accept: application/vnd.github.v3+json"
AUTH_HEADER="Authorization: token $GITHUB_TOKEN"

pr_resp=$(curl -X GET -s -H "${AUTH_HEADER}" -H "${API_HEADER}" \
          "${URI}/repos/$GITHUB_REPOSITORY/pulls/$PR_NUMBER")

BASE_REPO=$(echo "$pr_resp" | jq -r .base.repo.full_name)
HEAD_REPO=$(echo "$pr_resp" | jq -r .head.repo.full_name)
HEAD_BRANCH=$(echo "$pr_resp" | jq -r .head.ref)
HEAD_CLONE_URL=$(echo "$pr_resp" | jq -r .head.repo.clone_url)

set -o xtrace

# Install R dependencies
echo "options(repos = 'https://demo.rstudiopm.com/all/__linux__/xenial/latest')" > ~/.Rprofile

Rscript -e 'install.packages("styler")'

# Add token to URL
HEAD_CLONE_URL2=$(echo "$HEAD_CLONE_URL" | sed "s{https://{https://x-access-token:$GITHUB_TOKEN@{")

# Fetch from the URL, check changes
git remote add pr $HEAD_CLONE_URL2
git config --global user.email "action@github.com"
git config --global user.name "GitHub Action"

# Checkout the branch
git fetch pr $HEAD_BRANCH
git checkout -b $HEAD_BRANCH pr/$HEAD_BRANCH

# Document
Rscript -e 'styler::style_pkg()'

git add \*.R
git commit -m 'Style'

# push back
git push pr HEAD:$HEAD_BRANCH
