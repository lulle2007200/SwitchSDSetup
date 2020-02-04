#!/bin/bash

#Project: SwitchSDSetup

#This program is free software: you can redistribute it and/or modify
#it under the terms of the GNU General Public License as published by
#the Free Software Foundation, either version 3 of the License, or
#(at your option) any later version.

#This program is distributed in the hope that it will be useful,
#but WITHOUT ANY WARRANTY; without even the implied warranty of
#MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#GNU General Public License for more details.

#You should have received a copy of the GNU General Public License
#along with this program.  If not, see <http://www.gnu.org/licenses/>.

#This script was written by github.com/lulle2007200. Make sure that i get credit, if you reuse, redistribute or modify it.
#I take no responsibility if this script causes damage to your
#device or dataloss (which it should not).

declare Size

declare -a Partitions
declare -a PartitionNames
declare -a PartitionFriendlyNames
declare -a MBRPartitions

declare -a PostPartCmds

declare PartPrefix=""

declare -a StartFiles
declare -a AdditionalStartFiles

declare Input


declare hos_data_sz_default=$((500*1024*1024))

declare l4t_sz_default=$((10*1024*1024*1024))

declare emummc_sz_default=$((29844*1024*1024))

declare vendor_sz_default=$((1*1024*1024*1024))
declare app_sz_default=$((2*1024*1024*1024))
declare lnx_sz_default=$((32*1024*1024))
declare sos_sz_default=$((64*1024*1024))
declare dtb_sz_default=$((1*1024*1024))
declare mda_sz_default=$((16*1024*1024))
declare cac_sz_default=$((700*1024*1024))
declare uda_sz_default=$((1*1024*1024*1024))

declare Help="Optional command line options\n \
--android '[value]'\n \
\tValue can be\n \
\t- a path to an Android Oreo image named android-xxGb.img.\n \
\t- a path to a folder containing Android Pie images (boot.img, system.img, vendor.img, tegra210-icosa.dtb, recovery.img or twrp.img). If twrp.img is present it will get prioritized over recovery.img.\n \
\t- partitions-only. If value is partitions-only, the script will create partitions with a default size for Android Pie.\n \
\tIf the path contains spaces, put it in double quotes.\n \
\tIf you dont provide this option, the script will ask you, wether or not to add partitions for Android Pie.\n \
\n \
--l4t '[value]'\n \
\tValue can be\n \
\t- a path to an Ubuntu L4T image named switchroot-l4t-ubuntu-xxxx-xx-xx.img.\n \
\t- partitions-only. If value is partitions-only, the script will create partitions with a default size for L4T Ubuntu.\n \
\tIf the path contains spaces, put it in double quotes.\n \
\tIf you dont provide this option, the script will ask you, wether or to add partitions for L4T Ubuntu.\n \
\n \
--f '[value]'\n \
\tValue can be\n \
\t- a path to a zip file. The content of the provided zip file will get copied to the data partition (hos_data) automatically. Use --f '[value]' multiple times to add more than one zip file.\n \
\tUse this option to automatically copy files (e.g. Atmosphere CFW, homebrew, etc.) to the data partition.\n \
\tIf the path contains spaces, put it in double quotes.\n \
\n \
--emummc\n \
\tIf this option set, The script will create a partition for an EmuMMC.\n \
\tIf you dont set this options, the script will ask you, wether or not to add an EmuMMC partition.\n \
\n \
--device '[value]'\n \
\tValue can be\n \
\t- The path to the device you want to use.\n \
\tIf you dont provide this option, the script will list all available storage devices. You can choose the device you want to use.\n \
\n \
Advanced options:\n \
--no-ui\n \
\tIf this option is set, there will be no user interaction. THERE WILL BE NO WARNING ABOUT DATALOSS. YOU WILL NOT BE ASKED, IF YOU WANT TO CONTINUE, BEFORE THE DEVICE IS FORMATTED.\n \
\tWhen --no-ui is set, you must provide a device using --device.\n \
\n \
--no-startfiles\n \
\tIf this option is set, the script will not copy any files necessary to boot horizon, l4t or android to the data partition (hos_data).\n"

echo -e "SwitchSDSetup Script - use --help for a list of available options.\nMore information here:  github.com/lulle2007200/SwitchSDSetup\n"

