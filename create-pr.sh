#!/bin/bash
set -e

###################################### INPUT VARIABLES #######################################

README_FILE="README.md"
PARAGRAPH="Scrum is a discussion or meeting where "  # Change this to whatever paragraph you want to insert
HEADING="## Features"  # Heading under which the paragraph will be inserted

################################# FUNCTION DEFINITION #######################################

insert_paragraph_into_readme() {
  if [ ! -f "$README_FILE" ]; then
    echo "Error: $README_FILE not found."
    exit 1
  fi

  # Backup the file
  cp "$README_FILE" "${README_FILE}.bak"
  echo "Backup created at ${README_FILE}.bak"

  # Validate input
  if [[ -z "$PARAGRAPH" ]]; then
    echo "Paragraph is empty. Exiting."
    exit 1
  fi

  # Detect formatting style under the heading
  formatting_style="paragraph"  # default
  temp_style_file=$(mktemp)
  
  # Extract content under the heading
  awk -v heading="$HEADING" '
    $0 ~ heading {found=1; next}
    found && /^##/ {exit}  # Stop at next heading
    found {print}
  ' "$README_FILE" > "$temp_style_file"

  # Analyze formatting style
  if grep -q '^[*-] ' "$temp_style_file"; then
    formatting_style="bullet"
  elif grep -q '^[0-9]\. ' "$temp_style_file"; then
    formatting_style="numbered"
  fi

  # Prepare the paragraph in correct format
  case "$formatting_style" in
    "bullet")
      formatted_paragraph="- $PARAGRAPH"
      ;;
    "numbered")
      # Count existing numbered items
      item_count=$(grep -c '^[0-9]\. ' "$temp_style_file")
      ((item_count++))
      formatted_paragraph="$item_count. $PARAGRAPH"
      ;;
    *)
      formatted_paragraph="$PARAGRAPH"
      ;;
  esac

  # Insert the formatted paragraph
  temp_file=$(mktemp)
  inserted=0
  in_section=0

  while IFS= read -r line; do
    echo "$line" >> "$temp_file"
    
    if [[ "$line" == *"$HEADING"* ]]; then
      in_section=1
    elif [[ $in_section -eq 1 && $inserted -eq 0 ]]; then
      # Check if we've reached the end of the section content
      if [[ "$line" == "" || "$line" =~ ^## ]]; then
        echo "$formatted_paragraph" >> "$temp_file"
        echo "" >> "$temp_file"
        inserted=1
      fi
    fi
  done < "$README_FILE"

  # If heading wasn't found or section was empty, append at end
  if [[ $inserted -eq 0 ]]; then
    echo "" >> "$temp_file"
    echo "$HEADING" >> "$temp_file"
    echo "$formatted_paragraph" >> "$temp_file"
    echo " Heading \"$HEADING\" not found. Section created at end of file."
  else
    echo " Paragraph inserted under \"$HEADING\" in $formatting_style format."
  fi

  mv "$temp_file" "$README_FILE"
  rm "$temp_style_file"

  # Show git diff
  echo "🔍 Git diff:"
  git diff "$README_FILE"

  # Git commit and push
  echo " Committing and pushing changes to GitHub..."
  git add "$README_FILE"
  git commit -m "Update README.md: Added content under '$HEADING'"
  branch=$(git rev-parse --abbrev-ref HEAD)
  git push origin "$branch"

  echo " Changes successfully pushed to GitHub branch '$branch'."
}

################################# EXECUTE FUNCTION CALL ##########################################

insert_paragraph_into_readme