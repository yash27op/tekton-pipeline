#! /bin/bash

set -euo pipefail

PRG=$(basename -- "${0}")

USAGE="
usage:	${PRG}
        [--help]

        Prerequsites:
        - git
        - curl
        - jq
        - ibmcloud  oss CLI
        - ibmcloud catalog CLI plugin

        Required environment variables:
        CLOUD_API_KEY  (api key used for creating chnage_request via oss cli)
        CATALOG_API_KEY  (apikey with access to the catalog)
        PIPELINE_RUN_URL (url of pipeline run to refer in github issues)

        Required arguments:
        --release_notes_link=<release-notes-link>
        --catalog_id=<catalog-id>
        --offering_id=<offering-id>
        --env=<env>
        
        Optional arguments:
         --new_version=<new-version>  (if no value passed, the current latest git release tag will be used.)

"

# set -x  # Enable tracing for debugging
# trap 'echo "[ERROR] Command failed at line $LINENO: $BASH_COMMAND"' ERR

###############################################################################
# Script: release.sh
# Description:
#   - Parses parameters and environment
#   - Clones GitHub repo
#   - Extracts catalog & offering info
#   - Creates CR via change_request.sh
#   - Marks version as ready (if enabled)
#   - Marks CR as implemented & closes it
#
# Required ENV:
#   CLOUD_API_KEY  - API Key for ibm oss cli
#   CATALOG_API_KEY - IBM CLoud CATALOG Access API KEY
###############################################################################
# GLOBAL VARIABLES
ibmcloud plugin repo-add "IBM Cloud Internal" https://plugins.test.cloud.ibm.com
ibmcloud plugin install oss-tooling -r "IBM Cloud Internal"
NEW_VERSION="4.2.1"
CATALOG_API_KEY="t60qBADWvR2Nie72tJYV6vLBAquIPxw488g3Q2Ys8UFi"
CATALOG_ID="62a8fa8f-9894-417d-987b-8f7b9ff5b8e7"
OFFERING_ID="3f991bfe-9752-49db-ac17-ce5522d42009"
ENV="prod"
RELEASE_NOTES_LINK="release-notes-link"
CLOUD_API=""
OFFERING_JSON="offering.json"

#Calling functions from common_functions
source common_functions.sh

# ----------- Parse CLI Arguments -----------
for arg in "$@"; do
  set +e
  found_match=false

  if echo "${arg}" | grep -q -e --new-version=; then
    NEW_VERSION=$(echo "${arg}" | awk -F= '{ print $2 }')
    # found_match=true # to keep scope for possibility of version not provided
  fi
  if echo "${arg}" | grep -q -e --release-notes-link=; then
    RELEASE_NOTES_LINK=$(echo "${arg}" | awk -F= '{ print $2 }')
    found_match=true
  fi
  if echo "${arg}" | grep -q -e --env=; then
    ENV=$(echo "${arg}" | awk -F= '{ print $2 }')
    found_match=true
  fi
  if echo "${arg}" | grep -q -e --service_name=; then
    SERVICE_NAME=$(echo "${arg}" | awk -F= '{ print $2 }')
    found_match=true
  fi
  if echo "${arg}" | grep -q -e --catalog-id=; then
    CATALOG_ID=$(echo "${arg}" | awk -F= '{ print $2 }')
    found_match=true
  fi
  if echo "${arg}" | grep -q -e --offering-id=; then
    OFFERING_ID=$(echo "${arg}" | awk -F= '{ print $2 }')
    found_match=true
  fi
  if [ "${found_match}" = false ]; then
    if [ "${arg}" != "--help" ]; then
      echo "[ERROR] Unknown command line argument: ${arg}"
    fi
    echo "${USAGE}"  
    exit 1
  fi
  set -e
done


# ------  Verify required arguments are set  -----------
if [ -z "${RELEASE_NOTES_LINK}" ]; then
  echo "[ERROR] Missing value for required argument --release-notes-link"
  exit 1
fi
if [ -z "${CATALOG_ID}" ]; then
  echo "[ERROR] Missing value for required argument --catalog-id"
  exit 1
fi
if [ -z "${OFFERING_ID}" ]; then
  echo "[ERROR] Missing value for required argument --offering-id"
  exit 1
fi
if [ -z "${ENV}" ]; then
  echo "[ERROR] Missing value for required argument --env"
  exit 1
fi

# ------ Checking for optional Parameter NEW-VERSION ------
if [ -z "${NEW_VERSION}" ]; then
  NEW_VERSION="${1:-}" #
  echo "new-version (when not specified): ${NEW_VERSION}"
else
  echo "new-version: ${NEW_VERSION}"
fi

# ------- Parsed Parameters via Pipeline -----------
echo "new-version: ${NEW_VERSION} , RELEASE_NOTES_LINK: ${RELEASE_NOTES_LINK} , CATALOG_ID: ${CATALOG_ID} , OFFERING_ID: ${OFFERING_ID} , ENV: ${ENV}  "


# ----------- Defaults -----------
WORKDIR="$(mktemp -d)"

OFFERING_JSON="$WORKDIR/offering.json"

# # --- IBM Cloud Catalog Login ---
echo "[INFO] Logging into IBM Cloud..."

