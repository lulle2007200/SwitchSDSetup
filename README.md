This script sets up a SD card for Nintendo Switch homebrew

Usage:

sudo ./setup.sh '[Arg1]' '[Arg2]'

The arguments are optional, the order doesnt matter.
You can pass a path to a l4t ubuntu image named switchroot-l4t-ubuntu-xxxx-xx-xx.img and a path to a folder containing android images (boot.img, vendor.img, system.img, tegra-210.dtb, recovery.img or twrp.img (if twrp.img is present, it will get prioritized over recover.img)).
The script recognizes the images by their names and doesnt check wether or not they are valid - thats up to you.

If you provide images, you get the option to create partitions for them and also copy them to the respective partitions.
If you dont provide images, you still get the options to create partitions for Android and/or l4t Ubuntu.

The script lists all available storage devices at the beginning, you can select the one you want to use.
You get the option to extend each partition if there is free space left. Realistically though, you would only want to extend the Data, l4t, android system and android userdata partition.