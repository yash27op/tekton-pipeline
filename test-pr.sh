#!/bin/bash
set -e

# === GLOBAL INPUTS ===
NEW_BRANCH="newest"
BASE_BRANCH="main"
PR_TITLE="title of the Pull Request"
PR_BODY="Description of a pr"
REVIEWERS="Reviewer name"
COMMIT_MSG="This is a commit message /change causing PR"

# === CHECK DEPENDENCIES ===
check_dependencies() {
    if ! command -v gh &> /dev/null; then
        echo " GitHub CLI (gh) is not installed. Install it from https://cli.github.com/"
        exit 1
    fi
}

# === CREATE NEW BRANCH ===
create_branch() {
    git checkout -b "$NEW_BRANCH"
    echo " Created and switched to branch: $NEW_BRANCH"
}

# === PROMPT FOR CHANGES ===
prompt_changes() {
    echo "🔧 Make your changes now. Press Enter when done."
    read -p "Press Enter to continue..."
    git status
}

# === COMMIT CHANGES IF ANY ===
commit_changes() {
    if [[ -n $(git status --porcelain) ]]; then
        git add .
        git commit -m "$COMMIT_MSG"
        echo " Changes committed with message: $COMMIT_MSG"
    else
        echo "⚠ No changes to commit."
    fi
}

# === PUSH BRANCH ===
push_branch() {
    git push -u origin "$NEW_BRANCH"
}

# === CREATE PR ===
create_pull_request() {
    if [[ -z "$REVIEWERS" ]]; then
        gh pr create --base "$BASE_BRANCH" --head "$NEW_BRANCH" --title "$PR_TITLE" --body "$PR_BODY"
    else
        gh pr create --base "$BASE_BRANCH" --head "$NEW_BRANCH" --title "$PR_TITLE" --body "$PR_BODY" --reviewer "$REVIEWERS"
    fi

    if [ $? -eq 0 ]; then
        echo " Pull request successfully created from $NEW_BRANCH to $BASE_BRANCH."
    else
        echo " Failed to create pull request."
    fi
}

# === MAIN SCRIPT EXECUTION ===
main() {
    check_dependencies
    create_branch
    prompt_changes
    commit_changes
    push_branch
    create_pull_request
}

main