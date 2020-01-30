#!/bin/bash

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

if [[ $(id -u) -ne 0 ]] ; then echo "Please run as root" ; exit 1 ; fi

declare -a AvailableDevices
declare Device
declare Size

declare -a Partitions
declare -a PartitionNames
declare -a PartitionFriendlyNames
declare -a MBRPartitions

declare -a PostPartCmds

declare L4TImg
declare L4T=0

declare AndroidImg
declare Android=0

declare Emummc=0

declare hos_data_sz_default=$((100*1024*1024))

declare l4t_1_sz_default=$((500*1024*1024))
declare l4t_2_sz_default=$((10*1024*1024*1024))

declare emummc_sz_default=$((29844*1024*1024))

declare vendor_sz_default=$((1*1024*1024*1024))
declare app_sz_default=$((2*1024*1024*1024))
declare lnx_sz_default=$((32*1024*1024))
declare sos_sz_default=$((64*1024*1024))
declare dtb_sz_default=$((1*1024*1024))
declare mda_sz_default=$((16*1024*1024))
declare cac_sz_default=$((700*1024*1024))
declare uda_sz_default=$((1*1024*1024*1024))

#select storage device
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

Size=$(($(lsblk -b -n -d -o SIZE "$Device")-2*1024*1024))


#evaluate arguments
if [ -n "$1" ]
	then
	if expr match "$1" ".*switchroot-l4t-ubuntu-[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9].img$" > 0 && test -f "$1"
		then
		L4TImg=$1
	elif test -d "$1" && test -f "${1}/system.img" && test -f "${1}/vendor.img" && test -f "${1}/boot.img" && (test -f "${1}/obj/KERNEL_OBJ/arch/arm64/boot/dts/tegra210-icosa.dtb" || test -f "${1}/tegra210-icosa.dtb") && (test -f "${1}/recovery.img" || test -f "${1}/twrp.img")
		then
		AndroidImg=$1
	else
		echo "First argument is invalid, ignoring it."
	fi
fi
if [ -n "$2" ]
	then 
	if expr match "$2" ".*switchroot-l4t-ubuntu-[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9].img$" > 0 && test -f "$2"
		then
		L4TImg=$2
		
	elif test -d "$2" && test -f "${2}/system.img" && test -f "${2}/vendor.img" && test -f "${2}/boot.img" && (test -f "${2}/obj/KERNEL_OBJ/arch/arm64/boot/dts/tegra210-icosa.dtb" || test -f "${2}/tegra210-icosa.dtb") 
		then
		AndroidImg=$2
	else
		echo "Second argument is invalid, ignoring it."
	fi
fi

#add hos data partition
Partitions=(${Partitions[@]} $hos_data_sz_default)
Size=$(($Size-$hos_data_sz_default))

