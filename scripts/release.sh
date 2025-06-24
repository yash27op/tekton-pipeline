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

NEW_VERSION="4.2.3"

CATALOG_ID="a2737c18-75aa-407b-82b0-8b966e3aff22"
OFFERING_ID="64764778-25b6-4280-854f-048df4095af2"
ENV="prod"
RELEASE_NOTES_LINK="release-notes-link"
CLOUD_API=""
OFFERING_JSON="offering.json"
SERVICE_NAME="Mock-Service"
RELEASE_NOTES_LINK="release-notes-link"

CLOUD_API="https://cloud.ibm.com"
OFFERING_JSON="offering.json"
source login.sh

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

ic_login "$CLOUD_API" "$CATALOG_API_KEY"
# ibmcloud login -a "https://cloud.ibm.com" -r us-south -q --apikey "$CATALOG_API_KEY"

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

echo "state of the version is ${version_state}"

# ----------- Resolve Version If Not Supplied or Draft -----------

if [[ "$version_state" == "new" ]]; then
    echo "state of version selected is not validated draft hence taking the latest validated draft version"
    NEW_VERSION=$(jq -r '[.kinds[].versions[] | select(.state.current == "validated")] | sort_by(.version) | reverse | .[0].version' "$OFFERING_JSON")
    echo "[INFO] Resolved latest validated version: $NEW_VERSION"
elif [ -z "${NEW_VERSION:-}" ] || [ "$version_state" == "" ]; then
    echo "new-version not specified Hence taking the latest validated draft version"
    NEW_VERSION=$(jq -r '[.kinds[].versions[] | select(.state.current == "validated")] | sort_by(.version) | reverse | .[0].version' "$OFFERING_JSON")
    echo "[INFO] Resolved latest validated version: $NEW_VERSION"
else
    echo "Taking Offering version ${NEW_VERSION} Specified for Release"
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

# # ------------- Calling functions from common_functions ---------------
# source common_functions.sh

#  ------------  Calling Create_cr function to create Change request and Return CR Number -----------
CR_NUMBER=$(create_cr "${CLOUD_API}" "${CLOUD_API_KEY}" "${SERVICE_NAME}" "${NEW_VERSION}" "${RELEASE_NOTES_LINK}")
wait
#  ------------- Extract all 'flavor' variations as array elements  ------------------
CLOUD_API="https://cloud.ibm.com"
ic_login "$CLOUD_API" "$CATALOG_API_KEY"
# Fetching variations from offering.json
mapfile -t variation_array < <(jq -r '.badges[].constraints[] | select(.type == "flavor") | .rule[]' "$OFFERING_JSON")

# ------------ Initialize an empty string to store variations --------------
variations_str=""

# -------------- Iterate over the variation array and append to the string -----------
for variation in "${variation_array[@]}"; do
  variations_str+="$variation, "
done

# ------------- Remove the trailing comma and space -------------------------
variations_str="${variations_str%, }"

# Print the variations
echo "Variations present of the Version $NEW_VERSION: $variations_str"

# ----------- Calling Mark CR  Implemented function to change he state of the Change Request -------------
CLOUD_API="https://test.cloud.ibm.com"
mark_cr_implemented "$CR_NUMBER" "$CLOUD_API_KEY"
# wait
# ----------- Fetching  Version Locator from Offering.json -----------
CLOUD_API="https://cloud.ibm.com"
ic_login "$CLOUD_API" "$CATALOG_API_KEY"


# ------------ Fetch version locators for the specified version ------------------
mapfile -t VERSION_LOCATORS < <(jq -r --arg v "$NEW_VERSION" '.kinds[].versions[] | select(.version == $v) | .version_locator' "$OFFERING_JSON")

