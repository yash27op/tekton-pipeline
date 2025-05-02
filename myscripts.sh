#!/bin/bash

# Ensure GitHub CLI is installed
if ! command -v gh &> /dev/null; then
    echo "GitHub CLI (gh) is not installed. Install it from https://cli.github.com/"
    exit 1
fi

# Get the current branch name
BRANCH_NAME=$(git rev-parse --abbrev-ref HEAD)

# PR Type Selection
OPTIONS=("task" "bug" "feature" "hotfix" "fix" "style" "refactor" "test")
echo "Select PR Type:"
for i in "${!OPTIONS[@]}"; do
    echo "$((i+1))) ${OPTIONS[$i]}"
done

while true; do
    read -p "Enter a number (1-${#OPTIONS[@]}): " PR_TYPE_INDEX
    if [[ "$PR_TYPE_INDEX" =~ ^[1-9]$ ]] && [ "$PR_TYPE_INDEX" -le "${#OPTIONS[@]}" ]; then
        PR_TYPE="${OPTIONS[$((PR_TYPE_INDEX-1))]}"
        break
    else
        echo "Invalid choice, please enter a number between 1 and ${#OPTIONS[@]}"
    fi
done

# Prompt for base branch, PR title, and description
read -p "Enter the base branch (e.g., main, develop): " BASE_BRANCH
read -p "Enter PR Title: " PR_TITLE
read -p "Enter PR Description: " PR_DESCRIPTION

# Ensure inputs are not empty
if [[ -z "$BASE_BRANCH" || -z "$PR_TITLE" || -z "$PR_DESCRIPTION" ]]; then
    echo "Error: All fields are required!"
    exit 1
fi

# Format PR title
FINAL_PR_TITLE="$PR_TYPE: $PR_TITLE"

# Predefined Reviewers (Modify with actual GitHub usernames)
PREDEFINED_REVIEWERS=("dev-lead" "team-reviewer")

# Convert array to comma-separated string
REVIEWERS_LIST=$(IFS=, ; echo "${PREDEFINED_REVIEWERS[*]}")

# Push the current branch (if not already pushed)
git push origin "$BRANCH_NAME"

# Create the Pull Request using GitHub CLI with assigned reviewers
gh pr create --base "$BASE_BRANCH" --head "$BRANCH_NAME" --title "$FINAL_PR_TITLE" --body "$PR_DESCRIPTION" --reviewer "$REVIEWERS_LIST"

# Confirm the PR was created
if [ $? -eq 0 ]; then
    echo "✅ Pull request successfully created and assigned to reviewers: $REVIEWERS_LIST"
else
    echo "❌ Failed to create pull request."
fi