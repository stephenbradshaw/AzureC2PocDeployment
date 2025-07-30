# Azure C2 POC Deployment templates

This repo contains [Azure Resource Manager](https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/overview) templates that can be used to quickly deploy a POC C2 environment to allow demonstration and testing of C2 fronting of implant traffic with Azure services as discussed in posts on my blog [here](https://thegreycorner.com/tags.html#azure-service-fronting). 

These template allow resources to quickly be deployed to your Azure account in a given resource group using the [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/get-started-with-azure-cli?view=azure-cli-latest), allowing you to play with these ideas whilst minimising cost and allowing easy cleanup (just delete the resource group once you're done).

The templates setup a minimal set of low cost resources to support this testing in region `westus2`.

For more information, see my blog post [here](https://thegreycorner.com/2025/06/04/azure_c&c_poc_infra_deployment.html).


# Available templates

There are currently two different sets of templates available here:
* The `base` template which deploys the POC C2 compute instance (using [Sliver](https://github.com/BishopFox/sliver)) and basic network resources that are used as core supporting components by the domain fronting POCs
* The `functionapp` template which deploys an [Azure Function App](https://azure.microsoft.com/en-us/products/functions) to forward implant traffic as discussed on my blog [here](https://thegreycorner.com/2025/05/07/azure-service-C2-forwarding.html)
* The `azurefd` template that deploys an [Azure Front Door](https://azure.microsoft.com/en-au/products/frontdoor) that forwards traffic through the previously discussed Function App to the C2 server
* The `apim` template that deploys an [API Management Service](https://azure.microsoft.com/en-us/products/api-management) API that can forward traffic through the configured Function App to the C2 server


# Creating the Resource Group

These resources will be deployed in the `C2VMRG` resource group, that you can create using the [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/get-started-with-azure-cli?view=azure-cli-latest) like so.

```
az group create --name C2VMRG --location westus2
```

Once this has been created we next need to deploy the base resources.

# Creating base resources

The related files for this deployment template sit in `./base`

This template will create the following Azure resources in the resource group:
* An Ubuntu 22.04 Linux VM of type `Standard_B1s`, with a public IP address and a local user with name `ubuntu`
* A virtual network the VM will be attached to, allowing private cloud traffic to the VM from other Azure resources we can create in the resource group
* A Network Security Group attached to the VM that allows SSH traffic from your public IP address and pivate traffic from your virtual network to port 80 to allow implant traffic forwarding

## User data script
There is also a user data script that will run on VM startup and do the Operating System install, as well as setting up Apache in forwarding mode on port 80 that will act as a filter for incoming traffic and forward all valid traffic to local port 8888. It will also install a Sliver server that should start a listener job on port 8888 to receive this. If this doesn't start correctly for whatever reason you can connect using the sliver client `/opt/sliver/sliver-client` and run the command `http -l 8888 -p` to start the job once the server is running and configured.

This install script can take a little while to finish execution, so make sure you check for the file `/home/ubuntu/setupdone` that is created at the end of the script execution before trying to fix anything. 

The contents of the install script is listed in the `install.sh` file, but needs to be base64 encoded and placed in the `userData.value` section of the `parameters.json` file before deployment. If you want to change the contents of the script, be sure to update this field before deployment - you can encode in the right format using a command like so:

```
cat install.sh | base64 -w 0
```

## Settings to change before deployment

Before deployment, you also need to identify your public IP address and create an SSH key to use when accessing your VM.

A key can be created using a command similar to the following, which will create a key named `id_ed25519_azure` in your local ssh directory.

```
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_azure
```

You then need to replace the following strings in `parameters.json` with your own values.

* `<YOUR_IP_ADDRESS_HERE>` - replace with the public facing IP address of the machine you will use to ssh to your Azure VM - this is added to a rule in your VMs network security group allowing TCP port 22 traffic from this address
* `<YOUR_PUBLIC_KEY_HERE>` - replace with the contents of your ssh public key file, in my case this was the contents of file `id_ed25519_azure.pub`
* `<YOUR_DNS_LABEL_HERE>` - replace with a prefix to be used as part of the DNS name that will be associated with the VMs public IP address, which will be in the format of `<YOUR_DNS_LABEL_HERE><RANDOM_CHARACTERS>.westus2.cloudapp.azure.com`



Assuming a public key file of `~/.ssh/id_ed25519_azure.pub`, the following commands run can be used to automatically perform the necessary replacements.

```
export PUBLIC_IP=$(curl ipinfo.io/ip)
sed -i "s/<YOUR_IP_ADDRESS_HERE>/$PUBLIC_IP/g" parameters.json

export PUBLIC_KEY=$(cat ~/.ssh/id_ed25519_azure.pub | sed 's/\//\\\//g')
sed -i "s/<YOUR_PUBLIC_KEY_HERE>/$PUBLIC_KEY/g" parameters.json

export DNS_LABEL=mytestsystem
sed -i "s/<YOUR_DNS_LABEL_HERE>/$DNS_LABEL/g" parameters.json
```


## Deploying

With that done, you can actually deploy the resources using the following command (with directory `./base` as your present working directory).

```
az deployment group create --resource-group C2VMRG --template-file template.json --parameters @parameters.json
```


## Accessing the VM after deployment

Once the command execution has completed, check the [Resource Group section of the Azure Portal](https://portal.azure.com/#browse/resourcegroups) for the `C2VMRG` resource group, and check the VM resource within to confirm it has been correctly created. Grab the public IP address of the VM, and setup an ssh config entry as per the simple example below.

The DNS name that has been created for your VM can be retrieved using the following az cli command:

```
az network public-ip list -g C2VMRG --query "[].dnsSettings.fqdn | [0]"
```

The public IP address of the vm can also be grabbed like so using the az cli:

```
az vm list-ip-addresses -g C2VMRG --query "[].virtualMachine[].network.publicIpAddresses[].ipAddress | [0]"
```


```
Host azurevm
    hostname <PUBLIC_IP_ADDRESS>
    identityfile ~/.ssh/id_ed25519_azure
    user ubuntu
```

You then should be able to ssh into the instance using a command similar to `ssh azurevm`.


# Creating an Azure Function App for C2 fronting

The related files for this deployment template sit in `./functionapp`.

This template deploys a function app to forward implant traffic to the C2 VM created using the `base` resource template discussed above as documented in this blog post [here](https://thegreycorner.com/2025/05/07/azure-service-C2-forwarding.html).

Before deploying, you need to choose a globally unique function app name and replace the instances of the string `<FUNCTION_APP_NAME_HERE>` in `parameters.json` with that name.


Commands line the following can be used to perform the replacement, assuming a function app name of `randofunctionappname1234567abcdef`:
```
export FUNCTION_APP_NAME=randofunctionappname1234567abcdef
sed -i "s/<FUNCTION_APP_NAME_HERE>/$FUNCTION_APP_NAME/g" parameters.json
```


Then, create the function app resource using the following command:

```
az deployment group create --resource-group C2VMRG --template-file template.json --parameters @parameters.json
```

One this command has finished, the Function App resource should exist in your Azure account, but still needs to have the function code deployed to it in order for it to operate correctly.

The code we need to deploy is available [here](https://github.com/stephenbradshaw/AzureFunctionC2Forwarder). Clone it locally, set your present working directory to the cloned source and create a deployment zip file as follows:

```
zip -r /tmp/dep.zip ./function_app.py ./host.json ./requirements.txt
```

Then, deploy the zip file to your app as follows, replacing `<FUNCTION_APP_NAME_HERE>` in the command with the unique name you chose for your function app.

```
az functionapp deployment source config-zip -g C2VMRG -n <FUNCTION_APP_NAME_HERE> --src /tmp/dep.zip
```

You can get the function app host name like so:
```
az functionapp list -g C2VMRG  --query '[0].hostNames[0]'
```

Check the [blog post](https://thegreycorner.com/2025/05/07/azure-service-C2-forwarding.html) for more context on how this works.



# Creating an Azure Front Door instance for C2 fronting

The related files for this deployment template sit in `./azurefd`. For more information on the Azure Front Door setup, see the [blog post here](https://thegreycorner.com/2025/06/25/azure-service-c2-forwarding-part2.html).

This template deploys an Azure Front Door instance that will forward traffic to an existing Azure Function App (that forwards to a C2) similar to the one created using the process mentioned above. This will essentially provide an new entry point (with name and SSL certificate within the `azurefd.net` domain) for implant traffic that can be used in addition to or instead of the Function App one.

Before deploying, you need to replace the string `<FUNCTION_APP_NAME_HERE>` in `parameters.json` with the name of the Azure Function App you created previously (`randofunctionappname1234567abcdef` in the example above) and replace the string `<FRONT_DOOR_ENDPOINT_NAME_HERE>` with the endpoint name for your Front Door instance (this value will comprise part of the final endpoint URL so choose wisely).

Commands line the following can be used to perform the replacement, assuming a function app name of `randofunctionappname1234567abcdef` and a Front Door endpoint name of `testfd`:

```
export FUNCTION_APP_NAME=randofunctionappname1234567abcdef
sed -i "s/<FUNCTION_APP_NAME_HERE>/$FUNCTION_APP_NAME/g" parameters.json

export ENDPOINT_NAME=testfd
sed -i "s/<FRONT_DOOR_ENDPOINT_NAME_HERE>/$ENDPOINT_NAME/g" parameters.json
```

The resources can then be created using the normal deployment command.

```
az deployment group create --resource-group C2VMRG --template-file template.json --parameters @parameters.json
```

Once the deployment is done, the command will include the generated domain name in the `frontDoorEndpointHostName` output field, and you can also get it from within the Azure portal, or using the command below:

```
az afd endpoint list -g C2VMRG --profile-name MyFrontDoor --query '[].hostName | [0]'
```

# Creating an API Management service instance for C2 fronting

Rough instructions only for the moment. This creates an API Management service that can front the Function App deployment mentioned above. Set that up first.

Replace parameters in file. API_NAME needs to be globally unique, I might fix this in the template to generate the name randomly to help here
```
export API_NAME=myapi987654321
sed -i "s/<API_NAME>/$API_NAME/g" parameters.json

export NOTIFY_EMAIl='myemail@whatever.com'
sed -i "s/<NOTIFY_EMAIL>/$NOTIFY_EMAIl/g" parameters.json
```

Deploy

```
az deployment group create --resource-group C2VMRG --template-file template.json --parameters @parameters.json
```


Monitor the status of the deployment - it takes a while, and usually the the process will not complete until the deployment is done - you will also get an email to the configured address notifying you. Its also possible to do incremental checks on progress using the folliwng command, looking for the "Succeeded" status to be returned.

```
az apim list -g C2VMRG --query '[0].[name, provisioningState]'
```


Once deployed you need to create an API instance

```
export API_SERVICE_NAME=$(az apim list --query '[0].name' | jq -r)
export FAHOST=$(az functionapp list --query '[0].hostNames[0]' | jq -r)
az apim api import -g C2VMRG -n $API_SERVICE_NAME --specification-format OpenApiJson --api-id myapi --path '/' --display-name 'MyAPI' --subscription-required false  --service-url https://$FAHOST/  --api-type http --protocols http https --description 'My API' --specification-url https://raw.githubusercontent.com/stephenbradshaw/AzureC2PocDeployment/refs/heads/main/apim/azure_api_management_service_def.json
```


Once deployed you can retrieve the URL at which the frontend will be available as follows

```
az apim list --query '[0].gatewayUrl'
```


# Deleting the resources

Once you're done with the POC environment, you can delete the dedicated Resource Group and all its contents as follows:

```
az group delete --name C2VMRG
```



