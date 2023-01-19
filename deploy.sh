#!/bin/bash
STACKSETNAME="mystackset"
ACCOUNTS="473148384440"
REGIONS="us-east-2"

STACKSETEXISTS=$(aws cloudformation list-stack-sets --status ACTIVE --query Summaries[*].StackSetName --output text|grep -w ${STACKSETNAME})

if [[ -z "$STACKSETEXISTS" ]];
then
aws cloudformation create-stack-set --stack-set-name ${STACKSETNAME} --template-body file://s3-creation.yaml
STACKSETSTATUS=$(aws cloudformation describe-stack-set --stack-set-name ${STACKSETNAME} --query StackSet.Status --output text)
echo "StackSet Creation status: $STACKSETSTATUS"
else
        echo "Please Check the StackSet Name it exists in the StackSet"
        exit 1
fi

if [[ $STACKSETSTATUS != "ACTIVE" ]];then
  echo "Delete The Stack Set If StackSetStatus Is Not Active"
  aws cloudformation delete-stack-set --stack-set-name ${STACKSETNAME}
elif [[ $STACKSETSTATUS == "ACTIVE" ]];then
  OPERATIONID=$(aws cloudformation create-stack-instances --stack-set-name ${STACKSETNAME} --accounts ${ACCOUNTS} --regions ${REGIONS}  --query OperationId --output text)
  echo "Operation ID: $OPERATIONID"
  OPERATIONACTION=$(aws cloudformation describe-stack-set-operation --stack-set-name ${STACKSETNAME} --operation-id ${OPERATIONID} --query StackSetOperation.Action --output text)
  OPERATIONSTATUS=$(aws cloudformation describe-stack-set-operation --stack-set-name ${STACKSETNAME} --operation-id ${OPERATIONID} --query StackSetOperation.Status --output text)
  while [[ "$OPERATIONSTATUS" == "RUNNING" ]]
  do
          sleep 10
          OPERATIONSTATUS=$(aws cloudformation describe-stack-set-operation --stack-set-name ${STACKSETNAME} --operation-id ${OPERATIONID} --query StackSetOperation.Status --output text)
          echo "Stack-Instance $OPERATIONACTION status: $OPERATIONSTATUS"

  done
   echo "STATUS ACTION ${OPERATIONACTION} :${OPERATIONSTATUS}"
 fi

if [[ "$OPERATIONSTATUS" != "SUCCEEDED" ]]; then
      echo "Delete the Stack-Instance"
        DELETE_STACKINSTANCE_OPERATIONID=$(aws cloudformation delete-stack-instances --stack-set-name ${STACKSETNAME} --accounts ${ACCOUNTS} --regions ${REGIONS} --no-retain-stacks --query OperationId --output text)
        echo "Deleting the StackInstance OperationID:$DELETE_STACKINSTANCE_OPERATIONID"
    DELETE_STACKINSTANCE_OPERATIONACTION=$(aws cloudformation describe-stack-set-operation --stack-set-name ${STACKSETNAME} --operation-id ${DELETE_STACKINSTANCE_OPERATIONID} --query StackSetOperation.Action --output text)
        DELETE_STACKINSTANCE_OPERATIONSTATUS=$(aws cloudformation describe-stack-set-operation --stack-set-name ${STACKSETNAME} --operation-id ${DELETE_STACKINSTANCE_OPERATIONID} --query StackSetOperation.Status --output text)
        while [[ "$DELETE_STACKINSTANCE_OPERATIONSTATUS" == "RUNNING" ]]
        do
          sleep 10
          DELETE_STACKINSTANCE_OPERATIONSTATUS=$(aws cloudformation describe-stack-set-operation --stack-set-name ${STACKSETNAME} --operation-id ${DELETE_STACKINSTANCE_OPERATIONID} --query StackSetOperation.Status --output text)
          echo "Stack-Instance $DELETE_STACKINSTANCE_OPERATIONACTION status: $DELETE_STACKINSTANCE_OPERATIONSTATUS"

  done
        echo "STATUS ACTION $DELETE_STACKINSTANCE_OPERATIONACTION STATUS:$DELETE_STACKINSTANCE_OPERATIONSTATUS"

 else
   echo "Congrats!! succesfully updated the stack instance"
 fi