while (($# > 0))
	do
	declare Option="$1"
	
	case $Option in
		--help)
			echo -e "$Help"
			exit
		;;
		--f)
			if expr match "$2" "^.*[.]zip$" > 0 && test -f "$2"
				then
				AdditionalStartFiles=("${AdditionalStartFiles[@]}" "$2")
			else
				echo "Invalid path: \"${2}\" Make sure, the path is correct and points to a .zip file. Ignoring argument."
			fi
			shift 
			shift
		;;
		--no-startfiles)
			declare NoStartfiles=1
			shift
		;;
		--no-ui)
			declare NoUi=1
			shift
		;;
		--android)
			if expr match "$2" "^.*android-[1-9][0-9]*gb[.]img$" > 0 && test -f "$2"
				then
				declare AndroidImg=$2
				declare Android=1
			elif test -d "${2}" && test -f "${2}/boot.img" && test -f "${2}/vendor.img" && test -f "${2}/system.img" && (test -f "${2}/tegra210-icosa.dtb" || test -f "${2}/obj/KERNEL_OBJ/arch/arm64/boot/dts/tegra210-icosa.dtb") && (test -f "${2}/recovery.img" || test -f "${2}/twrp.img")
				then
				declare AndroidImg=$2
				declare Android=2
			elif expr match "$2" "^partitions-only$" > 0
				then
				declare Android=3
			else
				echo "Invalid option:\"${2}\" If its a path, make sure that it is correct. Ignoring argument."
			fi
			shift
			shift
		;;
		--l4t)
			if expr match "${2}" ".*switchroot-l4t-ubuntu-[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9][.]img$" > 0 && test -f "${2}"
				then
				declare L4TImg=$2
				declare L4T=1
			elif expr match "${2}" "^partitions-only$" > 0
				then
				declare L4T=2
			else
				echo "Invalid option: \"${2}\" If it is a path, make sure that it is correct. Ignoring argument"
			fi
			shift
			shift
		;;
		--emummc)
			declare Emummc=1
			shift
		;;
		--device)
			if test -b "${2}"
				then
				declare Device=$2
			else
				echo "Device \"${2}\" is not a block device. Ignoring argument."
			fi
			shift
			shift
		;;	
		*)
			echo "Unknown option: \"${1}\" Ignoring argument."
			shift
		;;
	esac
done

if [[ $(id -u) -ne 0 ]] ; then echo "Please run as root" ; exit 1 ; fi

if [[ $NoUi ]] && [[ -z $Device ]]
	then
	echo "Ui disabled, but no device provided. Aborting"
	exit
fi	
	
