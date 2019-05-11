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

PREFIX="build-egress"
RG="${PREFIX}-rg"
LOC="westus2"
AKSNAME="${PREFIX}"
VNET_NAME="${PREFIX}vnet"
AKSSUBNET_NAME="${PREFIX}akssubnet"
SVCSUBNET_NAME="${PREFIX}svcsubnet"
FWSUBNET_NAME="AzureFirewallSubnet"
FWNAME="${PREFIX}fw"
FWPUBLICIP_NAME="${PREFIX}fwpublicip"
FWIPCONFIG_NAME="${PREFIX}fwconfig"
FWROUTE_TABLE_NAME="${PREFIX}fwrt"
FWROUTE_NAME="${PREFIX}fwrn"
K8S_VERSION=1.13.5
AZURE_ACCOUNT_NAME=<YOUR_SUBSCRIPTION>
SUBID=$(az account show -s $AZURE_ACCOUNT_NAME -o tsv --query 'id')

# Setup right subscription
az account set -s $AZURE_ACCOUNT_NAME

# Automatically print the SP values into $APPID and $PASSWORD, trust me
eval "$(az ad sp create-for-rbac -n ${PREFIX}sp --skip-assignment | jq -r '. | to_entries | .[] | .key + "=\"" + .value + "\""' | sed -r 's/^(.*=)/\U\1/')"


# Create Resource Group
pe "az group create --name $RG --location $LOC"

# Create Virtual Network & Subnets for AKS, k8s Services, ACI, Firewall and WAF
pe "az network vnet create \
    --resource-group $RG \
    --name $VNET_NAME \
    --address-prefixes 10.42.0.0/16 \
    --subnet-name $AKSSUBNET_NAME \
    --subnet-prefix 10.42.1.0/24"

pe "az network vnet subnet create \
    --resource-group $RG \
    --vnet-name $VNET_NAME \
    --name $FWSUBNET_NAME \
    --address-prefix 10.42.3.0/24"


# Create Public IP
pe "az network public-ip create -g $RG -n $FWPUBLICIP_NAME -l $LOC --sku Standard"
# Create Firewall
pe "az network firewall create -g $RG -n $FWNAME -l $LOC"
# Configure Firewall IP Config
# This command will take a few mins.
pe "az network firewall ip-config create -g $RG -f $FWNAME -n $FWIPCONFIG_NAME --public-ip-address $FWPUBLICIP_NAME --vnet-name $VNET_NAME"

pe 'FWPRIVATE_IP=$(az network firewall show -g $RG -n $FWNAME --query "ipConfigurations[0].privateIpAddress" -o tsv)'

pe "az network route-table create -g $RG --name $FWROUTE_TABLE_NAME"
pe "az network route-table route create -g $RG --name $FWROUTE_NAME --route-table-name $FWROUTE_TABLE_NAME --address-prefix 0.0.0.0/0 --next-hop-type VirtualAppliance --next-hop-ip-address \$FWPRIVATE_IP --subscription \$SUBID"

# Add Network FW Rules
pe "az network firewall network-rule create -g $RG -f $FWNAME --collection-name 'aksfwnr' -n 'netrules' --protocols 'TCP' --source-addresses '*' --destination-addresses '*' --destination-ports 9000 443 --action allow --priority 100"

# Add Application FW Rules
pe "az network firewall application-rule create -g $RG -f $FWNAME --collection-name 'aksfwar' -n 'fqdn' --source-addresses '*' --protocols 'http=80' 'https=443' --target-fqdns '*.azmk8s.io' 'aksrepos.azurecr.io' '*blob.core.windows.net' '*mcr.microsoft.com' 'login.microsoftonline.com' 'management.azure.com' '*ubuntu.com' --action allow --priority 100"

# Associate AKS Subnet to FW
pe "az network vnet subnet update -g $RG --vnet-name $VNET_NAME --name $AKSSUBNET_NAME --route-table $FWROUTE_TABLE_NAME"

pe "az aks create -g $RG -n $AKSNAME -k $K8S_VERSION -l $LOC \
  --node-count 2 --generate-ssh-keys \
  --network-plugin azure \
  --network-policy azure \
  --service-cidr 10.41.0.0/16 \
  --dns-service-ip 10.41.0.10 \
  --docker-bridge-address 172.17.0.1/16 \
  --vnet-subnet-id \$SUBNETID \
  --service-principal \$APPID \
  --client-secret \$PASSWORD \
  --no-wait"

# Get AKS Credentials so kubectl works
# pe "az aks get-credentials -g $RG -n $AKSNAME --admin"
 
# Or if you don't want to wait, jump into the cluster done at Setup
kctx build-egress-admin

# Get Pods
pe "k get pods --all-namespaces"

pe "k apply -f test-pod.yaml"


# Exec into Pod and Check Traffic
pe "k get po -o wide"
pe "k exec -it centos -- /bin/bash"

# Manually do
# pe "curl www.ubuntu.com"
# pe "curl superman.com"
# pe "exit"


# cleanup

k delete -f test-pod.yaml > /dev/null
az group delete -n $RG -y --no-wait
az ad sp delete --id $APPID





