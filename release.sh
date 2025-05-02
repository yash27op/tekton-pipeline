#!/bin/bash
set -e

#################################
# === CHECK: GitHub CLI Installed ===
#################################

if ! command -v gh &> /dev/null; then
    echo "❌ GitHub CLI (gh) is not installed. Install it from https://cli.github.com/"
    exit 1
fi

#################################
# === BRANCH CREATION ===
#################################

read -p "Enter a new branch name: " NEW_BRANCH
if [[ -z "$NEW_BRANCH" ]]; then
    echo "❌ Branch name cannot be empty."
    exit 1
fi

git checkout -b "$NEW_BRANCH"
echo "✅ Created and switched to branch: $NEW_BRANCH"

#################################
# === MAKE CHANGES INTERACTIVE ===
#################################

echo "🛠️  Make your changes now. Press Enter when done."
read -p "Press Enter to continue..."

git status

#################################
# === COMMIT LOOP ===
#################################

while true; do
    read -p "Do you want to add more changes? (y/n): " ADD_MORE
    if [[ "$ADD_MORE" == "y" ]]; then
        git add .
        read -p "Enter commit message for these changes: " COMMIT_MSG
        git commit -m "$COMMIT_MSG"
        git status
    else
        break
    fi
done

#################################
# === PUSH CHANGES ===
#################################

git push -u origin "$NEW_BRANCH"

#################################
# === PR DETAILS ===
#################################

read -p "Enter base branch for PR (e.g., main, develop): " BASE_BRANCH
read -p "Enter PR Title: " PR_TITLE
read -p "Enter PR Description: " PR_BODY
read -p "Enter reviewers (comma-separated GitHub usernames), or leave blank: " REVIEWERS

#################################
# === CREATE PR USING gh ===
#################################

if [[ -z "$REVIEWERS" ]]; then
    gh pr create --base "$BASE_BRANCH" --head "$NEW_BRANCH" --title "$PR_TITLE" --body "$PR_BODY"
else
    gh pr create --base "$BASE_BRANCH" --head "$NEW_BRANCH" --title "$PR_TITLE" --body "$PR_BODY" --reviewer "$REVIEWERS"
fi

#################################
# === FINAL STATUS ===
#################################

if [ $? -eq 0 ]; then
    echo "✅ Pull request successfully created from $NEW_BRANCH to $BASE_BRANCH."
else
    echo "❌ Failed to create pull request."
fi
