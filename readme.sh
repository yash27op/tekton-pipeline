#!/bin/bash
set -e

###################################### INPUT VARIABLES #######################################

README_FILE="README.md"
PARAGRAPH="Scrum is a discussion or meeting where everyone gives their updates and help to track"
HEADING="Features"

################################# FUNCTION DEFINITION #######################################

insert_paragraph_into_readme() {
  if [ ! -f "$README_FILE" ]; then
    echo "❌ Error: $README_FILE not found."
    exit 1
  fi

  # Backup the file
  cp "$README_FILE" "${README_FILE}.bak"
  echo "✅ Backup created at ${README_FILE}.bak"

  if [[ -z "$PARAGRAPH" ]]; then
    echo "❌ Paragraph is empty. Exiting."
    exit 1
  fi

  temp_file=$(mktemp)
  inserted=0

  while IFS= read -r line; do
    echo "$line" >> "$temp_file"

    if [[ $inserted -eq 0 ]]; then
      # Clean markdown formatting from heading line for comparison
      clean_line=$(echo "$line" | sed 's/[#*`>-]//g' | xargs)

      # Compare after converting both to lowercase
      if [[ "${clean_line,,}" == "${HEADING,,}" ]]; then
        echo -e "\n$PARAGRAPH" >> "$temp_file"
        inserted=1
      fi
    fi
  done < "$README_FILE"

  if [[ $inserted -eq 0 ]]; then
    echo -e "\n$PARAGRAPH" >> "$temp_file"
    echo "⚠️ Heading \"$HEADING\" not found. Paragraph appended to end of file."
  else
    echo "✅ Paragraph inserted directly after \"$HEADING\"."
  fi

  mv "$temp_file" "$README_FILE"

  echo "🔍 Git diff:"
  git diff "$README_FILE"

  echo "📤 Committing and pushing changes to GitHub..."
  git add "$README_FILE"
  git commit -m "Update README.md: Added paragraph under '$HEADING'"
  branch=$(git rev-parse --abbrev-ref HEAD)
  git push origin "$branch"
  echo "🚀 Changes successfully pushed to GitHub branch '$branch'."
}

################################# EXECUTE FUNCTION CALL ##########################################

insert_paragraph_into_readme