# ----- Version Locator not found in the offering.json -------
if [[ ${#VERSION_LOCATORS[@]} -eq 0 || "${VERSION_LOCATORS[0]}" == "null" ]]; then
    echo "[ERROR] version_locator not found for version $NEW_VERSION"
    exit 1
fi


# Fetch current states from offering.json and store them in an array
mapfile -t current_state_array < <(ibmcloud catalog offering get --catalog "$CATALOG_ID" --offering "$OFFERING_ID" --output json | jq -r --arg v "$NEW_VERSION" '.kinds[].versions[] | select(.version == $v) | .state.current')

# 

# Loop through the version locators and states
for index in "${!VERSION_LOCATORS[@]}"; do
    VERSION_LOCATOR="${VERSION_LOCATORS[$index]}"
    current_state="${current_state_array[$index]}"

    echo "[INFO] Found version_locator: $VERSION_LOCATOR for the version $NEW_VERSION"

    # Check if the current state is 'consumable'
    if [[ "$current_state" == "consumable" ]]; then
        echo "[INFO] Version $NEW_VERSION is already in 'consumable' state. Skipping update for version_locator: $VERSION_LOCATOR."
    else
        # Mark the version as consumable
        echo "[INFO] Marking version $NEW_VERSION Offerings variation as ready to publish (consumable)..."
        # ibmcloud catalog offering ready --version-locator "$VERSION_LOCATOR"
    fi
done

echo "[INFO] Done."

# ----------- Calling Close CR function to close the Change Request -------------
CLOUD_API="https://test.cloud.ibm.com"
close_cr "$CR_NUMBER" "$CLOUD_API_KEY"
# wait



#!/usr/bin/env bash
set -e

# To run this script:
# common_functions.sh

# ========== Script Entry Point ==========

PRG=$(basename -- "${0}")

USAGE="
usage:	${PRG}

        Prerequisites:
        IBM Cloud OSS CLI

        
        Required environment variables:
        CLOUD_API_KEY (apikey to login to IBM Test Cloud)
        
        Required arguments:
        --service-name=<service-name>
        --new-version=<new-version>
        --release-notes=<release-notes-link>
        --env=<env>
"
############################################################
# Function to create change request
#
# $1: Cloud API endpoint
# $2: IBM Cloud API key
# $3: service name
# $4: new version to release
# $5: release notes link
############################################################



# #!/usr/bin/env bash
# set -e
# set -x  # Enable tracing for debugging
# trap 'echo "[ERROR] Command failed at line $LINENO: $BASH_COMMAND"' ERR

# To run this script:
# common_functions.sh

 # ========== Script Entry Point ==========
# source login.sh
PRG=$(basename -- "${0}")

USAGE1="
usage:	${PRG}

        Prerequisites:
        IBM Cloud OSS CLI

        
        Required environment variables:
        CLOUD_API_KEY (apikey to login to IBM Test Cloud)
        
        Required arguments:
        --service-name=<service-name>
        --new-version=<new-version>
        --release-notes=<release-notes-link>
        --env=<env>
"
############################################################
# Parsing Required arguments for the common_functions.sh
############################################################

ENV="test"
for arg in "$@"; do
    if echo "${arg}" | grep -q -e --service-name=; then
        SERVICE_NAME=$(echo "${arg}" | awk -F= '{ print $2 }')
    fi
    if echo "${arg}" | grep -q -e --release-notes=; then
        RELEASE_NOTES_LINK=$(echo "${arg}" | awk -F= '{ print $2 }')
    fi
    if echo "${arg}" | grep -q -e --env; then
        ENV=$(echo "${arg}" | awk -F= '{ print $2 }')
        if [ "${ENV}" == "test" ]; then
            CLOUD_API="https://test.cloud.ibm.com"
        elif [ "${ENV}" == "prod" ]; then
            CLOUD_API="https://cloud.ibm.com"
        else
            echo "Invalid input for env. Allowed values: [test, prod]"
            exit 1
        fi
    fi
done

if [ -z "${SERVICE_NAME}" ] || [ -z "${NEW_VERSION}" ] || [ -z "${RELEASE_NOTES_LINK}" ] || [ -z "${CLOUD_API_KEY}" ]; then
  echo
  echo "One or more required arguments are missing. See usage below:"
  echo "${USAGE1}"
  exit 1
fi

############################################################
# Function to create change request
#
# $1: Cloud API endpoint
# $2: IBM Cloud API key
# $3: service name
# $4: new version to release
# $5: release notes link
############################################################

create_cr() {

    ic_test_login "$CLOUD_API" "$CLOUD_API_KEY" 1>&2

    service_name="$3"
    new_version="$4"
    release_notes_link="$5"
    backout_plan="Not Applicable"
    impact="Customers will see new version of tile:  ${new_version}"
    customer_impact="low"
    purpose="The purpose is to release a new version of the tile: ${new_version}"
    description="Mark version ${new_version} as public in catalog. Release notes: ${release_notes_link}"
    service_environment="Production"
    service_environment_detail="Production"
    deployment_method="manual"
    region="us-south"
    assigned_to="ocofaigh@ie.ibm.com"

    if [ "$(uname)" == "Darwin" ]; then
        start_date=$(date -v+1M -u +%Y-%m-%dT%H:%M:%SZ)
    else
        start_date=$(date --date='1 min' -u +%Y-%m-%dT%H:%M:%SZ)
    fi

    # cr_response=$(ibmcloud oss cr create -s "${service_name}" --backout_plan "${backout_plan}" --impact "${impact}" \
    #     --purpose "${purpose}" --description "${description}" --service_environment "${service_environment}" \
    #     --service_environment_detail "${service_environment_detail}" --customer_impact "${customer_impact}" \
    #     --deployment_method "${deployment_method}" --region "${region}" --planned_start "${start_date}" \
    #     --assigned_to "${assigned_to}" --output "json")

    cr_api_status=$?

    if [ "${cr_api_status}" != 0 ]; then
        echo "Change request creation failed.">$2
        return 1
    else
        cr_response=111345
        cr_number="$(echo "${cr_response}" | jq -r '.[].number')">&2
      
        echo " Change request ${cr_number} has been created successfully.">&2
        return ${cr_number} 
    fi
}



############################################################
# Function to mark change request as implemented
#
# $1: CR number $2: CLOUD_API_KEY
############################################################
mark_cr_implemented() {
    # local cr_number="$1"
    CLOUD_API="https://test.cloud.ibm.com"
    ic_test_login "$CLOUD_API" "$CLOUD_API_KEY"
    echo "Marking Change Request  as implemented..." >$2
    # ibmcloud oss cr start -n ${cr_number}
    if [ $? -ne 0 ]; then
        echo " Failed to mark CR  as implemented." >$2
        # return 1
        exit
    fi
    echo "Change Request ${1} marked as implemented.">$2
    wait
}


############################################################
# Function to close the change request
#
# $1: CR number $2: CLOUD_API_KEY
############################################################
close_cr() {
    # local cr_number="$1"
    CLOUD_API="https://test.cloud.ibm.com"
    ic_test_login "$CLOUD_API" "$CLOUD_API_KEY"
    echo "Closing CR ${1}...">$2
    # ibmcloud oss cr close -n ${cr_number} --notes "published successfully" 
    if [ $? -ne 0 ]; then
        echo " Failed to close CR ${1}.">$2
        # return 1
        exit
    fi
    echo " CR ${1} closed successfully.">$2
    wait
}

ic_login() {
    # Use direct unbuffered output to stderr (>&2)
    # Timestamps help in pipeline logs
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Attempting login to production" >&2
    
    # Capture both stdout and stderr from ibmcloud command
    response=$(ibmcloud login -a "$1" -r us-south -q --apikey "$2" 2>&1)
    login_status=$?

    if [ "${login_status}" != 0 ]; then
        echo "[ERROR] Login failed" >&2
        echo "${response}" >&2
        return 1
    fi
    echo "[SUCCESS] Login completed" >&2
}

ic_test_login() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Attempting login to test environment" >&2
    
    response=$(ibmcloud login -a "$1" -r us-south -q --apikey "$2" 2>&1)
    login_status=$?

    if [ "${login_status}" != 0 ]; then
        echo "[ERROR] Test login failed" >&2
        echo "${response}" >&2
        return 1
    fi
    echo "[SUCCESS] Test login completed" >&2
}
