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
\tIf this option is set, the script will not copy any files necessary to boot horizon, l4t or android to the data partition (hos_data).\n \
--no-format\n \
\tIf this option is set, the script will not format the SD card and instead just flash the provided files. Required partitions must already be present and large enough."

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

				declare android_boot_img="${AndroidImg}/boot.img"
				
				if test -f "${AndroidImg}/tegra210-icosa.dtb" 
					then
					declare android_dtb_img="${AndroidImg}/tegra210-icosa.dtb"
				else
					declare android_dtb_img="${AndroidImg}/obj/KERNEL_OBJ/arch/arm64/boot/dts/tegra210-icosa.dtb"
				fi

				if test -f "${AndroidImg}/twrp.img"
					then
					declare TWRP=1
					android_recovery_img="${AndroidImg}/twrp.img"
				else
					android_recovery_img="${AndroidImg}/recovery.img"
				fi

				echo "Converting Android sparse images to raw images. This may take a while."

				./simg2img "${AndroidImg}"/vendor.img "${AndroidImg}"/vendor.raw.img
				declare android_vendor_img=${AndroidImg}/vendor.raw.img

				./simg2img "${AndroidImg}"/system.img "${AndroidImg}"/system.raw.img
				declare android_system_img=${AndroidImg}/system.raw.img

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
		--no-format)
			declare NoFormat=1
			shift
		;;
		--fix-mbr)
			declare FixMbr=1
			shift
		;;
		*)
			echo "Unknown option: \"${1}\" Ignoring argument."
			shift
		;;
	esac
done

if [[ $NoUi ]] && [[ -z $Device ]]
	then
	echo "Ui disabled, but no device provided. Aborting"
	exit
fi

if [[ $NoFormat ]] && ( ( [[ $Android ]] && (( $Android==3)) )  || ( [[ $L4T ]] && (( $L4T==3)) ) || ( [[ $Emummc ]] && (( $Android==1)) ))
	then
	echo "no-format and l4t=partitions-only / android=partitions-only are incompatible. Aborting"
fi

if [[ $(id -u) -ne 0 ]] ; then echo "Please run as root" ; exit 1 ; fi

	
	
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

