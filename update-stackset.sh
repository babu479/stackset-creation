#!/bin/bash

#usage : ./stackSet-deploy-script.sh --app-name APP_NAME --stackSet-name STACKSET_NAME --target-accounts TARGET_ACCOUNTS --regions REGIONS --template-file TEMPLATE_FILE --parameter-file PARAMETER_FILE  --profile PROFILE --create-stackset --create-stackInstance

#parse command line arguments
cblack='\033[0;30m'        #black
cred='\033[0;31m'          # Red
cgreen='\033[0;32m'        # Green
cyellow='\033[0;33m'       # Yellow
cblue='\033[0;34m'         # Blue
cpurple='\033[0;35m'       # Purple
ccyan='\033[0;36m'         # Cyan
cwhite='\033[0;37m'        # White
creset='\033[0m'           # Reset

ls

Config_file="$(cat scripts/config.json)"

create_stackset=false
create_stackInstace=false

while [[ $# -gt 0 ]]; do
    case $1 in
    --app-name)
    app_name="$2"
    shift 2
    ;;
    --stackSet-name)
    stackSet_name="$2"
    shift 2
    ;;
    --target-accounts)
    shift 1
    while [[ $# -gt 0 && "$1" != --* ]]; do
       target_accounts+=("$1")
       shift 1
       done
       ;;
    --regions)
    shift 1
    while [[ $# -gt 0 && "$1" != --* ]]; do
    regions+=("$1")
    shift 1
    done
    ;;
    --template-file)
    template_file="cloudformation/$2"
    shift 2
    ;;
    --parameter-file)
    parameter_file="$2"
    shift 2
    ;;
    --profile)
    profile="$2"
    shift 2
    ;;
    --update-stackset)
    update_stackset=true
    shift 1
    ;;
    --detect-drift)
    detect_drift=true
    shift 1
    ;;
*)
  echo "Unknown option: $1">&2
  exit 1
  ;;
  esac
  done

  echo "The value of app_name is: $app_name"
  echo "The value of target_accounts is: ${target_accounts[@]}"
  echo "The value of stackSet_name is: $stackSet_name"
  echo "The value of template_file is: $template_file"
  echo "The value of parameter_file is: $parameter_file"
  echo "The value of regions is: ${regions[@]}"
  echo "The value of profile is: ${profile}"


if [ -z "$stackSet_name" ] || [ -z "$template_file" ] || [ -z "$parameter_file" ] || [ -z "$regions" ] || [ -z "$profile" ];then
  echo -e "\033[0;33m\nMissing Required arguments. usage: ./stackSet-deploy-script.sh --app-name APP_NAME --stackSet-name STACKSET_NAME --target-accounts TARGET_ACCOUNTS --regions REGIONS --template-file TEMPLATE_FILE --parameter-file PARAMETER_FILE  --profile PROFILE --create-stackset --create-stackInstance"
exit 128
fi

######################################################################################################################
stackSet_name=$(echo "${stackSet_name}")
if [ -f "cfn-parameters/$parameter_file" ]; then
  echo -e "${ccyan}Parameter file exists${creset}"
else
 echo -e "${cred}Parameter file is missing in cfn-parameters/$parameter_file${creset}"
 exit 1
fi


update_stackset() {
    local stackSet_name=$1
    local template_file=$2
    local parameter_file=$3
    local region=$4


  local parameters_file="cfn-parameters/${ACCOUNT}-${REGION}-${parameter_file}"
  cp -r  "cfn-parameters/$parameter_file" "$parameter_file"
  cp -r "cfn-parameters/$parameter_file" "${ACCOUNT}"-"${REGION}"-update_parameter_file


#check if the stackset exists

if ! aws cloudformation describe-stack-set --stack-set-name "${stackSet_name}" --region "${region}">/dev/null 2>&1; then
    #Create the stackset if it doesn't exist
  echo -e "${ccyan}StackSet ${stackSet_name} doesn't exists in ${region}. Please proceed  to use create stackset job to create${creset}"
  exit 1

else
    echo -e "${ccyan}StackSet ${stackSet_name} already exists in ${region}. proceeding to update stackset${creset}"

    UPDATE_ID=$(aws cloudformation update-stack-set --stack-set-name "${stackSet_name}" --template-body "file://${template_file}" --parameters "file://${ACCOUNT}-${REGION}-update_parameter_file" --region "${region}"|jq -r '.OperationId')

    echo -e "${cpurple}OperationID:$UPDATE_ID${creset}"


    local UPDATE_DETAILS=$(aws cloudformation describe-stack-set-operation \
                           --stack-set-name "${stackSet_name}" \
                           --operation-id "${UPDATE_ID}" \
                           --region "${region}")

    local UPDATE_STATUS=$(echo "${UPDATE_DETAILS}"|jq -r '.StackSetOperation.Status')

    error_post=false
    count=0

    until [ $UPDATE_STATUS == "SUCCEEDED" ] || [ $error_post == "true" ] || [ $count -gt 15 ];
    do
       local update_stackset_details=$(aws cloudformation describe-stack-set-operation --stack-set-name "${stackSet_name}" --operation-id "${UPDATE_ID}" --region "${region}")

        local update_stackset_status=$(echo $update_stackset_details|jq -r '.StackSetOperation.Status')
        if [ $update_stackset_status == "RUNNING" ] && [ $error_post == "false" ];
        then
        echo -e "${ccyan}StackSet update is running. wait for to finish the update${creset}"
        sleep 10
        echo -n '.'
        count=$((count + 1))
        elif [ $update_stackset_status == "FAILED" ] && [ $error_post == "false" ];
        then
        echo -e "${cred} Error: Stack Set update failed. Please Check logs ${creset}"
        update_stackset_error=$(echo $update_stackset_details|jq -r '.StackSetOperation.Status')
        echo -e "${update_stackset_details}${creset}"
        error_post=true
        exit 1
        fi

      if [ "${UPDATE_STATUS}" == "SUCCEEDED" ]; then
          local STACK_SET_DETAILS=$(aws cloudformation describe-stack-set \
                                    --stack-set-name "${stackSet_name}" \
                                    --region "${region}")

          local TEMPLATE=$(echo "${STACK_SET_DETAILS}" |jq -r '.StackSet.TemplateBody')

          echo -e "${cyellow}${TEMPLATE}${creset}"

          echo -e "${cgreen}Success: Stack Set is updated.Please Validate Logs${creset}"

          echo "Stackset name: ${stackSet_name}" >> stackset_update

          echo "OperationId: ${UPDATE_ID}" >> stackset_update
      fi
      done
fi
}

