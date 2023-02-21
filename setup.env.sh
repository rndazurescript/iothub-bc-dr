
#!/bin/bash

## YOU CAN RUN THIS SCRIPT FROM THE AZURE CLI OR FROM THE AZURE CLOUD SHELL
## ENSURE YOU MAKE IT AN EXECUTABLE SCRIPT BY RUNNING: chmod +x setup.env.sh
## RUN THE SCRIPT BY RUNNING: . setup.env.sh or source setup.env.sh (if you want the env vars available in the current shell)

export SUFIX=bcdr
export RSG=iot-$SUFIX
export RSG_NE=iot-$SUFIX-ne
export HUB=iot-$SUFIX-hub
export ACR=iotacr$SUFIX
export VNET_WE=iot-$SUFIX-vnet-we
export VNET_NE=iot-$SUFIX-vnet-ne
export VM_NAME='edgevm-'$SUFIX

echo "Preparing testing environment for BC/DR demo."
echo "SUFIX=$SUFIX"
echo "RSG=$RSG"
echo "RSG_NE=$RSG_NE"
echo "HUB=$HUB"
echo "VNET_WE=$VNET_WE"
echo "VNET_NE=$VNET_NE"
echo 

echo "Creating resource group $RSG"
echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
## CREATE RESOURCE GRUOP
az group create --name $RSG --location westeurope
az group create --name $RSG_NE --location westeurope

echo "Creating IoT Hub $HUB"
echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
## PROVISION IOT HUB
az iot hub create --resource-group $RSG --name $HUB --sku S1 --partition-count 4

echo "Creating IoT Edge Device 'edge101' and IoT Device 'thermostat1'"
echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
## REGISTER DEVICES
az iot hub device-identity create --device-id edge101 --edge-enabled --hub-name $HUB --resource-group $RSG
az iot hub device-identity create --device-id thermostat1 --hub-name $HUB --resource-group $RSG

## SHOW DEVICES CONN STRINGS
az iot hub device-identity connection-string show --device-id edge101 --hub-name $HUB --resource-group $RSG
az iot hub device-identity connection-string show --device-id thermostat1 --hub-name $HUB --resource-group $RSG

echo "Creating IoT Edge VM"
echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
## DEPLOY VM 
az deployment group create \
--resource-group $RSG \
--template-uri "https://raw.githubusercontent.com/Azure/iotedge-vm-deploy/1.4/edgeDeploy.json" \
--parameters dnsLabelPrefix=$VM_NAME \
--parameters adminUsername='azureUser' \
--parameters deviceConnectionString=$(az iot hub device-identity connection-string show --device-id edge101 --hub-name $HUB --resource-group $RSG -o tsv) \
--parameters authenticationType='password' \
--parameters adminPasswordOrKey="vmPass#word"

echo "Configuring VM SSH on port 2223"
echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
## CONFIGURE VM SSH ON PORT 2223
VM_NAME=$(az vm list -g $RSG --query "[].name" -o tsv)
az vm run-command invoke -g $RSG  -n $VM_NAME --command-id RunShellScript --scripts "sudo sed -i -e 's/#Port 22/Port 2223/' /etc/ssh/sshd_config"
az vm run-command invoke -g $RSG  -n $VM_NAME --command-id RunShellScript --scripts "sudo cat /etc/ssh/sshd_config"
az vm run-command invoke -g $RSG  -n $VM_NAME --command-id RunShellScript --scripts "sudo systemctl restart ssh"

echo "Configuring NSG. Allow port 2223 for SSH and block all outbound traffic."
echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
## CONFIGURE NSG
NSG_NAME=$(az network nsg list -g $RSG --query "[].name" -o tsv)
az network nsg rule create --name AllowSSH_2223 --nsg-name $NSG_NAME --priority 2000 --resource-group $RSG --access Allow --source-port-ranges 0-65535 --destination-port-ranges 2223  --direction Inbound --protocol Tcp
az network nsg rule create --resource-group $RSG --nsg-name $NSG_NAME --name BlockInternetTraffic --priority 100 --direction Outbound --access deny --destination-address-prefix Internet --destination-port-range '*' --source-address-prefixes '*' --source-port-range '*'

echo "Configuring VNETs"
echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
## SETUP VNETS
VNET_VM=$(az network vnet list -g $RSG --query "[].name" -o tsv)
az network vnet create --resource-group $RSG --name $VNET_WE --address-prefix 10.1.0.0/16 --subnet-name default --subnet-prefix 10.1.0.0/24 --location westeurope
az network vnet create --resource-group $RSG_NE --name $VNET_NE --address-prefix 10.2.0.0/16 --subnet-name default --subnet-prefix 10.2.0.0/24 --location northeurope
 
echo "Configuring VNET peering"
echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
VNET_NE_ID=$(az network vnet show -g $RSG_NE -n $VNET_NE --query id -o tsv)
az network vnet peering create --name vnet-onprem-to-vnet-we --resource-group $RSG --vnet-name $VNET_VM --remote-vnet $VNET_WE --allow-vnet-access
az network vnet peering create --name vnet-onprem-to-vnet-ne --resource-group $RSG --vnet-name $VNET_VM --remote-vnet $VNET_NE  --remote-vnet $VNET_NE_ID --allow-vnet-access


echo "Configuring Storage Account"
echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
## SETUP STORAGE ACCOUNT
az storage account create --name iotstg$SUFIX --resource-group $RSG --location westeurope --sku Standard_LRS --kind StorageV2

az acr create --resource-group $RSG --name $ACR --sku Premium --admin-enabled true
az acr import --resource-group $RSG --name $ACR --source mcr.microsoft.com/azureiotedge-simulated-temperature-sensor:latest --image azureiotedge-simulated-temperature-sensor:latest

## MANUAL ACTIONS
# - ENABLE PRIVATE LINK FOR WE
# Ref: https://learn.microsoft.com/en-us/azure/iot-hub/iot-hub-public-network-access

echo "To connect to the VM run: ssh -p 2223 azureUser@$VM_NAME.westeurope.cloudapp.azure.com password: vmPass#word"
echo "You will need to MANUALLY create the private endpoints in the WE VNET (and NE when required) for the IoT Hub"
echo "ALSO you need to create the PE for the ACR"
echo "You will need to configure the IoT Edge device (edge101) to deploy the TemperatureSensorModule from the market place"