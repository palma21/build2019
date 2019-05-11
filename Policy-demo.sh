#!/bin/bash

# Including DemoMagic
. demo-magic.sh

# Defining Type Speed
TYPE_SPEED=20

# Defining Custom prompt
DEMO_PROMPT="${green2}\u@\H${WHITE}:${blue2}\w${yellow}$ "


# My Aliases
function k() {
    /usr/local/bin/kubectl "$@"
}

function kctx() {
    /usr/local/bin/kubectl config use-context "$@"
}

# Only works on WSL
# function chrome(){
#     /c/Program\ Files\ \(x86\)/Google/Chrome/Application/chrome.exe "$@"
# }

# Create Resource Group.
PREFIX="build-policy"
RG="${PREFIX}-rg"
LOC="westus2"
AKSNAME="${PREFIX}"
K8S_VERSION=1.13.5
AZURE_ACCOUNT_NAME=<YOUR_SUBSCRIPTION>
SUBID=$(az account show -s $AZURE_ACCOUNT_NAME -o tsv --query 'id')


# Setup right subscription
az account set -s $AZURE_ACCOUNT_NAME



pe "kctx build-policy-admin"

pe "az aks enable-addons --addons azure-policy --name $AKSNAME --resource-group $RG"

pe "clear"

# Only works on WSL
# chrome "https://ms.portal.azure.com/#blade/Microsoft_Azure_Policy/PolicyMenuBlade/Overview"

pe "k apply -f test-pod.yaml"

pe "k run --generator=run-pod/v1 jpalma-hello --image=jpalma.azurecr.io/helloworld:v1"

pe "k run --generator=run-pod/v1 mekint-hello --image=mekint.azurecr.io/helloworld:v1"


pe "clear"

## Clean up 

k delete pod jpalma-hello > /dev/null


# az aks disable-addons --addons azure-policy -n $AKSNAME -g $RG

