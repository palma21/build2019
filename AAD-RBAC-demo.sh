#!/bin/bash

# Including DemoMagic
. demo-magic.sh

# Defining Type Speed
TYPE_SPEED=25

# Defining Custom prompt
DEMO_PROMPT="${green2}\u@\H${WHITE}:${blue2}\w${yellow}$ "


# My Aliases
function k() {
    /usr/local/bin/kubectl "$@"
}

function kctx() {
    /usr/local/bin/kubectl config use-context "$@"
}


PREFIX="build-AAD-demo"
RG="${PREFIX}-rg"
LOC="westus2"
AKSNAME="${PREFIX}"
K8S_VERSION="1.13.5"
DEV_GROUP_NAME="appdev"
OPS_GROUP_NAME="opssre"


AZURE_ACCOUNT_NAME=<YOUR_SUBSCRIPTION>

# Setup right subscription
az account set -s $AZURE_ACCOUNT_NAME

# p = print
# pe = print and execute


# Create Server and Client App
pe "serverApplicationId=\$(az ad app create --display-name "${AKSNAME}Server" --identifier-uris "https://${AKSNAME}Server" --query appId -o tsv)"
# serverApplicationId="$(az ad app create --display-name "${AKSNAME}Server" --identifier-uris "https://${AKSNAME}Server" --query appId -o tsv)"
echo $serverApplicationId


pe "az ad app update --id \$serverApplicationId --set groupMembershipClaims=All"
# az ad app update --id $serverApplicationId --set groupMembershipClaims=All

pe "az ad sp create --id \$serverApplicationId"
# az ad sp create --id $serverApplicationId

pe 'serverApplicationSecret=$(az ad sp credential reset --name \$serverApplicationId --credential-description "AKSPassword" --query password -o tsv)'
# serverApplicationSecret=$(az ad sp credential reset --name $serverApplicationId --credential-description "AKSPassword" --query password -o tsv)

pe "az ad app permission add --id \$serverApplicationId --api 00000003-0000-0000-c000-000000000000 --api-permissions e1fe6dd8-ba31-4d61-89e7-88639da4683d=Scope 06da0dbc-49e2-44d2-8312-53f166ab848a=Scope 7ab1d382-f21e-4acd-a863-ba3e13f7da61=Role"
# az ad app permission add --id $serverApplicationId --api 00000003-0000-0000-c000-000000000000 --api-permissions e1fe6dd8-ba31-4d61-89e7-88639da4683d=Scope 06da0dbc-49e2-44d2-8312-53f166ab848a=Scope 7ab1d382-f21e-4acd-a863-ba3e13f7da61=Role

pe "az ad app permission grant --id $serverApplicationId --api 00000003-0000-0000-c000-000000000000"
# az ad app permission grant --id $serverApplicationId --api 00000003-0000-0000-c000-000000000000

pe "az ad app permission admin-consent --id \$serverApplicationId"
# az ad app permission admin-consent --id $serverApplicationId

pe "oAuthPermissionId=\$(az ad app show --id \$serverApplicationId --query "oauth2Permissions[0].id" -o tsv)"
# oAuthPermissionId="$(az ad app show --id $serverApplicationId --query "oauth2Permissions[0].id" -o tsv)"
echo $oAuthPermissionId

pe "clientApplicationId=\$(az ad app create --display-name "${AKSNAME}Client" --native-app --reply-urls "https://${AKSNAME}Client" --query appId -o tsv)"
# clientApplicationId="$(az ad app create --display-name "${AKSNAME}Client" --native-app --reply-urls "https://${AKSNAME}Client" --query appId -o tsv)"
echo $clientApplicationId

pe "az ad sp create --id \$clientApplicationId"
# az ad sp create --id $clientApplicationId

pe "az ad app permission add --id \$clientApplicationId --api \$serverApplicationId --api-permissions \$oAuthPermissionId=Scope"
# az ad app permission add --id $clientApplicationId --api $serverApplicationId --api-permissions $oAuthPermissionId=Scope

pe "az ad app permission grant --id $clientApplicationId --api $serverApplicationId"

# Create Resource Group
pe "az group create -n ${RG} -l ${LOC}"

# Create AKS SP
pe "SP=\$(az ad sp create-for-rbac -n ${AKSNAME}SP --skip-assignment)"
# SP=$(az ad sp create-for-rbac -n "${AKSNAME}SP" --skip-assignment)

pe 'appId=$(echo $SP | jq -r .appId)'
# appId=$(echo $SP | jq -r .appId)
# echo $appId

pe 'clientSecret=$(echo $SP | jq -r .password)'
# clientSecret=$(echo $SP | jq -r .password)
# echo $clientSecret

pe 'account=$(az account show --query "{subscriptionId:id,tenantId:tenantId,user:user.name}")'

pe 'tenantId=$(echo $account|jq -r .tenantId)'

