#!/usr/bin/env bash
set -e

# To run this script:
# Required environment variables:
#       CLOUD_API_KEY to login to IBM Cloud
#
# Required arguments:
#        --service-name=<service-name>
#        --new-version=<new-version>
#        --release-notes=<release-notes-link>
#        --env=<env>


############################################################
# Function to mark change request as implemented
#
# $1: CR number
############################################################
mark_cr_implemented() {
    local cr_number="$1"

    echo "Marking CR ${cr_number} as implemented..."
    implement_response=$(ibmcloud oss cr update --cr "${cr_number}" --implemented true --output json)
    if [ $? -ne 0 ]; then
        echo " Failed to mark CR ${cr_number} as implemented."
        return 1
    fi
    echo " CR ${cr_number} marked as implemented."
}

############################################################
# Function to close the change request
#
# $1: CR number
############################################################
close_cr() {
    local cr_number="$1"

    echo "Closing CR ${cr_number}..."
    close_response=$(ibmcloud oss cr close --cr "${cr_number}" --output json)
    if [ $? -ne 0 ]; then
        echo " Failed to close CR ${cr_number}."
        return 1
    fi
    echo "k CR ${cr_number} closed successfully."
}

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

    echo "Logging to Cloud..."
    response=$(ibmcloud login -a "$1" -r us-south -q --apikey "$2")
    login_status=$?

    if [ "${login_status}" != 0 ]; then
        echo "Login to ibmcloud failed."
        echo "${response}"
        return 1
    fi
    echo "Login to ibmcloud successful."

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

    cr_response=$(ibmcloud oss cr create -s "${service_name}" --backout_plan "${backout_plan}" --impact "${impact}" \
        --purpose "${purpose}" --description "${description}" --service_environment "${service_environment}" \
        --service_environment_detail "${service_environment_detail}" --customer_impact "${customer_impact}" \
        --deployment_method "${deployment_method}" --region "${region}" --planned_start "${start_date}" \
        --assigned_to "${assigned_to}" --output "json")

    cr_api_status=$?

    if [ "${cr_api_status}" != 0 ]; then
        echo "Change request creation failed."
        return 1
    else
        cr_number="$(echo "${cr_response}" | jq -r '.[].number')"
        echo " Change request ${cr_number} has been created successfully."

        # Mark as implemented and close
        mark_cr_implemented "${cr_number}" || exit 1
        close_cr "${cr_number}" || exit 1
    fi
}


# ========== Script Entry Point ==========

PRG=$(basename -- "${0}")

USAGE="
usage:	${PRG}

        Required environment variables:
        CLOUD_API_KEY (apikey to login to IBM Cloud)

        Required arguments:
        --service-name=<service-name>
        --new-version=<new-version>
        --release-notes=<release-notes-link>
        --env=<env>
"

apikey="${CLOUD_API_KEY}"

if [ -z "${apikey}" ]; then
  echo
  echo "API key to login to IBM Cloud is not defined. See usage below:"
  echo "${USAGE}"
  exit 1
fi

for arg in "$@"; do
    if echo "${arg}" | grep -q -e --service-name=; then
        SERVICE_NAME=$(echo "${arg}" | awk -F= '{ print $2 }')
    fi
    if echo "${arg}" | grep -q -e --new-version=; then
        NEW_VERSION=$(echo "${arg}" | awk -F= '{ print $2 }')
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

if [ -z "${SERVICE_NAME}" ] || [ -z "${NEW_VERSION}" ] || [ -z "${RELEASE_NOTES_LINK}" ] || [ -z "${CLOUD_API}" ]; then
  echo
  echo "One or more required arguments are missing. See usage below:"
  echo "${USAGE}"
  exit 1
fi

# Run full CR lifecycle
create_cr "${CLOUD_API}" "${apikey}" "${SERVICE_NAME}" "${NEW_VERSION}" "${RELEASE_NOTES_LINK}"
