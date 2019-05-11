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



PREFIX="build-demo"
RG="${PREFIX}-waf-rg"
LOC="westus2"
AKSNAME="${PREFIX}waf"
VNET_NAME="${PREFIX}vnet"
AKSSUBNET_NAME="${PREFIX}akssubnet"
SVCSUBNET_NAME="${PREFIX}svcsubnet"
APPGWSUBNET_NAME="${PREFIX}appgwsubnet"
IDENTITY_NAME="${PREFIX}identity"
AGNAME="${PREFIX}ag"
AGPUBLICIP_NAME="${PREFIX}agpublicip"
AZURE_ACCOUNT_NAME=<YOUR_SUBSCRIPTION>
SUBID=$(az account show -s $AZURE_ACCOUNT_NAME -o tsv --query 'id')

# Automatically print the SP values into $APPID and $PASSWORD, trust me
eval "$(az ad sp create-for-rbac -n ${PREFIX}sp --skip-assignment | jq -r '. | to_entries | .[] | .key + "=\"" + .value + "\""' | sed -r 's/^(.*=)/\U\1/')"

# p = print
# pe = print and execute

# Setup right subscription
az account set -s $AZURE_ACCOUNT_NAME

pe "az group create -n $RG -l $LOC --no-wait"

pe "az network vnet create \
    --resource-group $RG \
    --name $VNET_NAME \
    --address-prefixes 10.42.0.0/16 \
    --subnet-name $AKSSUBNET_NAME \
    --subnet-prefix 10.42.1.0/24"

pe "az network vnet subnet create \
    --resource-group $RG \
    --vnet-name $VNET_NAME \
    --name $SVCSUBNET_NAME \
    --address-prefix 10.42.2.0/24"

pe "az network vnet subnet create \
    --resource-group $RG \
    --vnet-name $VNET_NAME \
    --name $APPGWSUBNET_NAME \
    --address-prefix 10.42.3.0/24"

# Get $VNETID & $SUBNETID
pe 'VNETID=$(az network vnet show -g $RG --name $VNET_NAME --query id -o tsv)'
pe 'SUBNETID=$(az network vnet subnet show -g $RG --vnet-name $VNET_NAME --name $AKSSUBNET_NAME --query id -o tsv)'


pe "az aks create -g $RG -n $AKSNAME -k 1.13.5 -l $LOC \
  --node-count 2 --generate-ssh-keys \
  --network-plugin azure \
  --network-policy azure \
  --service-cidr 10.41.0.0/16 \
  --dns-service-ip 10.41.0.10 \
  --docker-bridge-address 172.17.0.1/16 \
  --vnet-subnet-id \$SUBNETID \
  --service-principal \$APPID \
  --client-secret \$PASSWORD"


pe "az network public-ip create -g $RG -n $AGPUBLICIP_NAME -l $LOC --sku Standard --no-wait"

pe "az network application-gateway create \
  --name $AGNAME \
  --resource-group $RG \
  --location $LOC \
  --min-capacity 2 \
  --frontend-port 80 \
  --http-settings-cookie-based-affinity Disabled \
  --http-settings-port 80 \
  --http-settings-protocol Http \
  --routing-rule-type Basic \
  --sku WAF_v2 \
  --private-ip-address 10.42.3.12 \
  --public-ip-address $AGPUBLICIP_NAME \
  --subnet $APPGWSUBNET_NAME \
  --vnet-name $VNET_NAME"


# Either wait or use the previously created cluster at Setup
pe "kctx buildwaf-admin"

# Get Nodes
pe "k get nodes -o wide"



# Setup Helm First
# pe "k create serviceaccount --namespace kube-system tiller-sa"
# pe "k create clusterrolebinding tiller-cluster-rule --clusterrole=cluster-admin --serviceaccount=kube-system:tiller-sa"
# pe "helm init --tiller-namespace kube-system --service-account tiller-sa"
# p "helm repo add application-gateway-kubernetes-ingress https://azure.github.io/application-gateway-kubernetes-ingress/helm/"
# helm repo add application-gateway-kubernetes-ingress https://azure.github.io/application-gateway-kubernetes-ingress/helm/
# p "helm repo update"
# helm repo update


# Show APP GW config file
pe "code agw-helm-config.yaml"

# Install App GW Ingress Controller
pe "helm install --name $AGNAME -f agw-helm-config.yaml application-gateway-kubernetes-ingress/ingress-azure"

# Check created resources
pe "k get po,svc,ingress,deploy,secrets"
# pe "helm list"


# Deploy Front-End
pe "code build19-web.yaml build19-ingress-web.yaml"

pe "k apply -f build19-web.yaml"
pe "k apply -f build19-ingress-web.yaml"

# Deploy Back-End
BUILD_RG="build-waf"
STORAGE_NAME="build05052019storage"
pe "STORAGE_KEY=\$(az storage account keys list -n $STORAGE_NAME -g $BUILD_RG --query [0].'value' -o tsv)"


pe "k create secret generic fruit-secret --from-literal=azurestorageaccountname=$STORAGE_NAME --from-literal=azurestorageaccountkey=\$STORAGE_KEY"

pe "k apply -f build19-worker.yaml"

pe "k get po,svc,ingress,deploy,secrets"

# Test App
BUILD_RG="build-waf"
BUILD_AGPUBLICIP_NAME="buildagpublicip"
pe "az network public-ip show -g $BUILD_RG -n $BUILD_AGPUBLICIP_NAME --query \"ipAddress\" -o tsv"

## Clean up
pe "clear"


k delete -f build19-worker.yaml > /dev/null
k delete secret fruit-secret > /dev/null
k delete -f build19-ingress-web.yaml > /dev/null
k delete -f build19-web.yaml > /dev/null

helm del --purge $AGNAME > /dev/null
helm reset > /dev/null
kubectl delete clusterrolebinding tiller-cluster-rule > /dev/null
kubectl delete -n kube-system serviceaccount tiller-sa > /dev/null


az ad sp delete --id $APPID --no-wait > /dev/null
az group delete -n $RG -y --no-wait > /dev/null