# Create AKS
pe "az aks create \
  -g $RG  \
  -n $AKSNAME \
  -k $K8S_VERSION \
  -c 1 \
  --generate-ssh-keys \
  --aad-server-app-id \$serverApplicationId \
  --aad-server-app-secret \$serverApplicationSecret \
  --aad-client-app-id \$clientApplicationId \
  --aad-tenant-id \$tenantId \
  --service-principal \$appId \
  --client-secret \$clientSecret \
  --no-wait"

# Changing to precreated cluster
BUILD_RG="build-AAD-rg"
BUILD_AKSNAME="build-AAD"
# p "AKS_ID=\$(az aks show -g $BUILD_RG -n $BUILD_AKSNAME --query id -o tsv)"
AKS_ID="/subscriptions/4cce23ba-33a7-4324-a00f-fcb09e6f4abb/resourcegroups/build-AAD-rg/providers/Microsoft.ContainerService/managedClusters/build-AAD"

pe "OPSSRE_ID=\$(az ad group create --display-name $OPS_GROUP_NAME --mail-nickname $OPS_GROUP_NAME --query objectId -o tsv)"
# OPSSRE_ID=$(az ad group create --display-name $OPS_GROUP_NAME --mail-nickname $OPS_GROUP_NAME --query objectId -o tsv)

echo $OPSSRE_ID

pe "APPDEV_ID=\$(az ad group create --display-name $DEV_GROUP_NAME --mail-nickname $DEV_GROUP_NAME --query objectId -o tsv)"
# APPDEV_ID=$(az ad group create --display-name $DEV_GROUP_NAME --mail-nickname $DEV_GROUP_NAME --query objectId -o tsv)

echo $APPDEV_ID


pe "az role assignment create --assignee \$APPDEV_ID --role \"Azure Kubernetes Service Cluster User Role\" --scope \$AKS_ID"
# az role assignment create --assignee $APPDEV_ID --role "Azure Kubernetes Service Cluster User Role" --scope $AKS_ID

pe "az role assignment create --assignee \$OPSSRE_ID --role \"Azure Kubernetes Service Cluster User Role\" --scope \$AKS_ID"
# az role assignment create --assignee $OPSSRE_ID --role "Azure Kubernetes Service Cluster User Role" --scope $AKS_ID

# Using precreated cluster
BUILD_RG="build-AAD-rg"
BUILD_AKSNAME="build-AAD"
p "az aks get-credentials --resource-group $BUILD_RG --name $BUILD_AKSNAME --admin"
kctx build-AAD-admin

pe "k create namespace dev"
pe "k create namespace sre"

pe "code roles/role-dev-namespace.yaml"
pe "k apply -f roles/role-dev-namespace.yaml"

sed -i roles/rolebinding-dev-namespace.yaml -e "s/\(^.*- name: \).*/\1\"$APPDEV_ID\"/gI"
pe "code roles/rolebinding-dev-namespace.yaml"

pe "k apply -f roles/rolebinding-dev-namespace.yaml"

sed -i roles/rolebinding-opssre.yaml -e "s/\(^.*- name: \).*/\1\"$OPSSRE_ID\"/gI"
pe "code roles/rolebinding-opssre.yaml"
pe "k apply -f roles/rolebinding-opssre.yaml"

# DEV Test
pe "userID=\$(az ad signed-in-user show --query objectId -o tsv)"
# userID=$(az ad signed-in-user show --query objectId -o tsv)
# echo $userID

pe "az ad group member add --group $DEV_GROUP_NAME --member-id \$userID"


BUILD_RG="build-AAD-rg"
BUILD_AKSNAME="build-AAD"
pe "az aks get-credentials --resource-group $BUILD_RG --name $BUILD_AKSNAME --overwrite-existing"

pe "k run --generator=run-pod/v1 nginx-dev --image=nginx -n dev"
pe "k get pods -n dev"
pe "k get pods -n sre"
pe "k get pods"


# Ops Test

pe "az ad group member add --group $OPS_GROUP_NAME --member-id \$userID"


pe "k run --generator=run-pod/v1 nginx-dev --image=nginx -n sre"
pe "k get pods --all-namespaces"


# Clean up

pe "clear"

kctx build-AAD-admin > /dev/null
k delete ns sre > /dev/null
k delete ns dev > /dev/null
k delete -f roles/rolebinding-opssre.yaml > /dev/null

az ad group delete -g $APPDEV_ID > /dev/null
az ad group delete -g $OPSSRE_ID > /dev/null

az ad group member remove --group $DEV_GROUP_NAME --member-id $userID
az ad group member remove --group $OPS_GROUP_NAME --member-id $userID

az ad app delete --id $serverApplicationId > /dev/null
az ad app delete --id $clientApplicationId > /dev/null

az ad sp delete  --id $appId > /dev/null
az group delete -n $RG -y --no-wait > /dev/null