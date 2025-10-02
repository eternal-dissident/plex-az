# plex-az
Plex Media Server on Azure (VM + Storage Container mount)

## Setup
This repository contains helper scripts to set up Plex Media Server on Azure.  
- `make_vm.sh` deploys a VM to Azure that will host the server (it is assumed that storage account and container already exist)
- `setup.sh` commands that need to be executed on the VM to setup Plex Media Server and blobfuse2 service
- `blobfuse2.yaml` config file for blobfuse2, just drop it in a home directory on the VM
- `blobfuse2.service` same as above, will be copied to `/etc/systemd/system` by `setup.sh`  


Populate `config` with proper values before running `make_vm.sh`. Also go through `blobfuse2.*` files and replace `STORAGE_ACCOUNT_NAME`, `STORAGE_ACCOUNT_KEY`, `CONTAINER_NAME`, and `VM_ADMIN_USERNAME` where appropriate. 

After executing `make_vm.sh` and `setup.sh`, you can continue with Plex Media Server setup through local browser by running the following command:
```bash
ssh -i $VM_SSH_KEY_PATH -L 8888:127.0.0.1:32400 $VM_ADMIN_USERNAME@$VM_PUBLIC_IP
```

`VM_PUBLIC_IP` should have been printed at the end of `make_vm.sh`. 

After setting up the `ssh` port forwarding, you can navigate to `http://127.0.0.1:8888` to finish the setup. After this initial setup, you will be able to access Plex server through webapp, TV apps, phone apps, etc., with your Plex account from anywhere. 

To populate the server with media, simply upload your media to the storage container and set up a Library in Plex Server settings (refer to Plex Server docs for guidance and tips).

## Notes
*Content in this section assumes a use case where Plex server is used mostly for streaming video files in "direct play" mode. Emphasis on "direct play" mode as it assumes no pre-transcoding of media files ("optimize" feature in Plex, which puts a heavy write I/O load on `blobfuse2`), and no transcoding at playback (more on that in a note on video codecs).*

*Additional considerations might need to be made if your use case involves a lot of transcoding or if you have a media library with high cardinality (e.g. a music library with thousands of songs, or short-form video content)*

### blobfuse2: block_cache vs file_cache
We use `block_cache` with `blobfuse2` to optimize for streaming. This way the VM fetches media in 32 MB (configurable in `blobfuse2.yaml`) blocks, allowing to start playback almost immediately. Using `file_cache` instead will make the VM fetch entire media file locally before starting playback, which can take a while.

---

### Storage Containers vs Managed Disks
VM + Storage Container mount setup **might** result in lowest costs to run the server when compared to other ways of setting up the server on Azure (e.g. VM + Managed Data Disks).

`blobfuse2`/`rclone`/other tools that allow you to mount a remote (generally) work through REST APIs. Azure Storage Containers charge you based on the amount of api calls you make. That's why we are setting `block-size-mb` to 32 MB (default 8 MB). You might have to "finetune" the block size value dynamically based on access patterns, library size, etc. For example, if we are streaming a 50 GB video (start to finish), increasing `block-size-mb` within `blobfuse2` from 8 MB to 32 MB will reduce the number of api calls (from the VM hosting the server to storage container where media files live) to fully stream the movie from roughly 6.2k (50,000/8) to 1.5k. 

