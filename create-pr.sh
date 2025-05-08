#!/bin/bash
set -e

###################################### INPUT VARIABLES #######################################

REPO_URL="https://github.com/yash27op/tekton-pipeline"
README_FILE="README.md"
PARAGRAPH="Scrum is a discussion or meeting where everyone gives their updates and help to track"
HEADING="# Project Title"

###################################### FUNCTION ###############################################

insert_paragraph_into_readme() {
  REPO_NAME=$(basename "$REPO_URL" .git)

  if [ ! -d "$REPO_NAME" ]; then
    echo "Cloning repository $REPO_URL..."
    git clone "$REPO_URL" "$REPO_NAME"
    cd "$REPO_NAME"
  else
    echo "Using existing repository directory: $REPO_NAME"
    cd "$REPO_NAME"
    git pull origin main
  fi

  if [ ! -f "$README_FILE" ]; then
    echo "Error: $README_FILE not found in repository."
    exit 1
  fi

  cp "$README_FILE" "${README_FILE}.bak"
  echo "Backup created at ${README_FILE}.bak"

  if [[ -z "$PARAGRAPH" ]]; then
    echo "Paragraph is empty. Exiting."
    exit 1
  fi

  temp_section_file=$(mktemp)
  awk -v heading="$HEADING" '
    $0 ~ heading {found=1; next}
    found && /^#/ {exit}
    found {print}
  ' "$README_FILE" > "$temp_section_file"

  if grep -q '^[*-] ' "$temp_section_file"; then
    formatting_style="bullet"
  elif grep -q '^[0-9]\. ' "$temp_section_file"; then
    formatting_style="numbered"
  else
    formatting_style="paragraph"
  fi

  case "$formatting_style" in
    bullet)
      formatted_paragraph="- $PARAGRAPH"
      ;;
    numbered)
      count=$(grep -c '^[0-9]\. ' "$temp_section_file")
      formatted_paragraph="$((count + 1)). $PARAGRAPH"
      ;;
    *)
      formatted_paragraph="$PARAGRAPH"
      ;;
  esac

  temp_output=$(mktemp)
  in_section=0
  inserted=0

  while IFS= read -r line; do
    echo "$line" >> "$temp_output"
    if [[ "$line" == "$HEADING" ]]; then
      in_section=1
      continue
    fi
    if [[ $in_section -eq 1 && "$line" =~ ^# ]]; then
      echo "$formatted_paragraph" >> "$temp_output"
      inserted=1
      in_section=0
    fi
  done < "$README_FILE"

  if [[ $inserted -eq 0 && $in_section -eq 1 ]]; then
    echo "$formatted_paragraph" >> "$temp_output"
    inserted=1
  fi

  if [[ $inserted -eq 0 ]]; then
    echo "" >> "$temp_output"
    echo "$HEADING" >> "$temp_output"
    echo "$formatted_paragraph" >> "$temp_output"
    echo "Heading \"$HEADING\" not found. Section created at end of file."
  else
    echo "Paragraph inserted under \"$HEADING\" in $formatting_style format."
  fi

  mv "$temp_output" "$README_FILE"
  rm "$temp_section_file"

  echo "Showing diff:"
  git diff "$README_FILE"

  git add "$README_FILE"
  git commit -m "docs: updated $README_FILE - appended under '$HEADING'"
  branch=$(git rev-parse --abbrev-ref HEAD)
  git push origin "$branch"

  echo "Changes pushed to $REPO_URL (branch: $branch)"
}

################################# EXECUTE #######################################################

insert_paragraph_into_readme
