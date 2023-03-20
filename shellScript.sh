#!/bin/bash

#usage : ./stackSet-deploy-script.sh --app-name APP_NAME --stackSet-name STACKSET_NAME --target-accounts TARGET_ACCOUNTS --regions REGIONS --template-file TEMPLATE_FILE --parameter-file PARAMETER_FILE  --profile PROFILE --create-stackset --create-stackInstance

#parse command line arguments
cblack='\033[0;30m'        # Black
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
    app_name ="$2"
    shift 2
    ;;
    --stackSet_name)
    stackSet_name = "$2"
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
    --create-stackset)
    create_stackset=true
    shift 1
    ;;
    --create-stackInstance)
    create_stackInstance=true
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


if [ -Z "$stackSet_name" ] || [ -Z "$template_file" ] || [ -Z "$parameter_file" ] || [ -Z "$regions" ] || [ -Z "$profile" ];then
  echo -e "\033[0;33m\nMissing Required arguments. usage: ./stackSet-deploy-script.sh --app-name APP_NAME --stackSet-name STACKSET_NAME --target-accounts TARGET_ACCOUNTS --regions REGIONS --template-file TEMPLATE_FILE --parameter-file PARAMETER_FILE  --profile PROFILE --create-stackset --create-stackInstance
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


create_stackset() {
    local stackSet_name=$1
    local template_file=$2
    local parameter_file=$3
    local target_account=$4
    local region=$5


  local parameters_file="cfn-parameters/${ACCOUNT}-${REGION}-${parameter_file}"
  jq -s '.[0] + .[1]' "cfn-parameters/$parameter_file" "$parameter_file" > "${ACCOUNT}"-"${REGION}"-update_parameter_file


#check if the stackset exists

if ! aws cloudformation describe-stack-set --stack-set-name "${stackSet_name}" --region "${region}">/dev/null 2>&1; then
#Create the stackset if it doesn't exist
echo -e "${ccyan}Creating stackSet: ${stackSet_name} in ${region}${creset}"
aws cloudformation create-stack-set \ 
    --stack-set-name "${stackSet_name}" \
    --template-body "file://${template_file}" \
    --parameters "file://${ACCOUNT}-${REGION}-update_parameter_file" \
    --region "${region}"

local STACK_SET_DETAILS=$(aws cloudformation describe-stack-set \
                          --stack-set-name "${stackSet_name}" \
                          --region "${region}" )
local STACK_SET_STATUS=$(echo "${STACK_SET_DETAILS}"|jq -r '.StackSet.Status')
if [ "${STACK_SET_STATUS}" == "ACTIVE" ]; then
  local TEMPLATE=$(echo "${STACK_SET_DETAILS}" |jq -r '.StackSet.TemplateBody')
  echo -e "${cyellow}${TEMPLATE}${creset}"
  echo -e "${cgreen}Success: Stack Set is created.Please Validate Logs${creset}"
  echo "${stackSet_name}" >> stackset_names
else
  echo -e "${STACK_SET_DETAILS}${creset}"
  echo -e "${cred} Error: Stack Set Creation failed. Please Check logs ${creset}"
  aws cloudformation delete-stack-set \
    --stack-set-name "${stackSet_name}" \
    --region "${region}"
  exit 1
fi
else
    echo -e "${ccyan}StackSet ${stackSet_name} already exists in ${region}. proceeding to create stackInstance${creset}"
fi
}

create_stackInstance(){
    local stackSet_name=$1
    local template_file=$2
    local parameter_file=$3
    local target_account=$4
    local region=$5

    #Create Stack Instances for target accounts
    echo -e "${ccyan} Creating stackInstaces for this deployment Account:${ACCOUNT} and Region:${REGION} under the stackSet:${stackSet_name}${creset}"
    #Create the stack Instance
    aws cloudformation create-stack-instance \
        --stack-set-name "${stackSet_name}" \
        --deployment-targets "${ACCOUNT}" \
        --regions "${REGION}" \
        --output text.json
    echo -e "${ccyan}Waiting to create a stack Instance:${stackSet_name}${creset}"
    aws cloudformation wait 
}



