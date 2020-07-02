# What this script does

This script sets up your SD card for the use of Android, L4T Ubuntu, emummc and makes sure that the SD card is still usable with HOS.
You can provide an Android and/or L4t Ubuntu image and the script will automatically flash those. If you dont provide images, you get the option to just create the partitions for Android and/or L4T Ubuntu.
The script will automatically add the necessary files to boot the images. 
You can also choose to add a partition for EmuMMC.  
When there is free space left on the SD card, you can extend each partition individually (realistically though you would only want to extend the L4T and Android user data partition), all remaining free space will get assigned to the data partition.
You can connect a switch in rcm mode to the pc and the script can directly write to the SD card that is inserted into it  (aka use switch as SD card reader). No need to ever remove the SD card from your switch again.
If doing so, you have to force power off the switch (hold power button for like 10s) after the script is done.  


## Requirements
- Linux distribution of your choice with bash, live CD/USB stick is sufficient. Virtual machine with USB passthrough should work aswell, but you are on your own then.
- the following programs must be installed (usually installed by default):
- gdisk, fdisk, sgdisk, sfdisk, parted, dd, mount, umount, losetup, awk, rm, rmdir, resize2fs, stat, mkfs.vfat, mkfs.ext4, unzip, printf, cp, echo, test, expr, partprobe, python3, python3-usb

## Basic usage:  
`sudo ./setup.sh`
`sudo ./setup.sh --android "path/to/android` to flash the given android image
`sudo ./setup.sh --l4t "path/to/l4t` to flash the given l4t image
`sudo ./setup.sh --l4t "path/to/l4t --android "path/to/android` to flash both images

You dont need to set any of the optional command line options, the script is interactive and will ask you, which device to use, wether or not to create an emummnc partition etc.

If you can't run the script, add execute permission to the files setup.sh, Tools/simg2img/simg2img and Tools/shofel2/shofel2.py with `chmod +x [file]`.

If some dependencies are missing, the script will tell you. Install the missing package with your package manager, on Ubuntu you would run `sudo apt install [missing package]`.

## Access hos_data partition from Windows
If you connect the SD card to a Windows system, Windows will throw a bunch of errors at you and eventually gives you access to the partition.  
The EmuMMC partition will appear aswell and seems to be empty. MAKE SURE TO NOT WRITE ANYTHING TO THAT PARTITION. DONT CLICK "Scan and fix removable disk".

If you want proper access to (and only to) the hos_data partition, run the script with --fix-mbr-properly, set Windows system date to 01.01.2014, plug in the SD card, go to device manager, find the SD card, right click and select "update driver", click "Browse for driver software on your computer", click "Let me pick from a list of device drivers on my computer", click "have disk", browse to the cfadisk.inf file of the filter driver and install the driver. Reset Windows system date. You only have to do that once. Next time plug in the SD card, Windows will automatically mount the hos_data partition without throwing errors.

## Optional command line options  
### --android [value]  
Value can be  
- a path to an Android Oreo image named android-xxgb.img.  
- a path to a folder containing Android Pie images (boot.img, system.img, vendor.img, tegra210-icosa.dtb,recovery.img or twrp.img). If twrp.img is present it will get prioritized over recovery.img.  
- partitions-only. If value is partitions-only, the script will create partitions with a default size for Android Pie.  
If the path contains spaces, put it in double quotes.  
If you dont provide this option, the script will ask you, wether or not to add partitions for Android Pie.  
	
### --l4t [value]  
Value can be  
- a path to an Ubuntu L4T image named switchroot-l4t-ubuntu-xxxx-xx-xx.img.  
- partitions-only. If value is partitions-only, the script will create partitions with a default size for L4T Ubuntu.  
If the path contains spaces, put it in double quotes.  
If you dont provide this option, the script will ask you, wether or to add partitions for L4T Ubuntu.  

### --cfw
Installs Atmosphere CFW.

Use this option to automatically copy files (e.g. Atmosphere CFW, homebrew, etc.) to the data partition.  
If the path contains spaces, put it in double quotes.  

### --emummc [hidden] [size(mb)] [path/to/emummc.img]  
If this option set, The script will create a partition for an EmuMMC.  
If you dont set this options, the script will ask you, wether or not to add an EmuMMC partition.  
All of the three additional arguments in rectangular brackets are optional.  
If 'hidden' is set, emummc partition wont be added to mbr.  
If a size is specified, it overrides the default emummc partition size (useful if you want an emummc partition thats smaller than 32gb).  
If a path to an image is set, it will flash that image to the emummc partition (filename must match 'emummc.img').  
Examples:  
`--emummc hidden 10000 ./emummc.img` creates a hidden emummc partition of size 10000mb and flashes the given image  
`--emummc 100000 hidden` creates a hidden emummc partition of size 10000mb, doesn't flash an image  
`--emummc ./emummc` creates an emummc partition and flashes the given image  

### --device [value]  
Value can be  
- The path to the device you want to use. 
- switch. If value is switch, the script will look for a switch in RCM mode attached to the pc and try to use the inserted SD card. If no SD card is inserted or it fails to detect a switch in RCM mode, the script will abort.
If you dont provide this option, the script will list all available storage devices. You can choose the device you want to use.  

### --no-format
If this option is set, the script will not format the SD card and instead only flashes the provided images/files. The necessary Partitions must already present and big enough.  
Not compatible with --l4t partitions-only, --emummc and --android partitions-only.  

## Advanced options:  
### --no-ui  
If this option is set, there will be no user interaction. THERE WILL BE NO WARNING ABOUT DATALOSS. YOU WILL NOT BE ASKED, IF YOU WANT TO CONTINUE, BEFORE THE DEVICE IS FORMATTED.  
When --no-ui is set, you must provide a device using --device.
Useful if you intend to run this script form another script.  

### --no-startfiles  
If this option is set, the script will not copy any files necessary to boot horizon, l4t or android to the data partition (hos_data).

### --fix-mbr
If this option is set, the script will fix the hybrid mbr on the SD card. Sets up the mbr so that the hos_data partition appears in Windows.  
Keep in mind that the emummc partition will appear aswell. Make sure to not write anything to the emummc partition and to not click "scan and fix removable disk" when it asks you. Windows will throw a whole bunch of warnings and errors at you, but eventually gives you access to the hos_data partition.  
Doesn't work with any other option.

### --fix-mbr-properly
Same as --fix-mbr. Sets up the mbr the proper way. Windows wont detect the hos_data partition due to some weird behaviour of the windows driver for removable storage devices.  
Use this, if you use the filter driver (makes the sd card appear as hard drive). No errors - it just works as intended.


### --f [value]  
Value can be  
- a path to a zip file. The content of the provided zip file will get copied to the data partition (hos_data) automatically. Use --f [value] multiple times to add more than one zip file. 


## Usage example:  
`sudo ./setup.sh`  

`sudo ./setup.sh --android "/home/user/downloads/android-16Gb.img" --l4t partitions-only --f "/home/user/downloads/Atmosphere.zip"`  

`sudo ./setup.sh --no-ui --device "dev/sdb" --android "/home/user/downloads/switchroot-l4t-ubuntu-2020-01-21.img" --emummc -f "/home/user/downloads/Atmosphere.zip"`  

`sudo ./setup.sh --fix-mbr`