PartitionNames=(${PartitionNames[@]} "hos_data")
PartitionFriendlyNames=(${PartitionFriendlyNames[@]} "Data")
MBRPartitions=(${MBRPartitions[@]} ${#Partitions[@]})

PostPartCmds=("${PostPartCmds[@]}" "mkfs.vfat -F 32 ${Device}${#Partitions[@]}" "sgdisk -t ${#Partitions[@]}:0700 $Device")

if (($Size < 0))
	then
	echo "Storage device too small, aborting."
	exit
fi

#add L4T partition
if [[ $L4TImg ]]
	then
	read -p "Found L4T Ubuntu image. Create partitions for L4T Ubuntu and copy the image? ([Y]es/[N]o): " L4T
	if  expr match "$L4T" "^[yY]$">0
		then
		L4T=1

		declare -a StartSectors
		declare -a PartitionSizes
		declare temp
		
		declare PartTable=$(sfdisk -d "${L4TImg}")

		mapfile -t PartitionSizes < <(echo "$PartTable" | awk '{if (NR>5 && (NF-1)>0){print int($ (NF-1));}}')
		mapfile -t StartSectors < <(echo "$PartTable" | awk '{if (NR>5 && (NF-3)>0){print int($ (NF-3));}}')

		
		temp=$(((${PartitionSizes[0]}+2047)/2048*2048*512))
		
		if (($temp>${Partitions[0]}))
			then
			Size=$(($Size-$temp+${Partitions[0]}))
			Partitions[0]=$temp
		fi
		
		temp=$(((${PartitionSizes[1]}+2047)/2048*2048*512))
		
		Size=$(($Size-$temp))
		if (($Size<0))
			then
			echo "Storage device too small, aborting."
			exit
		fi
		
		Partitions=(${Partitions[@]} $temp)
		PartitionNames=(${PartitionNames[@]} "l4t")
		PartitionFriendlyNames=(${PartitionFriendlyNames[@]} "Linux4Tegra")

		MBRPartitions=(${MBRPartitions[@]} ${#Partitions[@]})

		PostPartCmds=("${PostPartCmds[@]}" "mkfs.ext4 -F ${Device}${#Partitions[@]}" "dd bs=512 if=\"$L4TImg\" of=${Device}1 skip=${StartSectors[0]} count=${PartitionSizes[0]} status=progress" "dd bs=512 if=\"$L4TImg\" of=${Device}${L4TPartition} skip=${StartSectors[1]} count=${PartitionSizes[1]} status=progress")		
	else
		L4T=0
	fi
	
else
	echo "No L4T Ubuntu image provided"
	L4T=0
fi

if ((L4T != 1))
	then
	read -p "Create partitions for L4T Ubuntu anyways? ([Y]es/[N]o): " L4T
	if  expr match "$L4T" "^[yY]$">0
		then
		L4T=1

		if (($l4t_1_sz_default>${Partitions[0]}))
			then
			Size=$(($Size-$l4t_1_sz_default+${Partitions[0]}))
			Partitions[0]=$l4t_1_sz_default
		fi
		Size=$(($Size-$l4t_2_sz_default))

		if (($Size<0))
			then
			echo "Storage device too small, aborting."
			exit
		fi
		Partitions=(${Partitions[@]} $l4t_2_sz_default)
		PartitionNames=(${PartitionNames[@]} "l4t")
		PartitionFriendlyNames=(${PartitionFriendlyNames[@]} "Linux4Tegra")
		
		MBRPartitions=(${MBRPartitions[@]} ${#Partitions[@]})

		PostPartCmds=("${PostPartCmds[@]}" "mkfs.ext4 -F ${Device}${#Partitions[@]}")
	fi
fi
	
#add emummc partition	
read -p "Create EmuMMC parition ([Y]es/[N]o): " Emummc
if  expr match "$Emummc" "^[yY]$">0
	then
	Emummc=1

	Partitions=(${Partitions[@]} $emummc_sz_default)
	PartitionNames=(${PartitionNames[@]} "emummc")
	PartitionFriendlyNames=(${PartitionFriendlyNames[@]} "EmuMMC")
	
	MBRPartitions=(${MBRPartitions[@]} ${#Partitions[@]})

	PostPartCmds=("${PostPartCmds[@]}" "mkfs.vfat -F 32 ${Device}${#Partitions[@]}" "sgdisk -t ${#Partitions[@]}:0700 $Device")

	Size=$(($Size-$emummc_sz_default))
	if (($Size < 0))
		then
		echo "Storage device too small, aborting."
		exit
	fi
	
else
	Emummc=0
fi

#add android partitions
if [[ $AndroidImg ]]
	then
	read -p "Found Android image. Create partitions for Android and copy the image? ([Y]es/[N]o): " Android
	if  expr match "$Android" "^[yY]$">0
		then
		Android=1

		declare AndroidPartition=$((${#Partitions[@]}+1))

		echo "Converting Android sparse images to raw images."

		declare android_boot_img=${AndroidImg}/boot.img

		./simg2img "${AndroidImg}"/vendor.img "${AndroidImg}"/vendor.raw.img
		declare android_vendor_img=${AndroidImg}/vendor.raw.img

		./simg2img "${AndroidImg}"/system.img "${AndroidImg}"/system.raw.img
		declare android_system_img=${AndroidImg}/system.raw.img

		declare android_dtb_img
		if test -f "${AndroidImg}/tegra210-icosa.dtb" 
			then
			android_dtb_img=${AndroidImg}/tegra210-icosa.dtb
		else
			android_dtb_img=${AndroidImg}/obj/KERNEL_OBJ/arch/arm64/boot/dts/tegra210-icosa.dtb
		fi

		declare android_recovery_img
		if test -f "${AndroidImg}/twrp.img"
			then
			android_recovery_img=${AndroidImg}/twrp.img			
		else
			android_recovery_img=${AndroidImg}/recovery.img
		fi
		
		declare temp

		temp=$(( ($(stat -c%s "$android_vendor_img")+(1024*1024-1))/(1024*1024)*(1024*1024) ))
		Size=$(($Size-$temp))
		Partitions=(${Partitions[@]} $temp)
		PostPartCmds=("${PostPartCmds[@]}" "mkfs.ext4 -F ${Device}${#Partitions[@]}" "dd bs=512 if=\"$android_vendor_img\" of=${Device}${#Partitions[@]} status=progress")
		echo "${PostPartCmds[$((${#PostPartCmds[@]}-1))]}"
		
		temp=$(( ($(stat -c%s "$android_system_img")+(1024*1024-1))/(1024*1024)*(1024*1024) ))
		Size=$(($Size-$temp))
		Partitions=(${Partitions[@]} $temp)
		PostPartCmds=("${PostPartCmds[@]}" "mkfs.ext4 -F ${Device}${#Partitions[@]}" "dd bs=512 if=\"$android_system_img\" of=${Device}${#Partitions[@]} status=progress")

		temp=$(( ($(stat -c%s "$android_boot_img")+(1024*1024-1))/(1024*1024)*(1024*1024) ))
		Size=$(($Size-$temp))
		Partitions=(${Partitions[@]} $temp)
		PostPartCmds=("${PostPartCmds[@]}" "mkfs.ext4 -F ${Device}${#Partitions[@]}" "dd bs=512 if=\"$android_boot_img\" of=${Device}${#Partitions[@]} status=progress")

		temp=$(( ($(stat -c%s "$android_recovery_img")+(1024*1024-1))/(1024*1024)*(1024*1024) ))
		Size=$(($Size-$temp))
		Partitions=(${Partitions[@]} $temp)
		PostPartCmds=("${PostPartCmds[@]}" "mkfs.ext4 -F ${Device}${#Partitions[@]}" "dd bs=512 if=\"$android_recovery_img\" of=${Device}${#Partitions[@]} status=progress")

		temp=$(( ($(stat -c%s "$android_dtb_img")+(1024*1024-1))/(1024*1024)*(1024*1024) ))
		Size=$(($Size-$temp))
		Partitions=(${Partitions[@]} $temp)
		PostPartCmds=("${PostPartCmds[@]}" "mkfs.ext4 -F ${Device}${#Partitions[@]}" "dd bs=512 if=\"$android_dtb_img\" of=${Device}${#Partitions[@]} status=progress")

		Partitions=(${Partitions[@]} $mda_sz_default)
		Size=$(($Size-$mda_sz_default))
		PostPartCmds=("${PostPartCmds[@]}" "mkfs.ext4 -F ${Device}${#Partitions[@]}")

		Partitions=(${Partitions[@]} $cac_sz_default)
		Size=$(($Size-$cac_sz_default))
		PostPartCmds=("${PostPartCmds[@]}" "mkfs.ext4 -F ${Device}${#Partitions[@]}")

		Partitions=(${Partitions[@]} $uda_sz_default)
		Size=$(($Size-$uda_sz_default))
		PostPartCmds=("${PostPartCmds[@]}" "mkfs.ext4 -F ${Device}${#Partitions[@]}")

		PartitionNames=(${PartitionNames[@]} "vendor" "APP" "LNX" "SOS" "DTB" "MDA" "CAC" "UDA")
		PartitionFriendlyNames=(${PartitionFriendlyNames[@]} "Android vendor" "Android system" "Android boot" "Android recovery" "Android DTB" "Android MDA" "Android cache" "Android user data")

		if (($Size < 0))
			then
			echo "Storage device too small, aborting."
			exit
		fi		
	else
		Android=0
	fi
else
	echo "No Android image provided."
	Android=0
fi

if ((Android != 1))
	then
	read -p "Create partitions for Android anyways? ([Y]es/[N]o): " Android
	if  expr match "$Android" "^[yY]$">0
		then
		Android=1

		Partitions=(${Partitions[@]} $vendor_sz_default)
		Size=$(($Size-$vendor_sz_default))
		PostPartCmds=("${PostPartCmds[@]}" "mkfs.ext4 -F ${Device}${#Partitions[@]}")

		Partitions=(${Partitions[@]} $app_sz_default)
		Size=$(($Size-$app_sz_default))
		PostPartCmds=("${PostPartCmds[@]}" "mkfs.ext4 -F ${Device}${#Partitions[@]}")

		Partitions=(${Partitions[@]} $lnx_sz_default)
		Size=$(($Size-$lnx_sz_default))
		PostPartCmds=("${PostPartCmds[@]}" "mkfs.ext4 -F ${Device}${#Partitions[@]}")

		Partitions=(${Partitions[@]} $sos_sz_default)
		Size=$(($Size-$sos_sz_default))
		PostPartCmds=("${PostPartCmds[@]}" "mkfs.ext4 -F ${Device}${#Partitions[@]}")	

		Partitions=(${Partitions[@]} $dtb_sz_default)
		Size=$(($Size-$dtb_sz_default))
		PostPartCmds=("${PostPartCmds[@]}" "mkfs.ext4 -F ${Device}${#Partitions[@]}")

		Partitions=(${Partitions[@]} $mda_sz_default)
		Size=$(($Size-$mda_sz_default))
		PostPartCmds=("${PostPartCmds[@]}" "mkfs.ext4 -F ${Device}${#Partitions[@]}")

		Partitions=(${Partitions[@]} $cac_sz_default)
		Size=$(($Size-$cac_sz_default))
		PostPartCmds=("${PostPartCmds[@]}" "mkfs.ext4 -F ${Device}${#Partitions[@]}")

		Partitions=(${Partitions[@]} $uda_sz_default)
		Size=$(($Size-$uda_sz_default))
		PostPartCmds=("${PostPartCmds[@]}" "mkfs.ext4 -F ${Device}${#Partitions[@]}")

		PartitionNames=(${PartitionNames[@]} "vendor" "APP" "LNX" "SOS" "DTB" "MDA" "CAC" "UDA")
		PartitionFriendlyNames=(${PartitionFriendlyNames[@]} "Android vendor" "Android system" "Android boot" "Android recovery" "Android DTB" "Android MDA" "Android cache" "Android user data")
		
		if (($Size < 0))
			then
			echo "Storage device too small, aborting."
			exit
		fi
	fi
fi

#Adjust partition sizes
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

Partitions[0]=$((${Partitions[0]}+$Size))
Size=0


declare temp
read -p "Storage device will be formatted. All data will be lost. Continue? ([Y]es/[N]o): " temp
if  (($(expr match "$temp" "^[yY]$")==0))
	then
	echo "Aborting."
	exit
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

echo "Done."



















