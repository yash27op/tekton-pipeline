#!/bin/bash
set -e

#################################
# === CONFIGURATION SECTION === #
#################################

README_FILE="README.md"
PARAGRAPH="hkndc"  # Change this to whatever paragraph you want to insert
HEADING="## Features"  # Heading after which the paragraph will be inserted

#################################
# === FUNCTION DEFINITION ====  #
#################################

insert_paragraph_into_readme() {
  if [ ! -f "$README_FILE" ]; then
    echo "❌ Error: $README_FILE not found."
    exit 1
  fi

  # Backup the file
  cp "$README_FILE" "${README_FILE}.bak"
  echo "🔄 Backup created at ${README_FILE}.bak"

  # Validate input
  if [[ -z "$PARAGRAPH" ]]; then
    echo "❌ Paragraph is empty. Exiting."
    exit 1
  fi

  # Prepare insertion
  temp_file=$(mktemp)
  inserted=0

  while IFS= read -r line; do
    echo "$line" >> "$temp_file"
    if [[ $inserted -eq 0 && "$line" == *"$HEADING"* ]]; then
      echo "$PARAGRAPH" >> "$temp_file"
      inserted=1
    fi
  done < "$README_FILE"

  if [[ $inserted -eq 0 ]]; then
    echo "$PARAGRAPH" >> "$temp_file"
    echo "⚠️ Heading \"$HEADING\" not found. Paragraph appended to end of file."
  else
    echo "✅ Paragraph inserted directly after \"$HEADING\"."
  fi

  mv "$temp_file" "$README_FILE"

  # Show git diff
  echo "🔍 Git diff:"
  git diff "$README_FILE"

  # Git commit and push
  echo "💾 Committing and pushing changes to GitHub..."
  git add "$README_FILE"
  git commit -m "Update README.md: Added paragraph under '$HEADING'"
  branch=$(git rev-parse --abbrev-ref HEAD)
  git push origin "$branch"

  echo "🚀 Changes successfully pushed to GitHub branch '$branch'."
}

#################################
# === EXECUTE FUNCTION =======  #
#################################

insert_paragraph_into_readme
