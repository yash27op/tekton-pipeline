#!/bin/bash
set -e

readme_file="README.md"

# Check if README exists
if [ ! -f "$readme_file" ]; then
  echo "❌ Error: $readme_file not found."
  exit 1
fi

# Backup
cp "$readme_file" "${readme_file}.bak"
echo "🔄 Backup created at ${readme_file}.bak"

# Ask for single-line paragraph input (no CTRL+D)
echo "📝 Enter the paragraph to insert:"
read -r paragraph

# Validate input
if [[ -z "$paragraph" ]]; then
  echo "❌ No input provided. Exiting."
  exit 1
fi

# Ask for heading to insert under
echo "📌 Enter the heading after which to insert this (e.g., ## Features):"
read -r heading

# Insert paragraph after heading, fallback to end if not found
temp_file=$(mktemp)
inserted=0

while IFS= read -r line; do
  echo "$line" >> "$temp_file"
  if [[ $inserted -eq 0 && "$line" == *"$heading"* ]]; then
    echo "$paragraph" >> "$temp_file"
    inserted=1
  fi
done < "$readme_file"

if [[ $inserted -eq 0 ]]; then
  echo "$paragraph" >> "$temp_file"
  echo "⚠️ Heading \"$heading\" not found. Paragraph appended to end of file."
else
  echo "✅ Paragraph inserted directly after \"$heading\"."
fi

mv "$temp_file" "$readme_file"

# Show changes
echo "🔍 Git diff:"
git diff "$readme_file"

# Git commit and push
echo "💾 Committing and pushing changes to GitHub..."
git add "$readme_file"
git commit -m "Update README.md: Added paragraph under '$heading'"
branch=$(git rev-parse --abbrev-ref HEAD)
git push origin "$branch"

echo "🚀 Changes successfully pushed to GitHub branch '$branch'."
