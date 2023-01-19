#!/bin/bash

STACKSETNAME="mystackset"
ACCOUNTS="${ACCOUNTS}"
REGIONS="us-east-2"
  
aws cloudformation create-stack-set --stack-set-name ${STACKSETNAME} --template-body file://stackset-creation/s3-creation.yaml

STACKSETSTATUS=$(aws cloudformation describe-stack-set --stack-set-name ${STACKSETNAME} --query StackSet.Status --output text)

if [[ $STACKSETSTATUS != "ACTIVE" ]];then
  aws cloudformation delete-stack-set --stack-set-name ${STACKSETNAME}
elif [[ $STACKSETSTATUS == "ACTIVE" ]];then
  OPERATIINID=$(aws cloudformation create-stack-instances --stack-set-name ${STACKSETNAME} --accounts ${ACCOUNTS} --regions ${REGIONS})
  
  OPERATIONACTION=$(aws cloudformation describe-stack-set-operation --stack-set-name ${STACKSETNAME} --operation-id ${OPERATIINID} --query StackSetOperation.Action)
  
  OPERATIONSTATUS=$(aws cloudformation describe-stack-set-operation --stack-set-name ${STACKSETNAME} --operation-id ${OPERATIINID} --query StackSetOperation.Status)
   
   echo "${OPERATIONACTION} STATUS:${OPERATIONSTATUS}"
 elif [[ $OPERATIONSTATUS != "SUCCEEDED" ]]; then
	DELETE_STACKINSTANCE_OPERATIONID=$(aws cloudformation delete-stack-instances --stack-set-name ${STACKSETNAME} --accounts ${ACCOUNTS} --regions ${REGIONS} --no-retain-stacks)
    DELETE_STACKINSTANCE_OPERATIONACTION=$(aws cloudformation describe-stack-set-operation --stack-set-name ${STACKSETNAME} --operation-id 286a0aa7-763a-4af9-a75f-aa28ac1cd6e5 --query StackSetOperation.Action)
  
	DELETE_STACKINSTANCE_OPERATIONSTATUS=$(aws cloudformation describe-stack-set-operation --stack-set-name ${STACKSETNAME} --operation-id 286a0aa7-763a-4af9-a75f-aa28ac1cd6e5 --query StackSetOperation.Status)