The most convenient way to tune `block-size-mb` setting is to open a live chart of storage container API calls during periods of high server load, and tweak the setting in the `blobfuse2.yaml` file on the VM (don't forget to restart `blobfuse2` service via `systemctl`). Generally, you can change this setting non invasively with respect to clients with active streaming sessions - Plex clients pre-fetch media blocks from the VM, providing enough playback buffer for the `blobfuse2` to restart with updated `block-size-mb` setting without interrupting active playback.

Keep in mind that increasing the block size will add/increase the delay between client "clicking play button" and the playback actually starting. That is because `blobfuse2` "pre-fetches" a certain number of blocks before they are actually needed, so larger block sizes -> more time spent waiting to prefetch blocks. Generally, a few extra seconds in latency do not matter in light of cloud bill savings, but make sure that is true for your use case.

If your media library contains a lot of files (i.e. high cardinality) that get frequent hot metadata reads, you might be upset with your cloud bill unless you use managed disks instead of containers or further optimize (1) caching of block data on the VM, and (2) Plex Media Server settings that control how frequently library scans and other tasks that might access file's metadata are performed.

---

### Video Codecs: Optimizing Storage, Egress, Compute, and Other Cost Drivers of Cloud Services

#### Intro
When I was just setting up the server, I knew that one of the most important characteristics of a video file is the codec. In the context of hosting Plex Media Server on Azure (or cloud in general), understanding codecs is obligatory to be able to optimize your cloud bill. I never had time to do a somewhat in-depth research on video codecs, but have learned a lot from observing the bandwidth, cpu load, and cloud bill of `plex-az` setup across a wide range of codecs (H.264/H.265/VP9/AV1/etc) and Plex client apps (browser/desktop/mobile/TV).

P.S. `plex-az` is just a small, fun side project the cost of which I am so far able to cover with free Azure credits. With that being said, content in this note on codecs might lack depth and/or references. The rest of this note contains "rules of thumb" I have developed over time by running an instance of the server and observing its performance and the cloud bill. Use it as a primer, but always do your own research considering the specifics of the use case at hand.

#### Cost of `plex-az` (on Azure)
When using the VM + Storage Container mount, you can think about the total cost by breaking it into the following components:
- **API calls** (between the VM and storage container) - already discussed previously;
- **Persistent storage** (baseline cost to store media files in storage container) - can vary greatly with different storage settings like redundancy, availability zones, geo, etc. I use hot storage with minimal redundancy and availability in eastus2 region and use a rule of thumb to estimate this cost: it costs roughly $20 to store 1TB for a month. This can be optimized by using reserved capacity and changing access tier (hot/cool/cold/etc) of individual media files based on access patterns. 
- **Compute** - if you ensure that 100% of media can be streamed to your clients without transcoding ("direct play" mode), a $7/mo burstable VM can get you further than might seem initially. You just need to resize the VM (manually or automatically) strategically to facilitate periods of high CPU needs (transcoding, scheduled tasks to "analyze" media files). The time it takes to resize an active VM instance varies, but similarly to tuning `block-size-mb` parameter, I have been generally able to resize the VM without disrupting the playback of active streaming sessions (i.e. playback buffer on the client lasts long enough to cover Plex server downtime during resizing)
- **Egress** (traffic from the VM hosting the server and clients) - Azure provides 100 GB of free egress a month, so if your clients are streaming less than 100 GB a month, you have one less thing to worry about. After 100 GB, egress pricing can vary a lot, but for traffic from Azure services in North America or Europe it is currently around $0.09/GB by "default" but can potentially be optimized with special routing settings.
- **Ingress** (outside the scope of this repo, just an honorable mention) - generally, ingress is free on Azure. However, container storage billing for number of API calls still applies. For example, let's say that you use `rclone` to upload media files to Azure storage container from somewhere else (i.e. your laptop). Similarly to `blobfuse2`, `rclone` uses REST APIs to interact with Azure storage containers and works with default chunk size of 4 MB (meaning it would take ~12.5k api calls to upload a 50 GB file). In this particular scenario, you can reduce the number of api calls by setting `--azureblob-chunk-size` ([docs](https://rclone.org/azureblob/#azureblob-chunk-size)) to a value higher than default 4 MB for relevant `rclone` commands.

This is a simplified breakdown, final figures depend on many configurable parameters and usage load. Generally, it seems that you can run a server with a small (< 1 TB) media library for friends and family (egress < 100 GB per month) without any free Azure credits and have the total monthly cost be below or in line with a "premium" tier streaming service subscription (highest tier of subscription on Netflix is currently ~$25/mo).

#### Choosing a video codec
If your use case for Plex Server is to stream video files, sooner or later you will be presented with 4+ options to download a video (i.e. a YouTube video with `yt-dlp`). These different video formats usually have the same resolution, identical quality when you download and play them on your PC, but very different file sizes (up to 50% difference in file size across major codecs).

A "video file" is just a container (MP4/MKV/MOV/WEBM/etc) with a video stream and an audio stream, sometimes subtitles, title covers, thumbnails, and other metadata are embedded within the container as well (usually they are stored in standalone .srt/.vtt/.jpg/.etc files alongside video containers instead of being embedded directly). Choice of video encoding codec will have the greatest effect on the final video file size (holding other features like resolution, fps and encoding of audio stream constant). Subsequently, the choice of video codec can have a great effect on the cost of cloud infra that hosts Plex server.

Do not confuse video codecs (H.264/H.265/VP9/AV1/etc) and container formats (MP4/MKV/MOV/WEBM/etc) - you can encode raw video stream with any codec and put it into many different container formats (i.e. encode once with AV1 and mux into MP4/MKV/WEBM) without any issues; you can also encode the same raw video stream with many different codecs and put them into the same container format (i.e. encode with H.264 and AV1 and mux into two separate MKV containers). Remuxing the same streams between different containers usually does not affect the final file size that much (e.g. from an .mkv with H.264 video stream and M4A audio stream to an .mp4 with the same exact streams). Ultimately, the codec used to encode the video stream has the greatest impact. 

There are a lot of differences between major video codecs, for simplicity just keep in mind that major codecs are H.264 (aka AVC) --> H.265 (aka HEVC) --> VP9 --> AV1. The arrows indicate how efficient the compression is and how widely supported the codecs are by clients. So a video stream encoded with H.264 can be up to 50% larger in size than an identical stream in AV1 while having mostly identical visual quality, but H.264 can be played directly by virtually any client while AV1 stream might need to be transcoded at playback by the server.

Previous sentence contains the gist of the video codec choice dilemma. Initially, you might be tempted to just download/transcode all your library in AV1 format: this way you save on storage and egress. However, the reality is that not all Plex client apps support AV1 encoding (e.g. some old TVs), forcing the server to transcode from AV1 to a compatible format (most likely H.264) at runtime. As a result, you can still transcode everything to AV1 and save on storage, but depending on your clients you might end up with the same egress and higher server compute needs than if you were to store in H.264.

With all of that in mind, we can try to deduce the "rule of thumb" for video codec choice with the following points:
- if your library and load are small just keep everything in H.264 and you will most likely never have to worry about whether or not a specific codec is supported by your clients.
- if you have large library, but have granular control and insight into all the clients of the server, you can just pick the most efficient encoding format given the constraints. This might be the case if you run the server just for yourself and family and can "manually" keep track of all the clients connected to the server and what codecs they support.
- if you have large library and a set of clients that is always changing, you are going to want to explore 2 options: (1) beefing up the compute to be able to store everything in format like AV1 (high compression efficiency but lower client support) and transcoding at playback when needed; (2) pre-transcoding files with a set of different codecs and storing all versions side by side. The second option allows to keep the compute minimal at the expense of higher storage cost. Ideally, you would want to somehow dynamically determine which videos to transcode to which formats based on access patterns and codec support among your clients. This way, you save on egress by having Plex stream more modern formats (e.g. AV1) to supporting clients, while still keeping H.264 to be able to stream to "legacy" clients without transcoding at playback.