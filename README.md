# plex-az
Plex Media Server on Azure (VM + Storage Container mount)

This repository contains helper scripts to set up Plex Media Server on Azure.  
- `make_vm.sh` deploys a VM to Azure that will host the server (it is assumed that storage account and container already exist)
- `setup.sh` commands that need to be executed on the VM to setup Plex Media Server and blobfuse2 service
- `blobfuse2.yaml` config file for blobfuse2, just drop it in a home directory on the VM
- `blobfuse2.service` same as above, will be copied to `/etc/systemd/system` by `setup.sh`  

---


We use `block_cache` with `blobfuse2` to optimize for streaming. This way the VM fetches media in 32MB blocks, allowing to start playback almost immediately. Using `file_cache` instead will make the VM fetch entire media file locally before starting playback, which can take a while.

VM + Storage Container mount setup results in relatively low cost to run the server (versus VM + Data Disk mount, for example).

Populate `config` with proper values before running `make_vm.sh`. Also go through `blobfuse2.*` files and replace `STORAGE_ACCOUNT_NAME`, `STORAGE_ACCOUNT_KEY`, `CONTAINER_NAME`, and `VM_ADMIN_USERNAME` where appropriate. 

After executing `make_vm.sh` and `setup.sh`, you can continue with Plex Media Server setup through local browser by running the following command:
```bash
ssh -i $VM_SSH_KEY_PATH -L 8888:127.0.0.1:32400 $VM_ADMIN_USERNAME@$VM_PUBLIC_IP
```

`VM_PUBLIC_IP` should have been printed at the end of `make_vm.sh`. 

After setting up the `ssh` port forwarding, you can navigate to `http://127.0.0.1:8888` to finish the setup. After this initial setup, you will be able to access Plex server through webapp, TV apps, phone apps, etc., with your Plex account from anywhere. 

To populate the server with media, simply upload your media to the storage container and set up a Library in Plex Server settings (refer to Plex Server docs for guidance and tips).