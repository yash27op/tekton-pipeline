

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

SERVICE_NAME="Mock-Service"
RELEASE_NOTES_LINK="release-notes-link"
CLOUD_API_KEY="2uHb_WvwVe327txjaPudvtIwWrgYeSE4HVs_ogKce9Hv"
create_cr() {
    
    echo "Logging to  Test.Cloud.IBM ..."
    # response=ic_login "$CLOUD_API" "${CLOUD_API_KEY}"
    response=$(ibmcloud login -a "$1" -r us-south -q --apikey "$2")
    login_status=$?

    if [ "${login_status}" != 0 ]; then
        echo "Login to ibmcloud failed."
        echo "${response}"
        return 1
    fi
    echo "Login to test cloud successful."

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
        echo "Change request creation failed."
        return 1
    else
        cr_number="$(echo "${cr_response}" | jq -r '.[].number')"
        echo " Change request ${cr_number} has been created successfully."
        return ${cr_number}
    fi
}


apikey="${CLOUD_API_KEY}"

if [ -z "${apikey}" ]; then
  echo
  echo "API key to login to IBM Cloud is not defined. See usage below:"
  echo "${USAGE}"
  exit 1
fi
ENV="test"
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

if [ -z "${SERVICE_NAME}" ] || [ -z "${NEW_VERSION}" ] || [ -z "${RELEASE_NOTES_LINK}" ] || [ -z "${CLOUD_API_KEY}" ]; then
  echo
  echo "One or more required arguments are missing. See usage below:"
  echo "${USAGE}"
  exit 1
fi

############################################################
# Function to mark change request as implemented
#
# $1: CR number
############################################################
mark_cr_implemented() {
    # local cr_number="$1"

    echo "Marking Change Request ${1} as implemented..."
    ibmcloud oss cr start -n ${cr_number}
    if [ $? -ne 0 ]; then
        echo " Failed to mark CR ${1} as implemented."
        # return 1
        exit
    fi
    echo " Change Request ${1} marked as implemented."
}


############################################################
# Function to close the change request
#
# $1: CR number
############################################################
close_cr() {
    # local cr_number="$1"

    echo "Closing CR ${1}..."
    # ibmcloud oss cr close -n ${cr_number} --notes "published successfully" 
    if [ $? -ne 0 ]; then
        echo " Failed to close CR ${1}."
        # return 1
        exit
    fi
    echo " CR ${1} closed successfully."
}



# Function to log into IBM Cloud
ic_login() {
    if [ "${ENV}" == "test" ]; then
       CLOUD_API="https://test.cloud.ibm.com"
    elif [ "${ENV}" == "prod" ]; then
       CLOUD_API="https://cloud.ibm.com"
    else
       echo "Invalid input for env. Allowed values: [test, prod]"
       exit 1
    fi
    ibmcloud login -a "$1" -r us-south -q --apikey "$2"
    }

    
