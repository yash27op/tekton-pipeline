#!/bin/bash
set -e

# === CHECK: GitHub CLI Installed ===
if ! command -v gh &> /dev/null; then
    echo "❌ GitHub CLI (gh) is not installed. Install it from https://cli.github.com/"
    exit 1
fi

# === SYNC WITH MAIN ===
# git checkout main
# git pull origin main

# === BRANCH CREATION ===
read -p "Enter a new branch name: " NEW_BRANCH
if [[ -z "$NEW_BRANCH" ]]; then
    echo "❌ Branch name cannot be empty."
    exit 1
fi
git checkout -b "$NEW_BRANCH"
echo "✅ Created and switched to branch: $NEW_BRANCH"

# === CHANGE PROMPT ===
echo "Make your changes now. Press Enter when done."
read -p "Press Enter to continue..."

git status

# === COMMIT LOOP ===
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

# === OPTIONAL: ADD CODEOWNERS FILE ===
read -p "Do you want to add a CODEOWNERS file if missing? (y/n): " ADD_CODEOWNERS
if [[ "$ADD_CODEOWNERS" == "y" ]]; then
    mkdir -p .github
    CODEOWNERS_PATH=".github/CODEOWNERS"

    if [ ! -f "$CODEOWNERS_PATH" ]; then
        echo "📁 Creating CODEOWNERS file..."

        read -p "Enter default GitHub username for ownership (e.g., @shayak1109): " DEFAULT_CODEOWNER
        cat <<EOF > "$CODEOWNERS_PATH"
# Auto-assigned reviewers by GitHub
*.py ${DEFAULT_CODEOWNER}
*.sh ${DEFAULT_CODEOWNER}
README.md ${DEFAULT_CODEOWNER}
.github/** ${DEFAULT_CODEOWNER}
EOF
        git add "$CODEOWNERS_PATH"
        git commit -m "chore: add CODEOWNERS for auto-review assignments"
        echo "✅ CODEOWNERS file added and committed."
    else
        echo "✅ CODEOWNERS file already exists. Skipping."
    fi
fi

# === PUSH CHANGES ===
git push -u origin "$NEW_BRANCH"

# === PR INPUTS ===
read -p "Enter base branch for PR (e.g., main, develop): " BASE_BRANCH
read -p "Enter PR Title: " PR_TITLE
read -p "Enter PR Description: " PR_BODY
read -p "Enter reviewers (comma-separated GitHub usernames), or leave blank: " REVIEWERS

# === CREATE PR ===
if [[ -z "$REVIEWERS" ]]; then
    gh pr create --base "$BASE_BRANCH" --head "$NEW_BRANCH" --title "$PR_TITLE" --body "$PR_BODY"
else
    gh pr create --base "$BASE_BRANCH" --head "$NEW_BRANCH" --title "$PR_TITLE" --body "$PR_BODY" --reviewer "$REVIEWERS"
fi

# === SUCCESS MESSAGE ===
if [ $? -eq 0 ]; then
    echo "✅ Pull request successfully created from $NEW_BRANCH to $BASE_BRANCH."
else
    echo "❌ Failed to create pull request."
fi