# ic_login "$CLOUD_API" "$CATALOG_API_KEY"
ibmcloud login -a "https://cloud.ibm.com" -r us-south -q --apikey "$CATALOG_API_KEY"

 # ----------- Fetch Offering JSON -----------
ibmcloud catalog offering get --catalog "$CATALOG_ID" --offering "$OFFERING_ID" --output json >"$OFFERING_JSON"

# ----------- Extract Offering Metadata -----------
OFFERING_NAME=$( jq -r '.name' "$OFFERING_JSON")
echo "[INFO] Detected offering name: $OFFERING_NAME"

KIND=$(jq -r '.product_kind' "$OFFERING_JSON")
echo "[INFO] Detected offering kind: $KIND"

# -------- Checking Kind Resource Type ---------
if [[ "$KIND" == "solution" ]]; then
    variation_array_name="variations"
else
    variation_array_name="examples"
fi

# ---- Checking CATALOG_ID and OFFERING_ID ----------
echo "[INFO]  catalog_id: $CATALOG_ID"
echo "[INFO]  offering_id: $OFFERING_ID"

# -------- Fetch Offering JSON Metadata -------------
echo "[INFO] Fetching offering metadata JSON..."

# ----------- Extracting the current state of the Offering Version under release ----------------------------
version_state=$(jq -r --arg v "$NEW_VERSION" '.kinds[].versions[] | select(.version == $v) | .state.current' "$OFFERING_JSON")


# ----------- Resolve Version If Not Supplied or Draft -----------

if [[ -z "${NEW_VERSION:-}" || "$version_state" == "new" ]]; then
    echo "state of the version is ${version_state}"
    echo "new-version not specified Hence taking the latest validated draft version"
    NEW_VERSION=$(jq -r '[.kinds[].versions[] | select(.state.current == "validated")] | sort_by(.version) | reverse | .[0].version' "$OFFERING_JSON")
    echo "[INFO] Resolved latest validated version: $NEW_VERSION"
fi

# ------- ENV based the External Service Requirement [prod/test] -------
ENV="test"

# --------- Cloud API Endpoint ----------
if [ "${ENV}" == "test" ]; then
    CLOUD_API="https://test.cloud.ibm.com"
elif [ "${ENV}" == "prod" ]; then
    CLOUD_API="https://cloud.ibm.com"
else
     echo "Invalid input for env. Allowed values: [test, prod]"
exit 1
fi

#  ----------  Calling Create_cr function to create Change request and Return CR Number -----------
CR_NUMBER=$(create_cr "${CLOUD_API}" "${CLOUD_API_KEY}" "${SERVICE_NAME}" "${NEW_VERSION}" "${RELEASE_NOTES_LINK}")

#  ----------- Extract all 'flavor' variations as array elements  ------------------
# Create an empty array
variation_array=()

# Loop through the output of jq and add each item to the array
while IFS= read -r line; do
    variation_array+=("$line")
done < <(jq -r '.badges[].constraints[] | select(.type == "flavor") | .rule[]' "$OFFERING_JSON")

# Example to show the content of the array
for item in "${variation_array[@]}"; do
    echo "$item"
done



# #   --------  Iterate over the variation array  -------- 
# for variation in "${variation_array[@]}"; do
#   echo "Variations present of the Version $NEW_VERSION : $variation"
# done

# ----------- Calling Mark CR  Implemented function to change he state of the Change Request -------------
mark_cr_implemented "$CR_NUMBER"

# ----------- Fetching  Version Locator from Offering.json -----------
VERSION_LOCATORS=$(jq -r --arg v "$NEW_VERSION" '.kinds[].versions[] | select(.version == $v) | .version_locator' "$OFFERING_JSON")

# -----  Version Locator not found in the offering.json -------
if [[ -z "$VERSION_LOCATORS" || "$VERSION_LOCATORS" == "null" ]]; then
    echo "[ERROR] version_locator not found for version $NEW_VERSION"
    exit 1
fi

# ---- Marking each Version locator of variations of version to Ready State ------
for VERSION_LOCATOR in $VERSION_LOCATORS; do
    echo "[INFO] Found version_locator: $VERSION_LOCATOR for the version $NEW_VERSION"
    echo "[INFO] Marking version $NEW_VERSION Offerings as ready to publish (consumable)..."
    ibmcloud catalog offering ready --version-locator $VERSION_LOCATOR
done

# --------- Checking the New State of the Version ---------- 
NEW_STATE=$(ibmcloud catalog offering get --catalog "$CATALOG_ID" --offering "$OFFERING_ID" --output json | jq -r --arg v "$NEW_VERSION" '.kinds[].versions[] | select(.version == $v) | .state.current')
echo "[INFO] Updated version state: $NEW_STATE"
if [[ "$NEW_STATE" == "consumable" ]]; then
    echo "[SUCCESS] Version $NEW_VERSION is now ready to publish."
else
    echo "[ERROR] Failed to update version $NEW_VERSION to consumable. Current state: $NEW_STATE"
    exit 1
fi
    
echo "[INFO] Done."

# ----------- Calling Close CR function to close the Change Request -------------
close_cr "$CR_NUMBER"