detect_drift () {

    local stackSet_name=$1
    local region=$2


    if ! aws cloudformation describe-stack-set --stack-set-name "${stackSet_name}" --region "${region}">/dev/null 2>&1; then
    #Create the stackset if it doesn't exist
        echo -e "${ccyan}StackSet ${stackSet_name} doesn't exists in ${region}. Please proceed  to use create stackset job to create${creset}"
        exit 1
    else
        echo -e "${ccyan}Detecting the stackSet ${stackSet_name} drift in ${region}. proceeding to update stackset${creset}"
        
        DETECT_OPERATION_ID=$(aws cloudformation detect-stack-set-drift --stack-set-name "${stackSet_name}" --region "${region}"|jq -r '.OperationId')
        
        echo -e "${cpurple}OperationID:$DETECT_OPERATION_ID${creset}"
        
        local DETECT_DETAILS=$(aws cloudformation describe-stack-set-operation \
                           --stack-set-name "${stackSet_name}" \
                           --operation-id "${DETECT_OPERATION_ID}" \
                           --region "${region}")

        local DETECT_DRIFT_STATUS=$(echo "${DETECT_DETAILS}"|jq -r '.StackSetOperation.StackSetDriftDetectionDetails.DriftStatus')
        local DRIFT_DETECTION_STATUS=$(echo "${DETECT_DETAILS}"|jq -r '.StackSetOperation.StackSetDriftDetectionDetails.DriftDetectionStatus')
         
        error_post=false
        count=0

        until [ $DRIFT_DETECTION_STATUS == "COMPLETED" ] || [ $DRIFT_DETECTION_STATUS == "PARTIAL_SUCCESS " ] || [ $error_post == "true" ]  || [ $count -gt 15 ];
         do

        local detect_details=$(aws cloudformation describe-stack-set-operation \
                           --stack-set-name "${stackSet_name}" \
                           --operation-id "${DETECT_OPERATION_ID}" \
                           --region "${region}")
        local detect_drift_status=$(echo "${detect_details}"|jq -r '.StackSetOperation.StackSetDriftDetectionDetails.DriftStatus')
        local drift_detection_status=$(echo "${detect_details}"|jq -r '.StackSetOperation.StackSetDriftDetectionDetails.DriftDetectionStatus')

        if [ $drift_detection_status == "IN_PROGRESS" ];
        then
        echo -e "${ccyan}drift is running. wait for to finish the update${creset}"
        sleep 10
        echo -n '.'
        count=$((count + 1))
        elif [ $drift_detection_status == "FAILED" ];
        then
        echo -e "${ccyan}drift has failed. Please Validate the logs${creset}"
        echo -e "${detect_details}${creset}"
        error_post=true
        elif [ $drift_detection_status == "PARTIAL_SUCCESS" ];
        then
        echo -e "${ccyan}drift has partial success. Please Validate the logs${creset}"
        echo -e "${detect_details}${creset}"
        error_post=true
        else 
        echo -e "${cgreen}Success: The drift detection operation completed without failing on any stack instances${creset}"
        echo -e "${detect_details}${creset}"
        fi
        done
         
    fi

    if [ $detect_drift_status == "NOT_CHECKED" ];
        then
        
        echo -e "${ccyan}CloudFormation hasn't checked the stack set for drift${creset}"
        
        elif [ $detect_drift_status == "IN_SYNC" ];
        then
        
        echo -e "${cgreen}Success: All of the stack instances belonging to the stack set stack match from the expected template and parameter configuration .Please Validate Logs${creset}"
        
        elif [ $detect_drift_status == "DRIFTED" ];
        then

        echo -e "${cyellow}One or more of the stack instances belonging to the stack set stack differs from the expected template and parameter configuration${creset}"
        fi
}

if [ "$update_stackset" == "true" ];
then
          echo -e "${ccyan}Creating stackset${creset}"
          ACCOUNT=$(aws sts get-caller-identity|jq -r '.Account')
            #create_sts_credentials
                    for REGION in "${regions[@]}";
                    do
                            echo -e "${ccyan}Account:${ACCOUNT}${creset}"
                            echo -e "${ccyan}Region:${REGION}${creset}"
                            update_stackset "${stackSet_name}" "${template_file}" "${parameter_file}" "$REGION"
                    done

          unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN

fi


if [ "$detect_drift" == "true" ];
then
          echo -e "${ccyan}Checking the drift${creset}"
          ACCOUNT=$(aws sts get-caller-identity|jq -r '.Account')
            #create_sts_credentials
                    for REGION in "${regions[@]}";
                    do
                            echo -e "${ccyan}Account:${ACCOUNT}${creset}"
                            echo -e "${ccyan}Region:${REGION}${creset}"
                            detect_drift "${stackSet_name}" "$REGION"
                    done

          unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN

fi




