# What this script does

The script sets up the partitions in a way that the SD card remains usable with Horizon OS without the need to format it gain.  
You can provide an Android and/or a L4t Ubuntu image with the command line options (see below) and the script will automatically set up partitions and copy the content of the images to the right partitions and the necessary files to boot the images to the data partition.  
You can also choose to add a partition for EmuMMC.  
When there is free space left on the SD card, you can extend each partition individually (realistically though you would only want to extend the L4T, Android user data and maybe the android system partition), all remaining free space will get assigned to the data partition.  

## Basic usage:  
sudo ./setup.sh  

## Optional command line options  
### --android [value]  
Value can be  
- a path to an Android Oreo image named android-xxgb.img.  
- a path to a folder containing Android Pie images (boot.img, system.img, vendor.img, tegra210-icosa.dtb,recovery.img or twrp.img). If twrp.img is present it will get prioritized over recovery.img.  
- partitions-only. If value is partitions-only, the script will create partitions with a default size for Android Pie.  
f the path contains spaces, put it in double quotes.  
If you dont provide this option, the script will ask you, wether or not to add partitions for Android Pie.  
	
### --l4t [value]  
Value can be  
- a path to an Ubuntu L4T image named switchroot-l4t-ubuntu-xxxx-xx-xx.img.  
- partitions-only. If value is partitions-only, the script will create partitions with a default size for L4T Ubuntu.  
If the path contains spaces, put it in double quotes.  
If you dont provide this option, the script will ask you, wether or to add partitions for L4T Ubuntu.  

### --f [value]  
Value can be  
- a path to a zip file. The content of the provided zip file will get copied to the data partition (hos_data) automatically. Use --f [value] multiple times to add more than one zip file.  
Use this option to automatically copy files (e.g. Atmosphere CFW, homebrew, etc.) to the data partition.  
If the path contains spaces, put it in double quotes.  

### --emummc  
If this option set, The script will create a partition for an EmuMMC.  
If you dont set this options, the script will ask you, wether or not to add an EmuMMC partition.  

### --device [value]  
Value can be  
- The path to the device you want to use.  
If you dont provide this option, the script will list all available storage devices. You can choose the device you want to use.  

## Advanced options:  
### --no-ui  
If this option is set, there will be no user interaction. THERE WILL BE NO WARNING ABOUT DATALOSS. YOU WILL NOT BE ASKED, IF YOU WANT TO CONTINUE, BEFORE THE DEVICE IS FORMATTED.  
When --no-ui is set, you must provide a device using --device.  

### --no-startfiles  
If this option is set, the script will not copy any files necessary to boot horizon, l4t or android to the data partition (hos_data).  

## Usage example:  
`sudo ./setup.sh`  

`sudo ./setup.sh --android "/home/user/downloads/android-16Gb.img" --l4t partitions-only --f "/home/user/downloads/Atmosphere.zip"`  

`sudo ./setup.sh --no-ui --device "dev/sdb" --android "/home/user/downloads/switchroot-l4t-ubuntu-2020-01-21.img" --emummc -f "/home/user/downloads/Atmosphere.zip"`  

__You can not have both, L4T Ubuntu and Android Oreo on the same SD card. Android will fail to boot.__
