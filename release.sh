#!/bin/bash
set -euo pipefail

# === CONFIGURATION ===
REPO="your-username/your-repo"        # <-- Replace this
README_FILE="README.md"
NEW_TAG="v$(date +%Y%m%d%H%M)"
COMMIT_MESSAGE="Interactive README update for $NEW_TAG"
TARGET_HEADING="## Features"

# === ASK FOR PARAGRAPH (Supports Multi-line) ===
echo "📝 Enter the paragraph you want to insert under '$TARGET_HEADING' in README.md."
echo "(Press CTRL+D when you're done typing)"

NEW_PARAGRAPH=$(</dev/stdin)

# === VALIDATE INPUT ===
if [[ -z "$NEW_PARAGRAPH" ]]; then
  echo "❌ No paragraph entered. Exiting."
  exit 1
fi

# === BACKUP AND MODIFY README.md ===
echo "🔧 Inserting your paragraph into $README_FILE..."
TEMP_FILE=$(mktemp)

awk -v insert="$NEW_PARAGRAPH" -v heading="$TARGET_HEADING" '
BEGIN {
  added = 0
}
{
  print
  if ($0 ~ heading && !added) {
    print ""
    n = split(insert, lines, "\n")
    for (i = 1; i <= n; i++) {
      print lines[i]
    }
    print ""
    added = 1
  }
}' "$README_FILE" > "$TEMP_FILE" && mv "$TEMP_FILE" "$README_FILE"

# === COMMIT ONLY README.md ===
echo "💾 Committing README changes..."
git add "$README_FILE"
git commit -m "$COMMIT_MESSAGE"
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
git push origin "$CURRENT_BRANCH"

# === TAG AND PUSH ===
echo "🏷️  Tagging release: $NEW_TAG"
git tag "$NEW_TAG"
git push origin "$NEW_TAG"

# === GENERATE RELEASE NOTES ===
echo "🧾 Generating release notes..."
LAST_TAG=$(git describe --tags --abbrev=0 --exclude "$NEW_TAG" 2>/dev/null || echo "")
if [[ -z "$LAST_TAG" ]]; then
  echo "Initial release. Full README.md contents:" > release_notes.md
  echo -e "\n\`\`\`markdown\n$(cat $README_FILE)\n\`\`\`" >> release_notes.md
else
  echo "Changes in $README_FILE since $LAST_TAG:" > release_notes.md
  echo -e "\n\`\`\`diff\n$(git diff "$LAST_TAG"..HEAD -- $README_FILE)\n\`\`\`" >> release_notes.md
fi

# === CREATE RELEASE ===
echo "🚀 Creating GitHub release..."
gh release create "$NEW_TAG" \
  --repo "$REPO" \
  --title "README Update - $NEW_TAG" \
  --notes-file release_notes.md

echo "✅ Success! Paragraph added, committed, tagged, and released as $NEW_TAG."
