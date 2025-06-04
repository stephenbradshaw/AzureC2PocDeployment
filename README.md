# Azure C2 POC Deployment templates

This repo contains [Azure Resource Manager](https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/overview) templates that can be used to quickly deploy a POC C2 environment to allow demonstration and testing of C2 fronting of implant traffic with Azure services as discussed in posts on my blog [here](https://thegreycorner.com/tags.html#azure-service-fronting). 

These template allow resources to quickly be deployed to your Azure account in a given resource group using the [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/get-started-with-azure-cli?view=azure-cli-latest), allowing you to play with these ideas whilst minimising cost and allowing easy cleanup (just delete the resource group once you're done).

The templates setup a minimal set of low cost resources to support this testing in region `westus2`.


# Available templates

There are currently two different sets of templates available here:
* The `base` template which deploys the POC C2 compute instance (using [Sliver](https://github.com/BishopFox/sliver)) and basic network resources that are used as core supporting components by the domain fronting POCs
* The `functionapp` template which deploys an [Azure Function App](https://learn.microsoft.com/en-us/azure/azure-functions/functions-overview) to forward implant traffic as discussed on my blog [here](https://thegreycorner.com/2025/05/07/azure-service-C2-forwarding.html)


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

A key can be created using a command similar to the following:

```
ssh-keygen -t ed25519
```

I called my key `id_ed25519_azure`. 

You then need to replace the following strings in `parameters.json` with your own values.

* `<YOUR_IP_ADDRESS_HERE>` - replace with the public facing IP address of the machine you will use to ssh to your Azure VM - this is added to a rule in your VMs network security group allowing TCP port 22 traffic from this address
* `<YOUR_PUBLIC_KEY_HERE>` - replace with the contents of your ssh public key file, in my case this was the contents of file `id_ed25519_azure.pub`


## Deploying

With that done, you can actually deploy the resources using the following command (with directory `./base` as your present working directory).

```
az deployment group create --resource-group C2VMRG --template-file template.json --parameters @parameters.json
```


## Accessing the VM after deployment

Once the command execution has completed, check the [Resource Group section of the Azure Portal](https://portal.azure.com/#browse/resourcegroups) for the `C2VMRG` resource group, and check the VM resource within to confirm it has been correctly created. Grab the public IP address of the VM, and setup an ssh config entry as per the simple example below.


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

Check the [blog post](https://thegreycorner.com/2025/05/07/azure-service-C2-forwarding.html) for more context on how this works.