if [[ $Android ]] || [[ $L4T ]] || (( ${#AdditionalStartFiles[@]}>0 ))
	then

	declare temp=1	
	
	declare SDPartTable=$(sfdisk -d "${Device}")

	declare SDPartTableStartLine=$(echo "$SDPartTable" | awk '{if(!NF){print NR}}')

	mapfile -t SDPartNames < <(echo "$SDPartTable" | awk '{if (NR>$SDPartTableStartLine && (NF-1)>0){print substr($NF, 7, length($NF)-7);}}')
	mapfile -t SDPartitionSizes < <(echo "$SDPartTable" | awk '{if (NR>$SDPartTableStartLine && (NF-3)>0){print int($ (NF-3));}}')

	if test ${SDPartNames[0]} = "hos_data"
		then
		if (( ${SDPartitionSizes[0]} < ($hos_data_sz_default/512) ))
			then
			temp=0
		fi
	fi
			
	
	if [[ $L4T ]] && (( $L4T==1 ))
		then
		for ((i=0;i<${#SDPartNames[@]};i++))
			do
			if test "l4t" = "${SDPartNames[$i]}"
				then
				declare L4TPartTable=$(sfdisk -d "${L4TImg}")

				declare L4TPartTableStartLine=$(echo "$L4TPartTable" | awk '{if(!NF){print NR}}')
		
				mapfile -t L4TPartitionSizes < <(echo "$L4TPartTable" | awk '{if (NR>$L4TPartTableStartLine && (NF-1)>0){print int($ (NF-1));}}')

				if (( ${SDPartitionSizes[$i]} < $(((${L4TPartitionSizes[1]}+2047)/2048*2048)) ))
					then
					temp=0	
					break
				else
					declare L4T_part=$(($i+1))
					break
				fi
			fi
		done
		if [[ -z $L4T_part ]]
			then
			temp=0
		fi
	fi
	if [[ $Android ]] && (( $Android==1 ))
		then	
		declare AndroidPartTable=$(sfdisk -d "${AndroidImg}")

		declare AndroidPartTableStartLine=$(echo "$AndroidPartTable" | awk '{if(!NF){print NR}}')

		mapfile -t AndroidPartNames < <(echo "$AndroidPartTable" | awk '{if (NR>$PartTableStartLine && (NF-1)>0){print substr($NF, 7, length($NF)-7);}}')
		mapfile -t AndroidPartitionSizes < <(echo "$AndroidPartTable" | awk '{if (NR>$PartTableStartLine && (NF-3)>0){print int($ (NF-3));}}')

		for ((j=1;j<${#AndroidPartNames[@]}-1;j++))
			do
			for ((i=0;i<${#SDPartNames[@]};i++))
				do
				if test ${AndroidPartNames[$j]} = ${SDPartNames[$i]}
					then
					if (( ${SDPartitionSizes[$i]} < $(((${AndroidPartitionSizes[$j]}+2047)/2048*2048)) ))
						then
						temp=0
						break 2
					else
						eval declare ${AndroidPartNames[$j]}_part=$(($i+1))
					fi
					continue 2
				fi
			done
			temp=0
			break
		done
	elif [[ $Android ]] && (( $Android==2 ))
		then
		declare -a AndroidPiePartNames=("vendor" "LNX" "SOS" "DTB" "APP")
		declare -a AndroidPieImages=("$android_vendor_img" "$android_boot_img" "$android_recovery_img" "$android_dtb_img" "$android_system_img")
		
		for ((i=0;i<${#AndroidPiePartNames[@]};i++))
			do
			for ((j=0;j<${#SDPartNames[@]};j++))
				do
				if test ${SDPartNames[$j]} = ${AndroidPiePartNames[$i]}	
					then
					if (( ${SDPartitionSizes[$j]} < (($(stat -c%s "$android_vendor_img")+(1024*1024-1))/(1024*1024)*(1024*1024)/512) ))
						then
						temp=0
						break 2
					else
						eval declare ${AndroidPiePartNames[$i]}_part=$(($j+1))
					fi
					continue 2
				fi
			done
			temp=0
			break
		done
	fi
	if (( $temp==0 )) && [[ $NoFormat ]]
		then
		echo "no-format option set, but the required partitions are not present. Aborting"
		exit
	elif [[ -z $NoUi ]] && (( $temp==1 ))
		then
		read -p "Partitions for the provided files are already present on the SD card. Flash the provided images without formatting the SD card? ([Y]es/[N]o): " Input
		if expr match "$Input" "^[yY]$">0
			then
			declare NoFormat=1
		fi
	fi
		
elif [[ $NoFormat ]]
	then
	echo "no-format option set, but no files to flash provided. Aborting."
	exit
fi

#add hos data partition

Partitions=(${Partitions[@]} $hos_data_sz_default)
Size=$(($Size-$hos_data_sz_default))
PartitionNames=("${PartitionNames[@]}" "hos_data")
PartitionFriendlyNames=("${PartitionFriendlyNames[@]}" "Data")
MBRPartitions=("${MBRPartitions[@]}" ${#Partitions[@]})
if [[ -z $NoFormat ]]
	then
	PostPartCmds=("${PostPartCmds[@]}" "mkfs.vfat -F 32 ${Device}${PartPrefix}${#Partitions[@]}" "sgdisk -t ${#Partitions[@]}:0700 $Device")
fi
StartFiles=("${StartFiles[@]}" "./StartFiles/HOSStockStartFiles.zip" "./StartFiles/Hekate.zip")

if (($Size < 0))
	then
	echo "Storage device too small, aborting."
	exit
fi

#add android partitions
if [[ -z $NoUi ]] && [[ -z $Android ]] && [[ -z $NoFormat ]]
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
	
	if [[ -z $NoStartfiles ]]
		then
		StartFiles=("${StartFiles[@]}" "./StartFiles/AndroidPieStartFiles.zip")
		if [[ $TWRP ]] && (( $TWRP==1 ))
		then
			StartFiles=("${StartFiles[@]}" "./StartFiles/TWRPBootScr.zip")
		fi
	fi

	declare temp
	declare FileSize
	declare PartNo
	
	FileSize=$(stat -c%s "$android_vendor_img")
	temp=$(( ($FileSize+(1024*1024-1))/(1024*1024)*(1024*1024) ))
	Size=$(($Size-$temp))
	Partitions=("${Partitions[@]}" $temp)
	PartNo=${#Partitions[@]}
	if [[ $NoFormat ]]
		then
		PartNo=$vendor_part
	fi
	PostPartCmds=("${PostPartCmds[@]}" "mkfs.ext4 -F ${Device}${PartPrefix}${PartNo}" "dd oflag=sync bs=1M if=\"$android_vendor_img\" of=${Device}${PartPrefix}${PartNo} count=$((${FileSize}/(1024*1024))) status=progress")
	PostPartCmds=("${PostPartCmds[@]}" "dd oflag=sync bs=512 if=/dev/zero of=${Device}${PartPrefix}${PartNo} count=$(((${temp}-(${FileSize}/(1024*1024)*(1024*1024)))/512)) seek=$((${FileSize}/(1024*1024)*(1024*1024)/512)) status=progress")
	PostPartCmds=("${PostPartCmds[@]}" "dd oflag=sync bs=512 if=\"$android_vendor_img\" of=${Device}${PartPrefix}${PartNo} status=progress seek=$((${FileSize}/(1024*1024)*(1024*1024)/512)) skip=$((${FileSize}/(1024*1024)*(1024*1024)/512)) count=$((($FileSize-(${FileSize}/(1024*1024)*(1024*1024)))/512))")
	PostPartCmds=("${PostPartCmds[@]}" "resize2fs ${Device}${PartPrefix}${PartNo}")
	
	FileSize=$(stat -c%s "$android_system_img")
	temp=$(( ($FileSize+(1024*1024-1))/(1024*1024)*(1024*1024) ))
	Size=$(($Size-$temp))
	Partitions=("${Partitions[@]}" $temp)
	PartNo=${#Partitions[@]}
	if [[ $NoFormat ]]
		then
		PartNo=$APP_part
	fi
	PostPartCmds=("${PostPartCmds[@]}" "mkfs.ext4 -F ${Device}${PartPrefix}${PartNo}" "dd oflag=sync bs=1M if=\"$android_system_img\" of=${Device}${PartPrefix}${PartNo} count=$((${FileSize}/(1024*1024))) status=progress")
	PostPartCmds=("${PostPartCmds[@]}" "dd oflag=sync bs=512 if=/dev/zero of=${Device}${PartPrefix}${PartNo} count=$(((${temp}-(${FileSize}/(1024*1024)*(1024*1024)))/512)) seek=$((${FileSize}/(1024*1024)*(1024*1024)/512)) status=progress")
	PostPartCmds=("${PostPartCmds[@]}" "dd oflag=sync bs=512 if=\"$android_system_img\" of=${Device}${PartPrefix}${PartNo} status=progress seek=$((${FileSize}/(1024*1024)*(1024*1024)/512)) skip=$((${FileSize}/(1024*1024)*(1024*1024)/512)) count=$((($FileSize-(${FileSize}/(1024*1024)*(1024*1024)))/512))")
	PostPartCmds=("${PostPartCmds[@]}" "resize2fs ${Device}${PartPrefix}${PartNo}")

	FileSize=$(stat -c%s "$android_boot_img")
	temp=$(( ($FileSize+(1024*1024-1))/(1024*1024)*(1024*1024) ))
	Size=$(($Size-$temp))
	Partitions=("${Partitions[@]}" $temp)
	PartNo=${#Partitions[@]}
	if [[ $NoFormat ]]
		then
		PartNo=$LNX_part

	fi
	PostPartCmds=("${PostPartCmds[@]}" "mkfs.ext4 -F ${Device}${PartPrefix}${PartNo}" "dd oflag=sync bs=1M if=\"$android_boot_img\" of=${Device}${PartPrefix}${PartNo} count=$((${FileSize}/(1024*1024))) status=progress")
	PostPartCmds=("${PostPartCmds[@]}" "dd oflag=sync bs=512 if=/dev/zero of=${Device}${PartPrefix}${PartNo} count=$(((${temp}-(${FileSize}/(1024*1024)*(1024*1024)))/512)) seek=$((${FileSize}/(1024*1024)*(1024*1024)/512)) status=progress")
	PostPartCmds=("${PostPartCmds[@]}" "dd oflag=sync bs=512 if=\"$android_boot_img\" of=${Device}${PartPrefix}${PartNo} status=progress seek=$((${FileSize}/(1024*1024)*(1024*1024)/512)) skip=$((${FileSize}/(1024*1024)*(1024*1024)/512)) count=$((($FileSize-(${FileSize}/(1024*1024)*(1024*1024)))/512))")

	FileSize=$(stat -c%s "$android_recovery_img")
	temp=$(( ($FileSize+(1024*1024-1))/(1024*1024)*(1024*1024) ))
	Size=$(($Size-$temp))
	Partitions=("${Partitions[@]}" $temp)
	PartNo=${#Partitions[@]}
	if [[ $NoFormat ]]
		then
		PartNo=$SOS_part
	fi
	PostPartCmds=("${PostPartCmds[@]}" "mkfs.ext4 -F ${Device}${PartPrefix}${PartNo}" "dd oflag=sync bs=1M if=\"$android_recovery_img\" of=${Device}${PartPrefix}${PartNo} count=$((${FileSize}/(1024*1024))) status=progress")
	PostPartCmds=("${PostPartCmds[@]}" "dd oflag=sync bs=512 if=/dev/zero of=${Device}${PartPrefix}${PartNo} count=$(((${temp}-(${FileSize}/(1024*1024)*(1024*1024)))/512)) seek=$((${FileSize}/(1024*1024)*(1024*1024)/512)) status=progress")
	PostPartCmds=("${PostPartCmds[@]}" "dd oflag=sync bs=512 if=\"$android_recovery_img\" of=${Device}${PartPrefix}${PartNo} status=progress seek=$((${FileSize}/(1024*1024)*(1024*1024)/512)) skip=$((${FileSize}/(1024*1024)*(1024*1024)/512)) count=$((($FileSize-(${FileSize}/(1024*1024)*(1024*1024)))/512))")

	FileSize=$(stat -c%s "$android_dtb_img")
	temp=$(( ($FileSize+(1024*1024-1))/(1024*1024)*(1024*1024) ))
	Size=$(($Size-$temp))
	Partitions=("${Partitions[@]}" $temp)
	PartNo=${#Partitions[@]}
	if [[ $NoFormat ]]
		then
		PartNo=$DTB_part
	fi
	PostPartCmds=("${PostPartCmds[@]}" "mkfs.ext4 -F ${Device}${PartPrefix}${PartNo}" "dd oflag=sync bs=1M if=\"$android_dtb_img\" of=${Device}${PartPrefix}${PartNo} count=$((${FileSize}/(1024*1024))) status=progress")
	PostPartCmds=("${PostPartCmds[@]}" "dd oflag=sync bs=512 if=/dev/zero of=${Device}${PartPrefix}${PartNo} count=$(((${temp}-(${FileSize}/(1024*1024)*(1024*1024)))/512)) seek=$((${FileSize}/(1024*1024)*(1024*1024)/512)) status=progress")
	PostPartCmds=("${PostPartCmds[@]}" "dd oflag=sync bs=512 if=\"$android_dtb_img\" of=${Device}${PartPrefix}${PartNo} status=progress seek=$((${FileSize}/(1024*1024)*(1024*1024)/512)) skip=$((${FileSize}/(1024*1024)*(1024*1024)/512)) count=$((($FileSize-(${FileSize}/(1024*1024)*(1024*1024)))/512))")
	
	if [[ -z $NoFormat ]]
		then
		Partitions=("${Partitions[@]}" $mda_sz_default)
		Size=$(($Size-$mda_sz_default))
		PostPartCmds=("${PostPartCmds[@]}" "mkfs.ext4 -F ${Device}${PartPrefix}${#Partitions[@]}")

		Partitions=("${Partitions[@]}" $cac_sz_default)
		Size=$(($Size-$cac_sz_default))
		PostPartCmds=("${PostPartCmds[@]}" "mkfs.ext4 -F ${Device}${PartPrefix}${#Partitions[@]}")

		Partitions=("${Partitions[@]}" $uda_sz_default)
		Size=$(($Size-$uda_sz_default))
		PostPartCmds=("${PostPartCmds[@]}" "mkfs.ext4 -F ${Device}${PartPrefix}${#Partitions[@]}")
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

	declare PartNo
	
	for ((i=1;i<(${#Names[@]}-1);i++))
		do
		temp=$(( (${PartitionSizes[$i]}+2047)/2048*2048*512 ))
		Size=$(($Size-$temp))
		Partitions=("${Partitions[@]}" "$temp")
		PartitionNames=("${PartitionNames[@]}" "${Names[$i]}")
		PartitionFriendlyNames=("${PartitionFriendlyNames[@]}" "Android Oreo ${Names[$i]}")
		PartNo=${#Partitions[@]}
		if [[ $NoFormat ]]
			then
			eval PartNo=\$${Names[$i]}_part
		fi
		
		PostPartCmds=("${PostPartCmds[@]}" "mkfs.ext4 -F ${Device}${PartPrefix}${PartNo}" "dd oflag=sync bs=1M if=\"$AndroidImg\" of=${Device}${PartPrefix}${PartNo} status=progress iflag=skip_bytes skip=$((${StartSectors[$i]}*512)) count=$((${PartitionSizes[$i]}/2048))")
		PostPartCmds=("${PostPartCmds[@]}" "dd oflag=sync bs=512 if=/dev/zero of=${Device}${PartPrefix}${PartNo} status=progress count=$((${PartitionSizes[$i]}-(${PartitionSizes[$i]}/2048*2048))) seek=$((${PartitionSizes[$i]}/2048*2048))")
		PostPartCmds=("${PostPartCmds[@]}" "dd oflag=sync bs=512 if=\"$AndroidImg\" of=${Device}${PartPrefix}${PartNo} seek=$((${PartitionSizes[$i]}/2048*2048)) status=progress skip=$((${StartSectors[$i]}+(${PartitionSizes[$i]}/2048*2048))) count=$((${PartitionSizes[$i]}-(${PartitionSizes[$i]}/2048*2048)))")
	done
	Size=$(($Size-$uda_sz_default))
	Partitions=("${Partitions[@]}" "$uda_sz_default")
	PartitionNames=("${PartitionNames[@]}" "${Names[${#Names[@]}-1]}")
	PartitionFriendlyNames=("${PartitionFriendlyNames[@]}" "Android Oreo ${Names[${#Names[@]}-1]}")
	if [[ -z $NoFormat ]]
		then
		PostPartCmds=("${PostPartCmds[@]}" "mkfs.ext4 -F ${Device}${PartPrefix}${#Partitions[@]}")
	fi
	
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
if [[ -z $NoUi ]] && [[ -z $L4T ]] && [[ -z $NoFormat ]]
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

	declare PartNo
	
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

	PartNo=${#Partitions[@]}
	if [[ $NoFormat ]]
		then
		PartNo=$L4T_part
	fi

	if [[ -z $NoStartfiles ]]
		then
		PostPartCmds=("${PostPartCmds[@]}" "declare LoopDevice=$(losetup -f)" "losetup -o $temp \$LoopDevice \"$L4TImg\"" "mkdir -p ./LoopDeviceMount ./DataPartitionMount" "mount \$LoopDevice ./LoopDeviceMount" "mount ${Device}${PartPrefix}1 ./DataPartitionMount" "cp -R -f ./LoopDeviceMount/. ./DataPartitionMount/" "umount ${Device}${PartPrefix}1" "umount \$LoopDevice" "rmdir ./LoopDeviceMount ./DataPartitionMount" "losetup -d \$LoopDevice")
		StartFiles=("${StartFiles[@]}" "./StartFiles/bootp${PartNo}.zip")
	fi
	
	PostPartCmds=("${PostPartCmds[@]}" "mkfs.ext4 -F ${Device}${PartPrefix}${PartNo}" "dd oflag=sync bs=1M if=\"$L4TImg\" of=${Device}${PartPrefix}${PartNo} iflag=skip_bytes skip=$((${StartSectors[1]}*512)) count=$((${PartitionSizes[1]}/2048)) status=progress")	
	PostPartCmds=("${PostPartCmds[@]}" "dd oflag=sync bs=512 if=/dev/zero of=${Device}${PartPrefix}${PartNo} count=$((${PartitionSizes[1]}-(${PartitionSizes[1]}/2048*2048))) seek=$((${StartSectors[1]}+(${PartitionSizes[1]}/2048*2048))) status=progress")
	PostPartCmds=("${PostPartCmds[@]}" "dd oflag=sync bs=512 if=\"$L4TImg\" of=${Device}${PartPrefix}${PartNo} skip=$(( (${StartSectors[1]}+(${PartitionSizes[1]}/2048*2048)) )) count=$((${PartitionSizes[1]}-(${PartitionSizes[1]}/2048*2048))) seek=$((${StartSectors[1]}+(${PartitionSizes[1]}/2048*2048))) status=progress")
	PostPartCmds=("${PostPartCmds[@]}" "resize2fs ${Device}${PartPrefix}${PartNo}")

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
if [[ -z $NoUi ]] && [[ -z $Emummc ]] && [[ -z $NoFormat ]]
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

if [[ -z $NoUi ]] && [[ -z $NoFormat ]]
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

if [[ -z $NoUi ]] && [[ -z $NoFormat ]]
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

if [[ -z $NoFormat ]]
	then
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
fi

for ((Cmd=0;Cmd<${#PostPartCmds[@]};Cmd++))
	do
	echo  "${PostPartCmds[$Cmd]}"
done

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