if [[ -z $Device ]]
	then
	declare -a AvailableDevices
	mapfile -t -s 1 AvailableDevices < <(lsblk -d -p -e 1,7 -o NAME)

	lsblk -d -e 1,7 -p -o NAME,TRAN,SIZE | awk 'NR==1{print("    "$0);}NR>1{print("["NR-2"]"$0);}'

	if ((${#AvailableDevices[@]} < 1))
		then
		echo "No Storage devices found, aborting"
		exit
	fi

	while :
	do
		read -p "Choose device: " Device
		if  expr match "$Device" "^[0-9]*$" > 0 && (($Device >= 0)) && (($Device < ${#AvailableDevices[@]}))
			then
			Device=${AvailableDevices[$Device]}
			break
		fi
		echo "Enter a valid number"
	done
else
	echo "Selected device: $Device"
fi

if expr match "$Device" "^.*[0-9][0-9]*$" > 0
	then
	PartPrefix="p"
fi

Size=$(($(lsblk -b -n -d -o SIZE "$Device")-2*1024*1024))

#add hos data partition
Partitions=(${Partitions[@]} $hos_data_sz_default)
Size=$(($Size-$hos_data_sz_default))
PartitionNames=("${PartitionNames[@]}" "hos_data")
PartitionFriendlyNames=("${PartitionFriendlyNames[@]}" "Data")
MBRPartitions=("${MBRPartitions[@]}" ${#Partitions[@]})
PostPartCmds=("${PostPartCmds[@]}" "mkfs.vfat -F 32 ${Device}${PartPrefix}${#Partitions[@]}" "sgdisk -t ${#Partitions[@]}:0700 $Device")
StartFiles=("${StartFiles[@]}" "./StartFiles/HOSStockStartFiles.zip" "./StartFiles/Hekate.zip")

if (($Size < 0))
	then
	echo "Storage device too small, aborting."
	exit
fi

#add android partitions
if [[ -z $NoUi ]] && [[ -z $Android ]]
	then
	read -p "Create Partitions for Android Pie? ([Y]es/[N]o): " Input
	if expr match "$Input" "^[yY]$">0
		then
		declare Android=3
	fi
fi 

if [[ $Android ]] && (( $Android==3 ))
	then
	echo "Creating Partitions for Android Pie"
	Partitions=("${Partitions[@]}" $vendor_sz_default $app_sz_default $lnx_sz_default $sos_sz_default $dtb_sz_default $mda_sz_default $cac_sz_default $uda_sz_default)
	PartitionNames=("${PartitionNames[@]}" "vendor" "APP" "LNX" "SOS" "DTB" "MDA" "CAC" "UDA")
	PartitionFriendlyNames=("${PartitionFriendlyNames[@]}" "Android vendor" "Android system" "Android kernel" "Android recovery" "Android DTB" "Android meta data" "Android cache" "Android user data")
	Size=$(($Size-$vendor_sz_default-$app_sz_default-$lnx_sz_default-$sos_sz_default-$dtb_sz_default-$mda_sz_default-$cac_sz_default-$uda_sz_default))

	if (( $Size<0 ))
		then
		echo "Storage device too small, aborting"
	fi
elif [[ $Android ]] &&  (( $Android==2 ))
	then
	echo "Found Android Pie image, create partitions for it and copy the image."
	StartFiles=("${StartFiles[@]}" "./StartFiles/AndroidPieStartFiles.zip")
	
	declare android_boot_img=${AndroidImg}/boot.img

	if test -f "${AndroidImg}/tegra210-icosa.dtb" 
		then
		declare android_dtb_img=${AndroidImg}/tegra210-icosa.dtb
	else
		declare android_dtb_img=${AndroidImg}/obj/KERNEL_OBJ/arch/arm64/boot/dts/tegra210-icosa.dtb
	fi

	if test -f "${AndroidImg}/twrp.img"
		then
		declare TWRP=1
		android_recovery_img=${AndroidImg}/twrp.img			
	else
		android_recovery_img=${AndroidImg}/recovery.img
	fi

	echo "Converting Android sparse images to raw images. This may take a while."

	./simg2img "${AndroidImg}"/vendor.img "${AndroidImg}"/vendor.raw.img
	declare android_vendor_img=${AndroidImg}/vendor.raw.img

	./simg2img "${AndroidImg}"/system.img "${AndroidImg}"/system.raw.img
	declare android_system_img=${AndroidImg}/system.raw.img

	declare temp

	temp=$(( ($(stat -c%s "$android_vendor_img")+(1024*1024-1))/(1024*1024)*(1024*1024) ))
	Size=$(($Size-$temp))
	Partitions=("${Partitions[@]}" $temp)
	PostPartCmds=("${PostPartCmds[@]}" "mkfs.ext4 -F ${Device}${PartPrefix}${#Partitions[@]}" "dd bs=512 if=\"$android_vendor_img\" of=${Device}${PartPrefix}${#Partitions[@]} status=progress")
	
	temp=$(( ($(stat -c%s "$android_system_img")+(1024*1024-1))/(1024*1024)*(1024*1024) ))
	Size=$(($Size-$temp))
	Partitions=("${Partitions[@]}" $temp)
	PostPartCmds=("${PostPartCmds[@]}" "mkfs.ext4 -F ${Device}${PartPrefix}${#Partitions[@]}" "dd bs=512 if=\"$android_system_img\" of=$${PartPrefix}{Device}${#Partitions[@]} status=progress")

	temp=$(( ($(stat -c%s "$android_boot_img")+(1024*1024-1))/(1024*1024)*(1024*1024) ))
	Size=$(($Size-$temp))
	Partitions=("${Partitions[@]}" $temp)
	PostPartCmds=("${PostPartCmds[@]}" "mkfs.ext4 -F ${Device}${PartPrefix}${#Partitions[@]}" "dd bs=512 if=\"$android_boot_img\" of=${Device}${PartPrefix}${#Partitions[@]} status=progress")

	temp=$(( ($(stat -c%s "$android_recovery_img")+(1024*1024-1))/(1024*1024)*(1024*1024) ))
	Size=$(($Size-$temp))
	Partitions=("${Partitions[@]}" $temp)
	PostPartCmds=("${PostPartCmds[@]}" "mkfs.ext4 -F ${Device}${PartPrefix}${#Partitions[@]}" "dd bs=512 if=\"$android_recovery_img\" of=${Device}${PartPrefix}${#Partitions[@]} status=progress")

	temp=$(( ($(stat -c%s "$android_dtb_img")+(1024*1024-1))/(1024*1024)*(1024*1024) ))
	Size=$(($Size-$temp))
	Partitions=("${Partitions[@]}" $temp)
	PostPartCmds=("${PostPartCmds[@]}" "mkfs.ext4 -F ${Device}${PartPrefix}${#Partitions[@]}" "dd bs=512 if=\"$android_dtb_img\" of=${Device}${PartPrefix}${#Partitions[@]} status=progress")

	Partitions=("${Partitions[@]}" $mda_sz_default)
	Size=$(($Size-$mda_sz_default))
	PostPartCmds=("${PostPartCmds[@]}" "mkfs.ext4 -F ${Device}${PartPrefix}${#Partitions[@]}")

	Partitions=("${Partitions[@]}" $cac_sz_default)
	Size=$(($Size-$cac_sz_default))
	PostPartCmds=("${PostPartCmds[@]}" "mkfs.ext4 -F ${Device}${PartPrefix}${#Partitions[@]}")

	Partitions=("${Partitions[@]}" $uda_sz_default)
	Size=$(($Size-$uda_sz_default))
	PostPartCmds=("${PostPartCmds[@]}" "mkfs.ext4 -F ${Device}${PartPrefix}${#Partitions[@]}")

	if [[ $TWRP ]] && (( $TWRP==1 ))
		then
		StartFiles=("${StartFiles[@]}" "./StartFiles/TWRPBootScr.zip")
	fi

	PartitionNames=("${PartitionNames[@]}" "vendor" "APP" "LNX" "SOS" "DTB" "MDA" "CAC" "UDA")
	PartitionFriendlyNames=("${PartitionFriendlyNames[@]}" "Android Pie vendor" "Android Pie system" "Android Pie boot" "Android Pie recovery" "Android Pie DTB" "Android Pie MDA" "Android Pie cache" "Android Pie user data")

	if (($Size < 0))
		then
		echo "Storage device too small, aborting."
		exit
	fi		
elif [[ $Android ]] && (( $Android==1 ))
	then
	echo "Found Android Oreo image, creating partitions for it"

	declare -a PartitionSizes
	declare -a StartSectors
	declare -a Names

	declare PartTable=$(sfdisk -d "${AndroidImg}")

	declare PartTableStartLine=$(echo "$PartTable" | awk '{if(!NF){print NR}}')

	mapfile -t Names < <(echo "$PartTable" | awk '{if (NR>$PartTableStartLine && (NF-1)>0){print substr($NF, 7, length($NF)-7);}}')
	mapfile -t PartitionSizes < <(echo "$PartTable" | awk '{if (NR>$PartTableStartLine && (NF-3)>0){print int($ (NF-3));}}')
	mapfile -t StartSectors < <(echo "$PartTable" | awk '{if (NR>$PartTableStartLine && (NF-5)>0){print int($ (NF-5));}}')
	
	for ((i=1;i<(${#Names[@]}-1);i++))
		do
		temp=$(( (${PartitionSizes[$i]}+2047)/2048*2048*512 ))
		Size=$(($Size-$temp))
		Partitions=("${Partitions[@]}" "$temp")
		PartitionNames=("${PartitionNames[@]}" "${Names[$i]}")
		PartitionFriendlyNames=("${PartitionFriendlyNames[@]}" "Android Oreo ${Names[$i]}")
		PostPartCmds=("${PostPartCmds[@]}" "mkfs.ext4 -F ${Device}${PartPrefix}${#Partitions[@]}" "dd bs=512 if=\"$AndroidImg\" of=${Device}${PartPrefix}${#Partitions[@]} status=progress skip=${StartSectors[$i]} count=${PartitionSizes[$i]}")
	done
	Size=$(($Size-$uda_sz_default))
	Partitions=("${Partitions[@]}" "$uda_sz_default")
	PartitionNames=("${PartitionNames[@]}" "${Names[${#Names[@]}-1]}")
	PartitionFriendlyNames=("${PartitionFriendlyNames[@]}" "Android Oreo ${Names[${#Names[@]}-1]}")
	PostPartCmds=("${PostPartCmds[@]}" "mkfs.ext4 -F ${Device}${PartPrefix}${#Partitions[@]}")
	
	temp=$((${StartSectors[0]}*512))
	
	if [[ -z $NoStartfiles ]]
		then
		PostPartCmds=("${PostPartCmds[@]}" "declare LoopDevice=$(losetup -f)" "losetup -o $temp \$LoopDevice \"$AndroidImg\"" "mkdir -p ./LoopDeviceMount ./DataPartitionMount" "mount \$LoopDevice ./LoopDeviceMount" "mount ${Device}${PartPrefix}1 ./DataPartitionMount" "cp -f -R ./LoopDeviceMount/switchroot_android ./DataPartitionMount" "mkdir -p ./DataPartitionMount/bootloader/ini && cp -f ./LoopDeviceMount/bootloader/ini/00-android.ini ./DataPartitionMount/bootloader/ini/00-android.ini" "mkdir -p ./DataPartitionMount/bootloader/res && cp -f \"./LoopDeviceMount/bootloader/res/Switchroot Android.bmp\" \"./DataPartitionMount/bootloader/res/Switchroot Android.bmp\"" "umount ${Device}${PartPrefix}1" "umount \$LoopDevice" "rmdir ./LoopDeviceMount ./DataPartitionMount" "losetup -d \$LoopDevice")
	fi

	if (($Size < 0))
		then
		echo "Storage device too small, aborting."
		exit
	fi
	
fi

#add L4T partition
if [[ -z $NoUi ]] && [[ -z $L4T ]]
	then
	read -p "Create partitions for L4T Ubuntu? ([Y]es/[N]o): " Input
	if expr match "$Input" "^[yY]$" > 0
		then
		L4T=2
	fi
fi

if [[ $L4T ]] && (( $L4T==1 ))
	then
	echo "Found L4T Ubuntu Image. Create partitions for it and copy the image."
	declare -a StartSectors
	declare -a PartitionSizes
	declare temp
	
	declare PartTable=$(sfdisk -d "${L4TImg}")
	
	mapfile -t PartitionSizes < <(echo "$PartTable" | awk '{if (NR>5 && (NF-1)>0){print int($ (NF-1));}}')
	mapfile -t StartSectors < <(echo "$PartTable" | awk '{if (NR>5 && (NF-3)>0){print int($ (NF-3));}}')

	temp=$(((${PartitionSizes[1]}+2047)/2048*2048*512))	
	Size=$(($Size-$temp))

	Partitions=("${Partitions[@]}" $temp)
	PartitionNames=("${PartitionNames[@]}" "l4t")
	PartitionFriendlyNames=("${PartitionFriendlyNames[@]}" "Linux4Tegra")
	MBRPartitions=("${MBRPartitions[@]}" ${#Partitions[@]})

	temp=$((${StartSectors[0]}*512))
	if [[ -z $NoStartfiles ]]
		then
		PostPartCmds=("${PostPartCmds[@]}" "declare LoopDevice=$(losetup -f)" "losetup -o $temp \$LoopDevice \"$L4TImg\"" "mkdir -p ./LoopDeviceMount ./DataPartitionMount" "mount \$LoopDevice ./LoopDeviceMount" "mount ${Device}${PartPrefix}1 ./DataPartitionMount" "cp -R -f ./LoopDeviceMount/. ./DataPartitionMount/" "patch ./DataPartitionMount/l4t-ubuntu/boot.scr ./Patches/bootp${#Partitions[@]}.patch" "umount ${Device}${PartPrefix}1" "umount \$LoopDevice" "rmdir ./LoopDeviceMount ./DataPartitionMount" "losetup -d \$LoopDevice")
	fi

	PostPartCmds=("${PostPartCmds[@]}" "mkfs.ext4 -F ${Device}${PartPrefix}${#Partitions[@]}" "dd bs=512 if=\"$L4TImg\" of=${Device}${PartPrefix}${#Partitions[@]} skip=${StartSectors[1]} count=${PartitionSizes[1]} status=progress")	

	if (($Size<0))
		then
		echo "Storage device too small, aborting."
		exit
	fi

elif [[ $L4T ]] && (( $L4T==2 ))
	then
	echo "Creating partitions for L4T ubuntu"
	Size=$(($Size-$l4t_sz_default))

	if (($Size<0))
		then
		echo "Storage device too small, aborting."
		exit
	fi

	Partitions=("${Partitions[@]}" $l4t_sz_default)
	PartitionNames=("${PartitionNames[@]}" "l4t")
	PartitionFriendlyNames=("${PartitionFriendlyNames[@]}" "Linux4Tegra")		
	MBRPartitions=("${MBRPartitions[@]}" ${#Partitions[@]})
	PostPartCmds=("${PostPartCmds[@]}" "mkfs.ext4 -F ${Device}${PartPrefix}${#Partitions[@]}")
fi

#add emummc partition
if [[ -z $NoUi ]] && [[ -z $Emummc ]]
	then
	read -p "Create EmuMMC parition ([Y]es/[N]o): " Input
	if  expr match "$Input" "^[yY]$">0
		then
		declare Emummc=1
	fi
fi
	

if [[ $Emummc ]] && (( $Emummc==1 ))
	then
	Partitions=("${Partitions[@]}" $emummc_sz_default)
	PartitionNames=("${PartitionNames[@]}" "emummc")
	PartitionFriendlyNames=("${PartitionFriendlyNames[@]}" "EmuMMC")
	MBRPartitions=("${MBRPartitions[@]}" ${#Partitions[@]})
	PostPartCmds=("${PostPartCmds[@]}" "mkfs.vfat -F 32 ${Device}${PartPrefix}${#Partitions[@]}" "sgdisk -t ${#Partitions[@]}:0700 $Device")

	Size=$(($Size-$emummc_sz_default))
	if (($Size < 0))
		then
		echo "Storage device too small, aborting."
		exit
	fi
fi

#Adjust partition sizes

if [[ -z $NoUi ]]
	then
	declare temp
	declare SizeInMb=$(($Size/1024/1024))
	declare PartSizeInMb
	echo "Adjust partition sizes, currently unused space: ${SizeInMb}Mb. All remaining free space will get assigned to the data partition."
	for ((i=1;i<${#Partitions[@]};i++)) 
		do
		SizeInMb=$(($Size/1024/1024))
		PartSizeInMb=$((${Partitions[$i]}/1024/1024))
		while :
			do
			read -p "Extend ${PartitionFriendlyNames[$i]} partition (currently ${PartSizeInMb}Mb) by 0-${SizeInMb}Mb: " temp
			if  expr match "$temp" "^[0-9]*$" > 0 && (($temp >= 0)) && (($temp <= $Size*1024*1024))
				then
				Size=$(($Size-($temp*1024*1024)))
				Partitions[$i]=$((${Partitions[$i]}+($temp*1024*1024)))
				break
			fi
			echo "Enter a valid number."
		done
	done
fi

Partitions[0]=$((${Partitions[0]}+$Size))
Size=0

if [[ -z $NoUi ]]
	then
	declare temp
	read -p "Storage device will be formatted. All data will be lost. Continue? ([Y]es/[N]o): " temp
	if  (($(expr match "$temp" "^[yY]$")==0))
		then
		echo "Aborting."
		exit
	fi
fi

for n in "${Device}*"
	do 
	umount $n
done

parted $Device --script mklabel gpt
for ((i=0; i<${#Partitions[@]}; i++)) 
	do
	sgdisk -n $(($i+1)):0:+$((${Partitions[$i]}/1024))K $Device
	sgdisk -c $(($i+1)):${PartitionNames[$i]} $Device
done

declare Gdisk_cmd="r\nh\n"
for ((i=0;i<${#MBRPartitions[@]};i++))
	do
	Gdisk_cmd="${Gdisk_cmd}${MBRPartitions[$i]} "
done
Gdisk_cmd="${Gdisk_cmd}\nN\n"
for ((i=0;i<${#MBRPartitions[@]};i++))
	do
	Gdisk_cmd="${Gdisk_cmd}0C\nN\n"
done
if ((${#MBRPartitions[@]}<3))
	then
	Gdisk_cmd="${Gdisk_cmd}N\n"
fi
Gdisk_cmd="${Gdisk_cmd}w\nY\n"

printf "${Gdisk_cmd}" | gdisk $Device

partprobe

for ((Cmd=0;Cmd<${#PostPartCmds[@]};Cmd++))
	do
	eval "${PostPartCmds[$Cmd]}"
done

if [[ -z $NoStartfiles ]]
	then
	AdditionalStartFiles=("${StartFiles[@]}" "${AdditionalStartFiles[@]}")
fi
mkdir -p "./DataPartitionMount"
mount "${Device}1" "./DataPartitionMount"
for ((i=0;i<${#AdditionalStartFiles[@]};i++))
	do
	unzip -o "${AdditionalStartFiles[$i]}" -d "./DataPartitionMount"
done
umount "${Device}1"
rmdir "./DataPartitionMount"

echo "Done."
