#!/bin/bash
         execution_role_name="AWSCloudFormationStackSetExecutionRole"
         administration_role_arn="arn:aws:iam::473148384440:role/AWSCloudFormationStackSetAdministrationRole"
        if [ $# -ne 9 ]; then
            echo "Enter stack set name, stack set parameters file name, stack set template file name to create, set changeset value (true or false),enter region name and profile. "
            exit 0
        else
            STACK_SET_NAME=$1
            STACK_SET_PARAMETERS_FILE_NAME=$2
            STACK_SET_TEMPLATE_NAME=$3
            S3BUCKET=$4
            DESTINATION_ACCOUNTS=$5
            DESTINATION_REGIONS=$6
            CHANGESET_MODE=$7
            REGION=$8
            PROFILE=$9
        fi
        if [[ "cloudformation/"$STACK_SET_TEMPLATE_NAME != *.yaml ]]; then
            echo "CloudFormation template $STACK_SET_TEMPLATE_NAME does not exist. Make sure the extension is *.yaml and not (*.yml)"
           exit 0
        fi
        #if [[ "$PWD/cfn-parameters/"$STACK_SET_PARAMETERS_FILE_NAME != *.properties ]]; then
         #   echo "CloudFormation parameters $STACK_SET_PARAMETERS_FILE_NAME does not exist"
          #  exit 0
        #fi

        #****Print the Stacksets exists**
        aws cloudformation list-stack-sets --status ACTIVE --query Summaries[*].StackSetName --region $REGION --profile $PROFILE

        #****Verify stackset name exists in the above list**
        STACKSETEXISTS=$(aws cloudformation list-stack-sets --status ACTIVE --query Summaries[*].StackSetName --region $REGION --profile $PROFILE --output text|grep -w ${STACK_SET_NAME})

        #****If stackset name doesn't exist in the list
        if [[ -z "$STACKSETEXISTS" ]] && [[ $CHANGESET_MODE == "create&execute-stackset" ]];
        then
        echo "Create Stack-set"
        aws cloudformation create-stack-set --stack-set-name ${STACK_SET_NAME} --template-body file://cloudformation/${STACK_SET_TEMPLATE_NAME} --parameters ParameterKey=S3BucketName,ParameterValue=${S3BUCKET} --execution-role-name ${execution_role_name} --administration-role-arn ${administration_role_arn} --region $REGION --profile $PROFILE
        STACKSETSTATUS=$(aws cloudformation describe-stack-set --stack-set-name ${STACK_SET_NAME} --query StackSet.Status --region $REGION --profile $PROFILE --output text)
        echo "StackSet Creation status: $STACKSETSTATUS"
        #if stackset name exists in the above list
        fi

        #if stackset status not equal to active
        if [[ $STACKSETSTATUS != "ACTIVE" ]] && [[ $CHANGESET_MODE == "create&execute-stackset" ]];then
          echo "Delete The Stack Set If StackSetStatus Is Not Active"
        aws cloudformation delete-stack-set --stack-set-name ${STACK_SET_NAME} --region $REGION --profile $PROFILE
        fi

        #if Stackset status is active
        if [[ $STACKSETSTATUS == "ACTIVE" ]] && [[ $CHANGESET_MODE == "create&execute-stackset" ]];then
          OPERATIONID=$(aws cloudformation create-stack-instances --stack-set-name ${STACK_SET_NAME} --accounts ${DESTINATION_ACCOUNTS} --regions ${DESTINATION_REGIONS}  --region $REGION --profile $PROFILE --query OperationId --output text)
          echo "Operation ID: $OPERATIONID"
          OPERATIONACTION=$(aws cloudformation describe-stack-set-operation --stack-set-name ${STACK_SET_NAME} --operation-id ${OPERATIONID} --query StackSetOperation.Action --region $REGION --profile $PROFILE --output text)
          OPERATIONSTATUS=$(aws cloudformation describe-stack-set-operation --stack-set-name ${STACK_SET_NAME} --operation-id ${OPERATIONID} --query StackSetOperation.Status --region $REGION --profile $PROFILE --output text)
        #if the stack instane status ins running
        while [[ "$OPERATIONSTATUS" == "RUNNING" ]]
          do
        #wait for 10 sec and try again the stack instance status untill it comes to not equal running status
                  sleep 10
                  OPERATIONSTATUS=$(aws cloudformation describe-stack-set-operation --stack-set-name ${STACK_SET_NAME} --operation-id ${OPERATIONID} --query StackSetOperation.Status --region $REGION --profile $PROFILE --output text)
                  echo "Stack-Instance $OPERATIONACTION status: $OPERATIONSTATUS"

          done
           echo "STATUS ACTION ${OPERATIONACTION} :${OPERATIONSTATUS}"
           echo "Describe the stack instance"
        aws cloudformation describe-stack-instance --stack-set-name ${STACK_SET_NAME} --stack-instance-account ${DESTINATION_ACCOUNTS} --stack-instance-region ${DESTINATION_REGIONS} --region $REGION --profile $PROFILE

        #if the stack instance operation status is not equal to succeeded. Delete the created stack instance
           if [[ "$OPERATIONSTATUS" != "SUCCEEDED" ]];
           then
           DELETE_STACKINSTANCE_OPERATIONID=$(aws cloudformation delete-stack-instances --stack-set-name ${STACK_SET_NAME} --accounts ${DESTINATION_ACCOUNTS} --regions ${DESTINATION_REGIONS} --no-retain-stacks --query OperationId --region $REGION --profile $PROFILE --output text)
                echo "Deleting the StackInstance OperationID:$DELETE_STACKINSTANCE_OPERATIONID"
        DELETE_STACKINSTANCE_OPERATIONACTION=$(aws cloudformation describe-stack-set-operation --stack-set-name ${STACK_SET_NAME} --operation-id ${DELETE_STACKINSTANCE_OPERATIONID} --query StackSetOperation.Action --region $REGION --profile $PROFILE --output text)
        DELETE_STACKINSTANCE_OPERATIONSTATUS=$(aws cloudformation describe-stack-set-operation --stack-set-name ${STACK_SET_NAME} --operation-id ${DELETE_STACKINSTANCE_OPERATIONID} --query StackSetOperation.Status --region $REGION --profile $PROFILE --output text)
                while [[ "$DELETE_STACKINSTANCE_OPERATIONSTATUS" == "RUNNING" ]]
                do
                  sleep 10
                  DELETE_STACKINSTANCE_OPERATIONSTATUS=$(aws cloudformation describe-stack-set-operation --stack-set-name ${STACK_SET_NAME} --operation-id ${DELETE_STACKINSTANCE_OPERATIONID} --query StackSetOperation.Status --region $REGION --profile $PROFILE --output text)
                  echo "Stack-Instance $DELETE_STACKINSTANCE_OPERATIONACTION status: $DELETE_STACKINSTANCE_OPERATIONSTATUS"

          done
        echo "STATUS ACTION $DELETE_STACKINSTANCE_OPERATIONACTION STATUS:$DELETE_STACKINSTANCE_OPERATIONSTATUS"
            fi
         fi



         if [[ "$CHANGESET_MODE" == "delete-stackset" ]];
         then
         echo "Delete the StackSet"
         aws cloudformation delete-stack-set --stack-set-name ${STACK_SET_NAME} --region $REGION --profile $PROFILE
	 DELETE_STACKSET_STATUS=$(aws cloudformation describe-stack-set --stack-set-name  ${STACK_SET_NAME} --region ${REGION} --profile $PROFILE --query StackSet.Status --output text)
	 echo "StackSet Status:$DELETE_STACKSET_STATUS"
         fi


        if [[ "$CHANGESET_MODE" == "delete-stackInstance" ]];
        then
        echo "Delete the StackInstance"
        DELETE_STACKINSTANCE_OPERATIONID=$(aws cloudformation delete-stack-instances --stack-set-name ${STACK_SET_NAME} --accounts ${DESTINATION_ACCOUNTS} --regions ${DESTINATION_REGIONS} --no-retain-stacks --query OperationId --region $REGION --profile $PROFILE --output text)
                echo "Deleting the StackInstance OperationID:$DELETE_STACKINSTANCE_OPERATIONID"
        DELETE_STACKINSTANCE_OPERATIONACTION=$(aws cloudformation describe-stack-set-operation --stack-set-name ${STACK_SET_NAME} --operation-id ${DELETE_STACKINSTANCE_OPERATIONID} --query StackSetOperation.Action --region $REGION --profile $PROFILE --output text)
        DELETE_STACKINSTANCE_OPERATIONSTATUS=$(aws cloudformation describe-stack-set-operation --stack-set-name ${STACK_SET_NAME} --operation-id ${DELETE_STACKINSTANCE_OPERATIONID} --query StackSetOperation.Status --region $REGION --profile $PROFILE --output text)
                while [[ "$DELETE_STACKINSTANCE_OPERATIONSTATUS" == "RUNNING" ]]
                do
        sleep 10
                  DELETE_STACKINSTANCE_OPERATIONSTATUS=$(aws cloudformation describe-stack-set-operation --stack-set-name ${STACK_SET_NAME} --operation-id ${DELETE_STACKINSTANCE_OPERATIONID} --query StackSetOperation.Status --region $REGION --profile $PROFILE --output text)
                  echo "Stack-Instance $DELETE_STACKINSTANCE_OPERATIONACTION status: $DELETE_STACKINSTANCE_OPERATIONSTATUS"

          done
                echo "STATUS ACTION $DELETE_STACKINSTANCE_OPERATIONACTION STATUS:$DELETE_STACKINSTANCE_OPERATIONSTATUS"
        aws cloudformation list-stack-instances --stack-set-name ${STACK_SET_NAME} --region $REGION --profile $PROFILE --output json
        fi

        if [[ "$CHANGESET_MODE" == "update-stackset" ]];
        then
        echo "Update the stackset"
        UPDATE_STACKSET_OPERATIONID=$(aws cloudformation update-stack-set --stack-set-name ${STACK_SET_NAME} --template-body file://cloudformation/${STACK_SET_TEMPLATE_NAME} --tags Key=StackSetName,Value=${STACK_SET_NAME} --parameters ParameterKey=S3BucketName,ParameterValue=${S3BUCKET} --execution-role-name ${execution_role_name} --administration-role-arn ${administration_role_arn} --query OperationId --region $REGION --profile $PROFILE)
        echo "Updating the StackSet OperationID:$UPDATE_STACKSET_OPERATIONID"
        UPDATE_STACKSET_OPERATIONACTION=$(aws cloudformation describe-stack-set-operation --stack-set-name ${STACK_SET_NAME} --operation-id ${UPDATE_STACKSET_OPERATIONID} --query StackSetOperation.Action --region $REGION --profile $PROFILE --output text)
        UPDATE_STACKSET_OPERATIONSTATUS=$(aws cloudformation describe-stack-set-operation --stack-set-name ${STACK_SET_NAME} --operation-id ${UPDATE_STACKSET_OPERATIONID} --query StackSetOperation.Status --region $REGION --profile $PROFILE --output text)
        while [[ "$UPDATE_STACKSET_OPERATIONSTATUS" == "RUNNING" ]]
                do
                  sleep 10
        UPDATE_STACKSET_OPERATIONSTATUS=$(aws cloudformation describe-stack-set-operation --stack-set-name ${STACK_SET_NAME} --operation-id ${UPDATE_STACKINSTANCE_OPERATIONID} --query StackSetOperation.Status --region $REGION --profile $PROFILE --output text)
                  echo "Stack-Set $UPDATE_STACKSET_OPERATIONACTION status: $UPDATE_STACKSET_OPERATIONSTATUS"

          done
        echo "STATUS ACTION $UPDATE_STACKSET_OPERATIONACTION STATUS:$UPDATE_STACKSET_OPERATIONSTATUS"
        STACKSETSTATUS=$(aws cloudformation describe-stack-set --stack-set-name ${STACK_SET_NAME} --query StackSet.Status --region $REGION --profile $PROFILE --output text)
        echo "StackSet update status: $STACKSETSTATUS"
        fi


        if [[ "$CHANGESET_MODE" == "update-stackInstance" ]];
        then
         echo "Update the stackInstance"
        UPDATE_STACKINSTANCE_OPERATIONID=$(aws cloudformation update-stack-instances --stack-set-name ${STACK_SET_NAME} --accounts ${DESTINATION_ACCOUNTS} --regions ${DESTINATION_REGIONS} --parameter-overrides ParameterKey=S3BucketName,ParameterValue=${S3BUCKET} --query OperationId --region $REGION --profile $PROFILE --output text)
                echo "Updating the StackInstance OperationID:$UPDATE_STACKINSTANCE_OPERATIONID"
        UPDATE_STACKINSTANCE_OPERATIONACTION=$(aws cloudformation describe-stack-set-operation --stack-set-name ${STACK_SET_NAME} --operation-id ${UPDATE_STACKINSTANCE_OPERATIONID} --query StackSetOperation.Action --region $REGION --profile $PROFILE --output text)
        UPDATE_STACKINSTANCE_OPERATIONSTATUS=$(aws cloudformation describe-stack-set-operation --stack-set-name ${STACK_SET_NAME} --operation-id ${UPDATE_STACKINSTANCE_OPERATIONID} --query StackSetOperation.Status --region $REGION --profile $PROFILE --output text)
                while [[ "$UPDATE_STACKINSTANCE_OPERATIONSTATUS" == "RUNNING" ]]
                do
                  sleep 10
        UPDATE_STACKINSTANCE_OPERATIONSTATUS=$(aws cloudformation describe-stack-set-operation --stack-set-name ${STACK_SET_NAME} --operation-id ${UPDATE_STACKINSTANCE_OPERATIONID} --query StackSetOperation.Status --region $REGION --profile $PROFILE --output text)
                  echo "Stack-Instance $UPDATE_STACKINSTANCE_OPERATIONACTION status: $UPDATE_STACKINSTANCE_OPERATIONSTATUS"

          done
        echo "STATUS ACTION $DELETE_STACKINSTANCE_OPERATIONACTION STATUS:$DELETE_STACKINSTANCE_OPERATIONSTATUS"
                aws cloudformation list-stack-instances --stack-set-name ${STACK_SET_NAME} --region $REGION --profile $PROFILE --output json
        fi
