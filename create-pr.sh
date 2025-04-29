#!/bin/bash
set -e

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

# Prompt for reviewers (comma separated GitHub usernames, optional)
read -p "Enter GitHub usernames of reviewers (comma separated, or leave blank): " REVIEWERS_LIST

# Ensure mandatory inputs are not empty
if [[ -z "$BASE_BRANCH" || -z "$PR_TITLE" || -z "$PR_DESCRIPTION" ]]; then
    echo "Error: All fields are required!"
    exit 1
fi

# Format PR title
FINAL_PR_TITLE="$PR_TYPE: $PR_TITLE"

# Stage any unstaged changes (Optional: Ask user)
echo "Do you want to add changes before pushing? (y/n)"
read add_changes

if [[ "$add_changes" == "y" ]]; then
    git add .
    read -p "Enter commit message for new changes: " COMMIT_MESSAGE
    git commit -m "$COMMIT_MESSAGE"
fi

# Push the current branch (create upstream if not pushed yet)
git push -u origin "$BRANCH_NAME"

# Create the Pull Request
if [[ -z "$REVIEWERS_LIST" ]]; then
    gh pr create --base "$BASE_BRANCH" --head "$BRANCH_NAME" --title "$FINAL_PR_TITLE" --body "$PR_DESCRIPTION"
else
    gh pr create --base "$BASE_BRANCH" --head "$BRANCH_NAME" --title "$FINAL_PR_TITLE" --body "$PR_DESCRIPTION" --reviewer "$REVIEWERS_LIST"
fi

# Confirm PR creation
if [ $? -eq 0 ]; then
    echo "✅ Pull request successfully created!"
else
    echo "❌ Failed to create pull request."
fi
