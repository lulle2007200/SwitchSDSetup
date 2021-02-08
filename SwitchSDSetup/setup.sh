#!/bin/bash
WorkingDir="$(pwd)"
ScriptDir="$(dirname $0)"
if [ "$EUID" -ne 0 ]; then
	echo "Please run the script as root"
	exit 1
fi

echo -e "SwitchSDSetup v.2 - https://github.com/lulle2007200/SDSetup\n"

function FunctionMissingArgument {
	echo "Error: Missing argument"
	return 0
}

function FunctionPrintMenu {
	if [ $# -eq 0 ]; then
		echo "Error: Empty menu"
		return 1
	fi
	local _Menu=("$@")
	for i in $(seq ${#_Menu[@]}); do
		echo "[${i}] ${_Menu[$((${i}-1))]}"
	done
	return 0
}

function FunctionMenu {
	if [ $# -lt 2 ]; then
		echo "Error: Empty menu"
		retval=""
		return 1
	fi
	local _Title="$1"
	shift
	local _Menu=("$@")
	echo -e "${_Title}"
	FunctionPrintMenu "${_Menu[@]}"
	local _Input
	while true; do
		read -p "Select option: " _Input
		if [[ "${_Input}" =~ ^[0-9]+$ ]] && [ ${_Input} -gt 0 ] && [ ${_Input} -le ${#_Menu[@]} ]; then
			retval="${_Menu[$((${_Input}-1))]}"
			break
		else
			echo "Invalid input"
		fi
	done
	echo
	return 0
}

function FunctionCleanup {
	rm -rf "${ScriptDir}/tmp" > /dev/null 2&>1
}

function FunctionIsConfigured {
	if [ "$1" ]; then
		if [ "${IsConfigured[$1]}" ] && [ "${IsConfigured[$1]}" == "1" ]; then
			return 0
		else
			return 1
		fi
	fi
	FunctionMissingArgument
	return 0
}

function FunctionYesNoMenu {
	local _Menu=("Yes" "No")
	local _Title=""
	if [ "$1" ]; then
		_Title="$1"
	fi
	FunctionMenu "$_Title" "${_Menu[@]}"
	if [ "$retval" == "Yes" ]; then
		return 0
	else
		return 1
	fi
}

function FunctionSetConfigured {
	if [ "$1" ]; then
		IsConfigured[$1]=1
		return 0
	fi
	FunctionMissingArgument
	return 1
}

function FunctionSetNotConfigured {
	if [ "$1" ]; then
		IsConfigured[$1]=0
		return 0
	fi
	FunctionMissingArgument
	return 1
}

function FunctionIsConfiguredMenu {
	if [ "$1" ]; then
		if FunctionIsConfigured "$1"; then
			if FunctionYesNoMenu "$1 Already Configured. Do you want to reconfigure $1?"; then
				FunctionSetNotConfigured "$1"
				return 0
			else
				return 1
			fi
		else
			return 0
		fi
	fi
	FunctionMissingArgument
	return 1
}

function FunctionExit {
	FunctionCleanup
	exit 0
}

#-------------------

function FunctionSelectDevice {
	while true; do
		local _AvailableDevices
		mapfile -t _AvailableDevices < <(lsblk -d -e 1,7 -p -o NAME,TRAN,SIZE | grep usb)
		local _Menu=("${_AvailableDevices[@]}" "SD card in switch" "Reload device list" "Exit")
		FunctionMenu "Select Device" "${_Menu[@]}"
		local _SelectedDevice="$retval"
		local _FoundSwitch=0
		case "$_SelectedDevice" in
			"SD card in switch")
				if lsusb -d 0955:7321 > /dev/null 2>&1; then
					_FoundSwitch=1
					echo "Found switch in RCM mode"
				else
					local _Timeout=30 
					echo "Please insert a SD card into your switch, put it in RCM mode and connect it via USB ..."
					while [ $_Timeout -gt 0 ]; do
						if lsusb -d 0955:7321 > /dev/null 2>&1; then
							_FoundSwitch=1
							echo "Found switch in RCM mode"
							break
						fi
						_Timeout=$(($_Timeout-1))
						sleep 1
					done
				fi
			 	if [ $_FoundSwitch -eq 1 ]; then
			 		local _CurrentDevices
			 		mapfile -t _CurrentDevices < <(lsblk -d -e 1,7 -p -o NAME,TRAN | grep usb)
			 		python2 "${ScriptDir}/Tools/shofel2/shofel2.py" "${ScriptDir}/Tools/shofel2/cbfs.bin" "${ScriptDir}/Tools/shofel2/SDLoader.rom" > /dev/null 2>&1			 		
			 		local _Timeout=20
			 		while [ $_Timeout -gt 0 ]; do
			 			local _NewDevices
			 			mapfile -t _NewDevices < <(lsblk -d -e 1,7 -p -o NAME,TRAN | grep usb)
			 			for i in ${_NewDevices[@]}; do
			 				for j in ${_CurrentDevices[@]}; do
			 					if [ "$i" == "$j" ]; then
			 						continue 2
			 					fi
			 				done
			 				retval=($i)
			 				retval="${retval[0]}"
			 				break 3 
			 			done
			 			_Timeout=$(($_Timeout-1))
			 			sleep 1
			 		done
			 		echo "No SD card inserted"
			 	else 
			 		echo -e "Didn't find a switch in RCM mode\n"
			 	fi
			;;
			"Reload device list")
				continue
			;;
			"Exit")
				FunctionExit
			;;
			*)
				retval=($_SelectedDevice)
				retval="${retval[0]}"
				break
			;;
		esac
	done
	Device="$retval"
	if [[ "$Device" =~ ^.*[0-9]+$ ]]; then
		PartPrefix="p"
	else
		PartPrefix=""
	fi
	return 0
}

function FunctionBackup {
	if [ "$1" ]; then
		local _BackupName="${1//\//-}.bak.img"
		if [ "$2" ]; then
			_BackupName="$2"
		fi
		mkdir -p "${ScriptDir}/backup" > /dev/null
		local _AvailSpace
		mapfile -t _AvailSpace < <(df --output=avail "${ScriptDir}/backup")
		_AvailSpace=${_AvailSpace[1]}
		local _DevSize
		if ! _DevSize=$(lsblk -b -n -d -o SIZE "$1") > /dev/null 2>&1; then
			echo "Failed to create backup\n"
			return 1
		fi
		if [ $((_DevSize/1024)) -ge $_AvailSpace ]; then
			echo -e "Failed to create backup, not enough space\n"
			return 1
		fi
		echo "Creating backup ..."
		if ! dd if=$1 of=${ScriptDir}/backup/${_BackupName} bs=1M > /dev/null 2>&1; then
			rm "${ScriptDir}/backup/${_BackupName}" > /dev/null 2>&1
			echo "Failed to create backup\n"
			return 1
		else
			echo
			return 0
		fi
	fi
	return 1
}

function FunctionFindFile {
	local _Regex=".*"
	if [ "$1" ]; then
		_Regex="$1"
	fi
	local _SearchDir="${WorkingDir}"
	if [ "$2" ]; then
		_SearchDir="$2"
	fi
	while true; do
		local _Files
		mapfile -t _Files < <(find "$_SearchDir" -maxdepth 1 -type f -exec basename {} \;| grep -E "$_Regex")
		local _Menu=("${_Files[@]}" "Search in different directory" "Back")
		FunctionMenu "Select File" "${_Menu[@]}"
		case "$retval" in
			"Search in different directory")
				if FunctionEnterDirectory; then
					_SearchDir="$retval"
				fi
				local _Input
				continue
			;;
			"Back")
				retval=""
				return 1
			;;
			*)
				retval="${_SearchDir}/$retval"
				return 0
			;;
		esac
	done
}

function FunctionRestoreFromBackup {
	if [ "$1" ]; then
		if ! FunctionFindFile "^[^ ]*.img$" "${ScriptDir}/backup"; then
			echo "No file selected\n"
			return 1
		else
			local _FileSize
			if ! _FileSize=$(stat -c%s "$retval") > /dev/null 2>&1; then
				echo "Failed to restore from backup\n"
				return 1
			fi
			local _DevSize
			if ! _DevSize=$(lsblk -b -n -d -o SIZE "$1") > /dev/null 2>&1; then
				echo "Failed to restore from backup\n"
				return 1
			fi
			if [ $_FileSize -gt $_DevSize ]; then
				echo "Failed to restore from backup. Selected Image is too big\n"
				return 1
			fi
			echo "Restoring backup ..."
			if ! dd if=$retval of=$1 bs=1M > /dev/null 2>&1; then
				echo "Failed to restore from backup\n"
				return 1
			else
				echo
				return 0
			fi
		fi
	fi
	return 1
}

function FunctionSetDevice {
	while true; do
		IsConfigured=()
		FunctionSelectDevice
		local _Device="$retval"
		local _Device=($(lsblk -d -e 1,7 -p -o NAME,VENDOR,MODEL | grep "$_Device"))
		local _Vendor="${_Device[1]}"
		local _Model="${_Device[2]}"
		local _Title
		local _Menu
		_Device="${_Device[0]}"
		if [ "$_Vendor" == "hekate" ]; then
			local _BackupName="${_Model}.bak.img"
			case "$_Model" in
				"SD_RAW")
					_Title="Selected device is $_Device"
					_Menu=("Backup" "Continue" "Restore from backup" "Back" "Exit")
				;;
				"eMMC_GPP")
					FunctionSetConfigured "eMMC"
					_Title="Selected Device is Switch eMMC.\nMake sure that you have a full Backup of it.\nInstalling stuff on eMMC will wipe it."
					local _Menu=("Backup" "Continue" "Restore from backup" "Back" "Exit")
				;;
				*)
					_Title="Selected device is Switch $_Model.\nSelect \"SD card\" or \"eMMC RAW GPP\" in Hekate USB Tools, other options are not supported."
					_Menu=("Backup" "Continue" "Restore from backup" "Back" "Exit")
				;;
			esac
		else
			_Title="Selected Device is $_Device"
			_Menu=("Backup" "Continue" "Restore from backup" "Back" "Exit")
		fi
		Size=$((($(lsblk -b -n -d -o SIZE "$_Device")/1024/1024-1)/8-1))
		while true; do
			FunctionMenu "$_Title" "${_Menu[@]}"
			case "$retval" in
				"Exit")
					FunctionExit
				;;
				"Back")
					continue 2
				;;
				"Continue")
					if [ "$(cat /sys/block/${_Device##*/}/ro)" == "1" ]; then
						echo -e "Selected device is read-only\n"
						continue 2
					fi
					retval="$_Device"
					break 2
				;;
				"Backup")
					if [ "$_BackupName" ]; then
						FunctionBackup "$_Device" "$_BackupName"
					else
						FunctionBackup "$_Device"
					fi
					continue
				;;
				"Restore from backup")
					if [ "$(cat /sys/block/${_Device##*/}/ro)" == "1" ]; then
						echo -e "Selected device is read-only\n"
						continue 2
					fi
					FunctionRestoreFromBackup "$_Device"
					continue
				;;
			esac
		done
	done
}

function FunctionIsInArray {
	if [ $# -lt 2 ]; then
		return 1
	fi
	local _Item="$1"
	shift
	local _Array=("$@")
	for i in $(seq ${#_Array[@]}); do
		if [ "${_Array[$(($i-1))]}" == "$_Item" ]; then
			retval=$i
			return 0
		fi
	done
	return 1
}


function FunctionSearchForExisting {
	local _OreoPartitions=("boot" "dtb" "recovery" "system" "userdata" "vendor")
	local _QPartitions=("LNX" "UDA" "MDA" "DTB" "APP" "vendor" "SOS" "CAC")
	local _QAltPartitions=("LNX_ALT" "MDA_ALT" "DTB_ALT" "APP_ALT" "vendor_ALT" "UDA_ALT" "SOS_ALT" "CAC_ALT" )
	
	local _Partitions
	local _PartitionNames
	if ! mapfile -t _Partitions < <(sfdisk -l -o Start,Sectors,Name "$1" | grep -E '^[ \t]*[0-9]+[ \t]+[0-9]+[ \t]+[a-zA-Z_]+[0-9]*$'); then
		return 1
	fi
	if ! mapfile -t _PartitionNames < <(sfdisk -l -o Name "$1" | grep -E '^[^ ]+$' | grep -v Name); then
		return 1
	fi
	if ! FunctionIsInArray "hos_data" "${_PartitionNames[@]}"; then
		return 1
	fi
	local _CurrentPart
	ExistingPartSize=()
	for i in "${_Partitions[@]}"; do
		_CurrentPart=($i)
		ExistingPartSize[${_CurrentPart[2]}]=$((${_CurrentPart[1]}/2/1024/8));
	done
	local _Menu=()
	local _PartitionsFor=()
	ExistingParts=("${_PartitionNames[@]}")
	while true; do
		for i in ${_OreoPartitions[@]}; do
			if ! FunctionIsInArray "$i" "${_PartitionNames[@]}"; then
				break 2
			fi
		done
		_Menu=("${_Menu[@]}" "Install Android Oreo")
		_PartitionsFor=("${_PartitionsFor[@]}" "Android Oreo")
		break
	done
	while true; do
		for i in ${_QPartitions[@]}; do
			if ! FunctionIsInArray "$i" "${_PartitionNames[@]}"; then
				break 2
			fi
		done
		_Menu=("${_Menu[@]}" "Install Android Q")
		_PartitionsFor=("${_PartitionsFor[@]}" "Android Q")
		break
	done
	while true; do
		for i in ${_QAltPartitions[@]}; do
			if ! FunctionIsInArray "$i" "${_PartitionNames[@]}"; then
				break 2
			fi
		done
		_Menu=("${_Menu[@]}" "Install second Android Q")
		_PartitionsFor=("${_PartitionsFor[@]}" "Secondary Android Q")
		break
	done
	if FunctionIsInArray "l4t" "${_PartitionNames[@]}"; then
		_Menu=("${_Menu[@]}" "Install L4T Ubuntu")
		_PartitionsFor=("${_PartitionsFor[@]}" "L4T  Ubuntu")
	fi
	local _NumberEmummc=0
	if FunctionIsInArray "emummc1" "${_PartitionNames[@]}"; then
		_Menu=("${_Menu[@]}" "Configure EmuMMC 1")
		_NumberEmummc=$(($_NumberEmummc+1))
	fi
	if FunctionIsInArray "emummc2" "${_PartitionNames[@]}"; then
		_Menu=("${_Menu[@]}" "Configure EmuMMC 2")
		_NumberEmummc=$(($_NumberEmummc+1))
	fi
	if [ $_NumberEmummc -gt 0 ]; then
		_PartitionsFor=("${_PartitionsFor[@]}" "$_NumberEmummc EmuMMC(s)")
	fi
	local _Title="Found partitions for ${_PartitionsFor[0]}"
	for i in $(seq 1  $((${#_PartitionsFor[@]}-2))); do
		_Title="${_Title}, ${_PartitionsFor[$i]}"
	done
	if [ ${#_PartitionsFor[@]} -gt 1 ]; then
		_Title="${_Title} and ${_PartitionsFor[-1]}."
	else
		_Title="${_Title}."
	fi
	_Title="${_Title}\ncontinue without formatting and use the existing partitions?"
	if FunctionYesNoMenu "${_Title}"; then
		retval=("${_Menu[@]}")
		retval1=("Fix MBR")
		return 0
	fi
	return 1
}
#TODO: set proper read permissions for backup files
function FunctionWriteHybridMBR {
	local _Device="$1"
	shift
	local _NumberMBRPParts=$1
	shift
	if [ $_NumberMBRPParts -lt 1 ] || [ $_NumberMBRPParts -gt 4 ]; then
		echo -e "Failed to write MBR\n"
		return 1
	fi
	local _MBRParts=("$@")
	local _GdiskCommand="r\nh\n"
	local _Temp=""
	for i in $(seq 0 $(($_NumberMBRPParts-1))); do
		_GdiskCommand="${_GdiskCommand}${_MBRParts[$i]} "
		_Temp="${_Temp}${_MBRParts[$(($i+$_NumberMBRPParts))]}\nN\n"
	done
	_GdiskCommand="${_GdiskCommand}\nN\n${_Temp}"
	if [ $_NumberMBRPParts -lt 3 ]; then
		_GdiskCommand="${_GdiskCommand}N\n"
	fi
	_GdiskCommand="${_GdiskCommand}w\nY\n"
	if ! printf "$_GdiskCommand" | gdisk "$_Device" > /dev/null 2>&1; then
		echo -e "Failed to write MBR\n"
		return 1
	fi
	return 0
}

function FunctionFixMBR {
	local _PartitionNames
	if ! _PartitionNames=$(sfdisk -l -o Name "$1" | grep -E '^[^ ]+$' | grep -v Name); then
		echo -e "Failed to write MBR\n"
		return 1
	fi
	mapfile -t _PartitionNames < <(echo "$_PartitionNames")
	local _MBRParts=()
	local _MBRCodes=()
	if FunctionIsInArray "hos_data" "${_PartitionNames[@]}"; then
		_MBRCodes=("${_MBRCodes[@]}" "0C")
		_MBRParts=("${_MBRParts[@]}" "$retval")
	fi
	for i in "emummc1" "emummc2"; do
		if FunctionIsInArray "$i" "${_PartitionNames[@]}"; then
			_MBRCodes=("${_MBRCodes[@]}" "1C")
			_MBRParts=("${_MBRParts[@]}" "$retval")
		fi
	done
	if ! FunctionWriteHybridMBR "$1" "${#_MBRParts[@]}" "${_MBRParts[@]}" "${_MBRCodes[@]}"; then
		return 1
	fi
	return 0
}

function FunctionEnterDirectory {
	local _Input
	read -p "Enter path: " _Input
	if [ -d "$_Input" ]; then
		retval="$_Input"
		echo
		return 0
	else
		echo -e "Path is invalid or directory doesn't exist\n"
		return 1
	fi
}

function FunctionDownload {
	mkdir -p "${ScriptDir}/tmp/download" > /dev/null 2>&1
	if ! wget -q "$1" -O "${ScriptDir}/tmp/download/$(basename "$1")"; then
		rm "${ScriptDir}/tmp/download/$(basename "$1")" > /dev/null 2>&1
		return 1
	fi
	retval="${ScriptDir}/tmp/download/$(basename "$1")"
	return 0
}

function FunctionAdjustParts {
	if [ $# -eq 0 ]; then
		return 0
	fi
	local _Parts=("$@")
	if ! [ $UsedSize -lt $Size ]; then
		return 0
	fi
	if ! FunctionYesNoMenu "Adjust partition sizes?"; then
		return 0
	fi
	while true; do
		FunctionMenu "Select partition to adjust" "${_Parts[@]}" "Done"
		if [ "$retval" == "Done" ]; then
			break
		fi
		local _Input
		while true; do
			read -p "Current size of $retval partition is $((${PartSizes[$retval]}*8))MB. Extend by (0-$((($Size-$UsedSize)*8)))MB: " _Input
			if [[ "$_Input" =~ ^[0-9]+$ ]] && [ "$_Input" -ge 0 ] && [ "$_Input" -le $((($Size-$UsedSize)*8)) ]; then
				break
			else 
				echo "Enter a valid number"
			fi
		done
		PartSizes[$retval]=$((${PartSizes[$retval]}+($_Input+7)/8))
		UsedSize=$(($UsedSize+($_Input+7)/8))
		if [ $UsedSize -ge $Size ]; then
			break
		fi
	done
	return 0
}

function FunctionDownloadOreo {
	local _OreoUrl="https://download.switchroot.org/android/android-16gb.img.gz"
	echo "Downloading image ..."
	if ! FunctionDownload "$_OreoUrl"; then 
		echo -e "Failed to download Android image\n"
		return 1
	else
		return 0
	fi
}

function FunctionInstallOreo {
	AndroidPartitions=()
	local _OreoImage
	if ! [ "$1" ]; then
		_SearchDir="${WorkingDir}"
		while true; do
			local _OreoImages
			mapfile -t _OreoImages < <(ls "$_SearchDir" | grep -E '^android-[0-9]+gb.img($|[.]gz$)')
			local _Menu=("${_OreoImages[@]}" "Download and use latest Android Oreo image" "Enter path to another directory" "Back")
			FunctionMenu "Select an Android image to install"
			case "$retval" in
				"Back")
					return 1
				;;
				"Enter path to another directory")
					if FunctionEnterDirectory; then
						_SearchDir="$retval"
					fi
				;;
				"Download and use latest Android Oreo image")
					if FunctionDownloadOreo; then
						_OreoImage="$retval"
						break
					fi
				;;
				*)
					_OreoImage="$retval"
					break
				;;
			esac
		done
	else
		_OreoImage="$1"
	fi
	if [[ "$_OreoImage" =~ ^.*[.]gz$ ]]; then
		echo "Extracting image ..."
		mkdir -p "${ScriptDir}/tmp/extract" > /dev/null 2>&1
		rm "${ScriptDir}/tmp/extract/oreo.img" 2> /dev/null
		if ! gzip -c -d "$_OreoImage" > "${ScriptDir}/tmp/extract/oreo.img"; then
			echo -e "Failed to read image\n"
			return 1
		fi
		echo
		_OreoImage="${ScriptDir}/tmp/extract/oreo.img"
	fi
	local _LoopDevice="$(losetup -f)"
	if ! losetup "$_LoopDevice" "$_OreoImage" > /dev/null 2>&1; then
		echo -e "Failed to read image\n"
		return 1
	fi
	local _OreoPartTable
	mapfile -t _OreoPartTable < <(sfdisk -l -o Start,Sectors,Name "$_LoopDevice" | grep -E '^[ \t]*[0-9]+[ \t]+[0-9]+[ \t]+[a-zA-Z_]+$' | grep -v hos_data | grep -v userdata)
	if [ ${#_OreoPartTable[@]} -eq 0 ]; then
		echo -e "Failed to read image\n"
	fi
	AndroidPartitions=()
	local _CurrentPart
	local _PartSize
	local _OreoSize=0
	for i in "${_OreoPartTable[@]}"; do
		_CurrentPart=($i)
		AndroidPartitions=("${AndroidPartitions[@]}" "${_CurrentPart[2]}")
		_PartSize=$(((${_CurrentPart[1]}+16383)/16384))
		PartSizes[${_CurrentPart[2]}]=$_PartSize
		if FunctionIsConfigured "NoFormat"; then
			if [ $_PartSize -gt ${ExistingPartSize[${_CurrentPart[2]}]} ]; then
				echo -e "Selected image is too big for existing partitions\n"
				AndroidPartitions=()
				return 1
			fi
		fi
		Files[${_CurrentPart[2]}]="$_OreoImage"
		_OreoSize=$(($_OreoSize+$_PartSize))
		DDExtraArgs[${_CurrentPart[2]}]="iflag=count_bytes,skip_bytes count=$((${_CurrentPart[1]}*512)) skip=$((${_CurrentPart[0]}*512))"
	done
	PartNeedsResize[vendor]=1
	PartNeedsResize[system]=1
	AndroidPartitions=("${AndroidPartitions[@]}" "userdata")
	if ! FunctionIsConfigured "NoFormat"; then
		PartSizes[userdata]=$(((1024+7)/8))
		_OreoSize=$(($_OreoSize+${PartSizes[userdata]}))
		UsedSize=$(($UsedSize+$_OreoSize))
		PartFormats[userdata]="ext4"
		if [ $(($_OreoSize+$UsedSize)) -gt $Size ]; then
			echo -e "Not enough space to create required partitions\n"
			AndroidPartitions=()
			return 1
		fi
		FunctionAdjustParts "${AndroidPartitions[@]}"
	fi
	BootFiles[system]="${ScriptDir}/Files/OreoBootFiles.zip"
	return 0
}

function FunctionInstallQImages {
	local _SOS="SOS"
	local _APP="APP"
	local _vendor="vendor"
	local _DTB="DTB"
	local _LNX="LNX"
	local _UDA="UDA"
	local _MDA="MDA"
	local _CAC="CAC"
	if [ "$1" ]; then
		local _SOS="SOS_ALT"
		local _APP="APP_ALT"
		local _vendor="vendor_ALT"
		local _DTB="DTB_ALT"
		local _LNX="LNX_ALT"
		local _UDA="UDA_ALT"
		local _MDA="MDA_ALT"
		local _CAC="CAC_ALT"
	fi
	local _AndroidQParts=()
	Files[$_SOS]="${ScriptDir}/Files/twrp.img"
	PartSizes[$_SOS]=$((($(stat -c%s "${Files[$_SOS]}")+(1024*1024*8)-1)/(1024*1024*8)))
	PartSizes[$_APP]=$((($(stat -c%s "${Files[$_APP]}")+(1024*1024*8)-1)/(1024*1024*8)))
	PartSizes[$_vendor]=$((($(stat -c%s "${Files[$_vendor]}")+(1024*1024*8)-1)/(1024*1024*8)))
	PartSizes[$_DTB]=$((($(stat -c%s "${Files[$_DTB]}")+(1024*1024*8)-1)/(1024*1024*8)))
	PartSizes[$_LNX]=$((($(stat -c%s "${Files[$_LNX]}")+(1024*1024*8)-1)/(1024*1024*8)))
	PartSizes[$_UDA]=$(((1024+7)/8))
	PartSizes[$_MDA]=$(((16+7)/8))
	PartSizes[$_CAC]=$(((700+7)/8))
	_AndroidQParts=("$_UDA" "$_APP" "$_MDA" "$_DTB" "$_vendor" "$_SOS" "$_CAC" "$_LNX")
	local _QSize
	for i in ${_AndroidQParts[@]}; do
		if [ ${PartSizes[$i]} -le 0 ]; then
			echo -e "Selected image is not valid\n"
			_AndroidQParts=()
			if [ "$1" ]; then
				QAltPartitions=()
			else
				AndroidPartitions=()
			fi
			return 1
		fi
		if FunctionIsConfigured "NoFormat"; then
			if [ ${PartSizes[$i]} -gt ${ExistingPartSize[$i]} ]; then
				echo "Existing partitions are too small for this image\n"
				_AndroidQParts=()
				if [ "$1" ]; then
					QAltPartitions=()
				else
					AndroidPartitions=()
				fi
				return 1
			fi
		fi
		_QSize=$(($_QSize+${PartSizes[$i]}))
	done
	if [ $(($_QSize+$UsedSize)) -gt $Size ]; then
		echo -e "Not enough space to create partitions"
		_AndroidQParts=()
		if [ "$1" ]; then
			QAltPartitions=()
		else
			AndroidPartitions=()
		fi
		return 1
	fi
	UsedSize=$(($UsedSize+$_QSize))
	PartNeedsResize[$_APP]="1"
	PartNeedsResize[$_vendor]="1"
	if ! FunctionIsConfigured "NoFormat"; then
		PartFormats[$_UDA]="ext4"
	fi
	PartFormats[$_CAC]="ext4"
	Files[$_MDA]="/dev/zero"
	DDExtraArgs[$_MDA]="iflag=count_bytes count=$((${PartSizes[$_MDA]}*8*1024*1024))"

	if [ "$1" ]; then
		QAltPartitions=("${_AndroidQParts[@]}")
	else
		AndroidPartitions=("${_AndroidQParts[@]}")
	fi
	if FunctionIsConfigured "eMMC"; then
		if [ "$1" ]; then
			BootFiles[$_APP]="${ScriptDir}/Files/QAltBootFilesEMMC.zip"
		else
			BootFiles[$_APP]="${ScriptDir}/Files/QBootFilesEMMC.zip"
		fi
	else
		if [ "$1" ]; then
			BootFiles[$_APP]="${ScriptDir}/Files/QAltBootFiles.zip;"
		else
			BootFiles[$_APP]="${ScriptDir}/Files/QBootFiles.zip;"
		fi
	fi
	FunctionAdjustParts "${_AndroidQParts[@]}"
	FunctionSetConfigured "AndroidQ"
	return 0
}

function FunctionInstallQZip {
	if ! [ "$1" ]; then
		return 1
	fi
	local _vendor="vendor"
	local _APP="APP"
	local _LNX="LNX"
	if [ "$2" ]; then
		local _vendor="vendor_ALT"
		local _APP="APP_ALT"
		local _LNX="LNX_ALT"
	fi
	local _QZip="$1"
	echo "Extracting selected image ..."
	mkdir -p "${ScriptDir}/tmp/extract" > /dev/null 2>&1
	if ! unzip -o -d "${ScriptDir}/tmp/extract/Q" "$_QZip" "vendor.transfer.list" "system.transfer.list" "system.new.dat.br" "vendor.new.dat.br" "boot.img" > /dev/null 2>&1; then
		echo -e "Failed to unzip selected image\n"
		return 1
	fi
        if ! "${ScriptDir}/Tools/brotli" -f -j --decompress "${ScriptDir}/tmp/extract/Q/vendor.new.dat.br" "${ScriptDir}/tmp/extract/Q/system.new.dat.br"; then
                echo -e "Failed to decompress selected image\n"
                return 1
        fi
        if ! "${ScriptDir}/Tools/dat2img.sh" --transfer-list "${ScriptDir}/tmp/extract/Q/system.transfer.list" --data-file "${ScriptDir}/tmp/extract/Q/system.new.dat"; then
                echo -e "Failed to read selected image\n"
                return 1
        fi
        if ! "${ScriptDir}/Tools/dat2img.sh" --transfer-list "${ScriptDir}/tmp/extract/Q/vendor.transfer.list" --data-file "${ScriptDir}/tmp/extract/Q/vendor.new.dat"; then
                echo -e "Failed to read selected image\n"
                return 1
        fi
	Files[$_vendor]="${ScriptDir}/tmp/extract/Q/vendor.new.dat.img"
	Files[$_APP]="${ScriptDir}/tmp/extract/Q/system.new.dat.img"
	Files[$_LNX]="${ScriptDir}/tmp/extract/Q/boot.img"
	return 0
}

function FunctionInstallAndroidQ {
	local _APP="APP"
	local _vendor="vendor"
	local _LNX="LNX"
	local _DTB="DTB"
	if ! [ "$1" ]; then
		if FunctionIsConfigured "AndroidQ"; then
			if FunctionIsConfiguredMenu "AndroidQ"; then
				for i in ${AndroidPartitions[@]}; do
					UsedSize=$(($UsedSize-$((${PartSizes[$i]}))))
				done
			else
				return 1
			fi
		fi
	else
		local _APP="APP_ALT"
		local _vendor="vendor_ALT"
		local _LNX="LNX_ALT"
		local _DTB="DTB_ALT"
		if FunctionIsConfigured "AndroidAltQ"; then
			if FunctionIsConfiguredMenu "AndroidAltQ"; then
				for i in ${QAltPartitions[@]}; do
					UsedSize=$(($UsedSize-$((${PartSizes[$i]}))))
				done
			else
				return 1
			fi
		fi
	fi
	local _SearchDir="${WorkingDir}"
	while true; do
		local _QZipImages
		mapfile -t _QZipImages < <(ls "$_SearchDir" | grep -E '^lineage-17.1-[0-9]{8}-UNOFFICIAL-(foster|foster_tab|icosa)[.]zip$')
		local _QImages
		if	[ -f "${_SearchDir}/system.img" ] && [ -f "${_SearchDir}/vendor.img" ] && [ -f "${_SearchDir}/boot.img" ]; then
			_QImages=("Android Q")

			Files[$_APP]="${_SearchDir}/system.img"
			Files[$_vendor]="${_SearchDir}/vendor.img"
			Files[$_LNX]="${_SearchDir}/boot.img"
		fi
		if [ -f "${_SearchDir}/tegra210-icosa.dtb" ]; then
			Files[$_DTB]="${_SearchDir}/tegra210-icosa.dtb"
		elif [ -f "${_SearchDir}/obj/KERNEL_OBJ/arch/arm64/boot/dts/tegra210-icosa.dtb" ]; then
			Files[$_DTB]="${_SearchDir}/obj/KERNEL_OBJ/arch/arm64/boot/dts/tegra210-icosa.dtb"
		else
			if [ $QImages ] || [ $QZipImages ]; then
				MissingDTB=1
			fi
			_QImages=()
			_QZipImages=()
		fi
		local _AndroidMenu=("${_QZipImages[@]}" "${_QImages[@]}" "Enter path to another directory" "Back")
		FunctionMenu "Select an Android image to install" "${_AndroidMenu[@]}"
		local _SelectedOption="$retval"
		case "$_SelectedOption" in
			"Enter path to another directory")
				if FunctionEnterDirectory; then
					_SearchDir="$retval"
				fi
				continue
			;;
			"Back")
				return 1
			;;
			*)
				break
			;;
		esac
	done
	if FunctionIsInArray "$_SelectedOption" "${_QZipImages[@]}"; then
		if FunctionInstallQZip "${_SearchDir}/${_SelectedOption}" "$1"; then
			FunctionInstallQImages "$1"
		fi
	fi
	if FunctionIsInArray "$_SelectedOption" "${_QImages[@]}"; then
		echo "Extracting images ..."
		mkdir -p "${ScriptDir}/tmp" > /dev/null
		if ! "${ScriptDir}/Tools/simg2img" "${Files[$_APP]}" "${ScriptDir}/tmp/system.raw.img"; then
			echo -e "Failed to extract image\n"
			return 1
		fi
		Files[$_APP]="${ScriptDir}/tmp/system.raw.img"
		if ! "${ScriptDir}/Tools/simg2img" "${Files[$_vendor]}" "${ScriptDir}/tmp/vendor.raw.img"; then
			echo -e "Failed to extract image\n"
			return 1
		fi
		Files[$_vendor]="${ScriptDir}/tmp/vendor.raw.img"
		FunctionInstallQImages "$1"
	fi
	local _ret=$?
	if [ $_ret -eq 0 ]; then
		if [ "$1" ]; then
			FunctionSetConfigured "AndroidAltQ"
		else
			FunctionSetConfigured "AndroidQ"
		fi
	fi
	return 0
}

function FunctionInstallAndroid {
	if FunctionIsConfigured "Android"; then
		if FunctionIsConfiguredMenu "Android"; then
			for i in ${AndroidPartitions[@]}; do
				UsedSize=$(($UsedSize-$((${PartSizes[$i]}))))
			done
		else
			return 1
		fi
	fi
	local _SearchDir="${WorkingDir}"

	while true; do
		local _OreoImages
		mapfile -t _OreoImages < <(ls "$_SearchDir" | grep -E '^android-[0-9]+gb.img($|[.]gz$)')
		local _QZipImages
		mapfile -t _QZipImages < <(ls "$_SearchDir" | grep -E '^lineage-17.1-[0-9]{8}-UNOFFICIAL-(foster|foster_tab|icosa)[.]zip$')
		local _QImages
		if	[ -f "${_SearchDir}/system.img" ] && [ -f "${_SearchDir}/vendor.img" ] && [ -f "${_SearchDir}/boot.img" ]; then
			_QImages=("Android Q")
			Files[APP]="${_SearchDir}/system.img"
			Files[vendor]="${_SearchDir}/vendor.img"
			Files[LNX]="${_SearchDir}/boot.img"
		fi
		if [ -f "${_SearchDir}/tegra210-icosa.dtb" ]; then
			Files[DTB]="${_SearchDir}/tegra210-icosa.dtb"
		elif [ -f "${_SearchDir}/obj/KERNEL_OBJ/arch/arm64/boot/dts/tegra210-icosa.dtb" ]; then
			Files[DTB]="${_SearchDir}/obj/KERNEL_OBJ/arch/arm64/boot/dts/tegra210-icosa.dtb"
		else
			if [ $QImages ] || [ $QZipImages ]; then
				MissingDTB=1
			fi
			_QImages=()
			_QZipImages=()
		fi
		local _AndroidMenu=("${_OreoImages[@]}" "${_QZipImages[@]}" "${_QImages[@]}" "Download and use latest Android image" "Enter path to another directory" "Back")
		FunctionMenu "Select an Android image to install" "${_AndroidMenu[@]}"
		local _SelectedOption="$retval"
		case "$_SelectedOption" in
			"Download and use latest Android image")
				if FunctionDownloadOreo; then
					_SelectedOption="$(basename "$retval")"
					_OreoImages=("${_OreoImages[@]}" "$_SelectedOption")
					_SearchDir="$(dirname "$retval")"
					break
				else
					echo -e "Failed to download image\n"
					continue
				fi
			;;
			"Enter path to another directory")
				if FunctionEnterDirectory; then
					_SearchDir="$retval"
				fi
				continue
			;;
			"Back")
				return 1
			;;
			*)
				break
			;;
		esac
	done

	if FunctionIsInArray "$_SelectedOption" "${_OreoImages[@]}"; then
		FunctionInstallOreo "${_SearchDir}/${_SelectedOption}"
	fi
	if FunctionIsInArray "$_SelectedOption" "${_QZipImages[@]}"; then
		if FunctionInstallQZip "${_SearchDir}/${_SelectedOption}"; then
			FunctionInstallQImages
		fi
	fi
	if FunctionIsInArray "$_SelectedOption" "${_QImages[@]}"; then
		echo "Extracting images ..."
		mkdir -p "${ScriptDir}/tmp" > /dev/null
		if ! "${ScriptDir}/Tools/simg2img" "${Files[APP]}" "${ScriptDir}/tmp/system.raw.img"; then
			echo -e "Failed to extract image\n"
			return 1
		fi
		Files[APP]="${ScriptDir}/tmp/system.raw.img"
		if ! "${ScriptDir}/Tools/simg2img" "${Files[vendor]}" "${ScriptDir}/tmp/vendor.raw.img"; then
			echo -e "Failed to extract image\n"
			return 1
		fi
		Files[vendor]="${ScriptDir}/tmp/vendor.raw.img"
		echo
		FunctionInstallQImages
	fi
	local _ret=$?
	if [ $_ret -eq 0 ]; then
		FunctionSetConfigured "Android"
	fi
	return $_ret
}

function FunctionAddHosPart {
	local _HosMinSize=$(((500+7)/8))
	if [ $(($Size-$UsedSize)) -lt $_HosMinSize ]; then
		echo -e "Storage device too small\n"
		return 1
	fi
	PartSizes[hos_data]=$_HosMinSize
	UsedSize=$(($UsedSize+$_HosMinSize))
	HosPartitions=("${HosPartitions[@]}" "hos_data")
	MBRPartitions[hos_data]=1
	MBRPartCodes[hos_data]="0C"
	PartFormats[hos_data]="vfat"
	BootFiles[hos_data]="${ScriptDir}/Files/Atmosphere.zip;${ScriptDir}/Files/Stock.zip"
	return 0
}

function FunctionAddDataPart {
	local _HosMinSize=$(((500+7)/8))
	if [ $(($Size-$UsedSize)) -lt $_HosMinSize ]; then
		echo -e "Storage device too small\n"
		return 1
	fi
	PartSizes[hos_data]=$_HosMinSize
	UsedSize=$(($UsedSize+$_HosMinSize))
	HosPartitions=("${HosPartitions[@]}" "hos_data")
	MBRPartitions[hos_data]=1
	MBRPartCodes[hos_data]="0C"
	PartFormats[hos_data]="vfat"
	return 0
}

function FunctionSaveChanges {
	local _Title="This will wipe the storage device. All data on it will be lost. Continue?"
	if FunctionIsConfigured "NoFormat"; then
		_Title="This will format wipe all partitions that need to be changed. Continue?"
	fi
	if ! FunctionYesNoMenu "$_Title"; then
		return 1;
	fi
	if ! [ "$1" ]; then
		echo -e "Failed to write to storage device\n"
		return 1
	fi
	local _Device="$1"
	if ! FunctionIsConfigured "NoFormat" && ! FunctionIsConfigured "eMMC"; then
		PartSizes[hos_data]=$(($Size-$UsedSize+${PartSizes[hos_data]}))
	fi
	UsedSize=$Size
	echo "Unmounting storage device ..."
	for i in "${_Device}*"; do
		umount $i > /dev/null 2>&1
	done
	local _Partitions=("${ExistingParts[@]}")
	if ! FunctionIsConfigured "NoFormat"; then
		_Partitions=("${HosPartitions[@]}" "${AndroidPartitions[@]}" "${QAltPartitions[@]}" "${L4TPartitions[@]}" "${EmummcPartitions[@]}")
		echo "Formatting storage device ..."
	parted "$_Device" --script mklabel gpt
		local _PartBegin="8M"
		local _MBRParts=()
		local _MBRCodes=()
		for i in $(seq ${#_Partitions[@]}); do
			local _CurrentPart=$i
			if ! sgdisk -n ${_CurrentPart}:${_PartBegin}:+$((${PartSizes[${_Partitions[$(($i-1))]}]}*8))M $_Device > /dev/null 2>&1; then
				echo -e "Failed to write to storage device\n"
				return 1
			fi
			if ! sgdisk -c ${_CurrentPart}:${_Partitions[$(($i-1))]} "$_Device" > /dev/null 2>&1; then
				echo -e "Failed to write to storage device\n"
				return 1
			fi
			if [ "${MBRPartitions[${_Partitions[$(($i-1))]}]}" == "1" ]; then
				_MBRParts=("${_MBRParts[@]}" "$i")
				_MBRCodes=("${_MBRCodes[@]}" "${MBRPartCodes[${_Partitions[$(($i-1))]}]}")
			fi
			_PartBegin="0"
		done
		if [ ${#_MBRParts[@]} -gt 0 ]; then
			if ! FunctionWriteHybridMBR "$_Device" "${#_MBRParts[@]}" "${_MBRParts[@]}" "${_MBRCodes[@]}"; then
				return 1
			fi
		fi
		local _UUID=$(uuidgen)
		_UUID="${_UUID:0:14}00${_UUID:16:38}"
		if ! sgdisk -u 1:${_UUID} $_Device > /dev/null 2>&1; then
			echo -e "Failed to set UUID\n"
			return 1
		fi
		partprobe "$_Device"  > /dev/null 2>&1
		while [ ! -e "${_Device}${PartPrefix}1" ]; do
			sleep 1
		done
		sleep 10
	fi
	echo "Formatting partitions ..."
	for i in $(seq 0 $((${#_Partitions[@]}-1))); do
		if [ "${PartFormats[${_Partitions[$i]}]}" ]; then
			if ! mkfs -t ${PartFormats[${_Partitions[$i]}]} ${_Device}${PartPrefix}$(($i+1)) > /dev/null 2>&1; then
				echo -e "Failed to write to storage device\n"
				return 1
			fi
		fi
	done
	echo "Writing images ..."
	for i in $(seq 0 $((${#_Partitions[@]}-1))); do
		if [ "${Files[${_Partitions[$i]}]}" ]; then
			if ! dd if="${Files[${_Partitions[$i]}]}" of="${_Device}${PartPrefix}$(($i+1))" oflag=sync bs=8M ${DDExtraArgs[${_Partitions[$i]}]} > /dev/null 2>&1; then
				echo -e "Failed to write image to storage device\n"
				return 1
			fi
		fi
	done
	echo "Resizing file systems ..."
	for i in $(seq 0 $((${#_Partitions[@]}-1))); do
		if [ "${PartNeedsResize[${_Partitions[$i]}]}" ]; then
			if ! resize2fs ${_Device}${PartPrefix}$(($i+1)) > /dev/null 2>&1; then
				echo -e "Failed to resize file system\n"
				return 1
			fi
		fi
	done
	echo "Copying files ..."
	for i in $(seq 0 $((${#_Partitions[@]}-1))); do
		if [ "${PartFiles[${_Partitions[$i]}]}" ]; then
			mkdir -p "${ScriptDir}/tmp/mountdir" > /dev/null
			local _PartMount
			_PartMount="${ScriptDir}/tmp/mountdir"
			if ! mount "${_Device}${PartPrefix}$(($i+1))" "${ScriptDir}/tmp/mountdir"; then
				echo "Failed to mount storage device"
				return 1
			fi
			local _ZipFiles
			IFS=';' read -r -a _ZipFiles <<< "${PartFiles[${_Partitions[$i]}]}"
			for j in "${_ZipFiles[@]}"; do
				if ! unzip -o -d "$_PartMount" "$j" > /dev/null 2>&1; then
					echo -e "Failed to copy files\n"
					return 1
				fi
			done
			umount "$_PartMount"
		fi
	done
	local _SDFiles
	if FunctionIsConfigured "eMMC"; then
		mkdir -p "${WorkingDir}/SDFiles" > /dev/null
		_SDFiles="${WorkingDir}/SDFiles"
	else
		mkdir -p "${ScriptDir}/tmp/mountdir" > /dev/null
		_SDFiles="${ScriptDir}/tmp/mountdir"
		if ! mount "${_Device}${PartPrefix}1" "${ScriptDir}/tmp/mountdir" > /dev/null 2>&1; then
			echo "Failed to mount storage device"
			return 1
		fi
	fi
	for i in $(seq 0 $((${#_Partitions[@]}-1))); do
		if [ "${BootFiles[${_Partitions[$i]}]}" ]; then
			local _ZipFiles
			IFS=';' read -r -a _ZipFiles <<< "${BootFiles[${_Partitions[$i]}]}"
			for j in "${_ZipFiles[@]}"; do
				if ! unzip -o -d "$_SDFiles" "$j" > /dev/null 2>&1; then
					echo -e "Failed to copy files\n"
					return 1
				fi
			done
		fi
	done
	if ! unzip -o -d "$_SDFiles" "${ScriptDir}/Files/Hekate.zip"; then
		echo -e "Failed to copy files\n"
		return 1
	fi
	echo "Done"
	if FunctionIsConfigured "eMMC"; then
		chmod -R 755 "$_SDFiles"
		chown -R "$_SDFiles" $SUDO_UID:
		echo -e "Copy all files from SDFiles to the root of your SD card\n"
	else
		umount "${ScriptDir}/tmp/mountdir" > /dev/null 2>&1
		echo
	fi
	return 0
}

function FunctionInstallL4T {
	if FunctionIsConfigured "L4T"; then
		if FunctionIsConfiguredMenu "L4T"; then
			for i in ${L4TPartitions[@]}; do
				UsedSize=$(($UsedSize-$((${PartSizes[$i]}))))
			done
		else
			return 1
		fi
	fi
	L4TPartitions=()
	local _SearchDir=${WorkingDir}
	while true; do
		local _L4TImages
		mapfile -t _L4TImages <  <(ls "$_SearchDir" | grep -E '^switchroot-ubuntu-[0-9]+[.][0-9]+[.][0-9]+-[0-9]{4}-[0-9]{2}-[0-9]{2}[.]7z$')
		local _Menu=("${_L4TImages[@]}" "Download latest L4T Ubuntu image" "Enter path to another directory" "Back")
		FunctionMenu "Select a L4T image" "${_Menu[@]}"
		local _L4TImage="$retval"
		case "$_L4TImage" in 
			"Back")
				return 1
			;;
			"Enter path to another directory")
				if FunctionEnterDirectory; then
					_SearchDir="$retval"
				fi
			;;
			"Download latest L4T Ubuntu image")
				echo "Download latest L4T ubuntu image ..."
				local _L4TUrl="https://download.switchroot.org/ubuntu/switchroot-ubuntu-3.2.0-2020-10-05.7z"
				if FunctionDownload "$_L4TUrl"; then
					_L4TImage="$retval"
					break
				else
					echo -e "Failed to download L4T Ubuntu image\n"
				fi
			;;
			*)
				break
			;;
		esac
	done
	echo "Extracting L4T Ubuntu image ..."
	local _L4TImageParts
	mkdir -p "${ScriptDir}/tmp/extract/l4timage" > /dev/null
	mapfile -t _L4TImageParts < <(7z l "$_L4TImage" | grep -o -E 'switchroot/install/l4t[.][0-9]+$')
	if [ ${#_L4TImageParts[@]} -eq 0 ]; then
		echo -e "L4T Ubuntu image is not valid\n"
		return 1
	fi
	if ! 7z -o${ScriptDir}/tmp/extract/l4tbootfiles -aoa x '-xr!l4t.*' "$_L4TImage" > /dev/null 2>&1; then
		echo -e "Failed to extract L4T image\n"
		return 1
	fi
	if ! 7z -o${ScriptDir}/tmp/extract/l4timage -aoa e "$_L4TImage" "${_L4TImageParts[0]}" > /dev/null 2>&1; then
		echo -e "Failed to extract L4T image\n"
		return 1
	fi
	_L4TImage1="${ScriptDir}/tmp/extract/l4timage/$(basename ${_L4TImageParts[0]})"
	for i in $(seq 1 $((${#_L4TImageParts[@]}-1))); do
		if ! 7z e -so "$_L4TImage" "${_L4TImageParts[$i]}" >> "$_L4TImage1" 2>/dev/null; then
			echo -e "Failed to extract L4T Ubuntu image\n"
			return 1
		fi
	done
	chmod -R 755 "${ScriptDir}/tmp"
	cd "${ScriptDir}/tmp/extract/l4tbootfiles"
	if FunctionIsConfigured "eMMC"; then
		sed -i 's/^overlays=/&tegra210-icosa_emmc-overlay/' "switchroot/ubuntu/uenv.txt"
	fi
	if ! zip ${ScriptDir}/tmp/L4TBootFiles.zip -r ./* > /dev/null 2>&1; then
		cd -
		echo -e "Failed to extract L4T Ubuntu image\n"
		return 1
	fi
	cd -
	local _L4TSize=$((($(stat -c%s "$_L4TImage1")+(1024*1024*8)-1)/(1024*1024*8)))
	if ! FunctionIsConfigured "NoFormat"; then
		if [ $(($_L4TSize+$UsedSize)) -gt $Size ]; then
			echo -e "Not enough space to create partitions\n"
			return 1
		fi
	else
		if [ $_L4TSize -gt ${ExistingPartSize[l4t]} ]; then
			echo -e "Existing partitions are too small for this image\n"
			return 1
		fi
	fi
	UsedSize=$(($UsedSize+$_L4TSize))
	PartSizes[l4t]=$_L4TSize
	Files[l4t]="$_L4TImage1"
	PartNeedsResize[l4t]=1
	BootFiles[l4t]="${ScriptDir}/tmp/L4TBootFiles.zip"
	L4TPartitions=("${L4TPartitions[@]}" "l4t")
	FunctionAdjustParts "l4t"
	FunctionSetConfigured "L4T"
}

function FunctionAddEmuMMC {
	if ! [ "$1" ]; then
		return 1
	fi
	if [ "$1" == "1" ]; then
		if FunctionIsConfigured "EmuMMC"; then
			if FunctionIsConfiguredMenu "EmuMMC"; then
				for i in ${EmummcPartitions[@]}; do
					UsedSize=$(($UsedSize-$((${PartSizes[$i]}))))
				done
				EmummcPartitions=()
			else
				return 1
			fi
		fi
	else
		if [ $1 -gt 2 ]; then
			echo -e "Already configured two EmuMMC partitions, can't add more\n"
			return 1
		fi
	fi
	local _EmuMMCPart="emummc${1}"
	local _EmuMMCSize=$(((29844+7)/8))
	if [ $(($_EmuMMCSize+$UsedSize)) -gt $Size ]; then
		echo -e "Not enough space to create EmuMMC partition\n"
		return 1
	fi
	EmummcPartitions=("${EmummcPartitions[@]}" "$_EmuMMCPart")
	PartSizes[$_EmuMMCPart]=$_EmuMMCSize
	UsedSize=$(($_EmuMMCSize+$UsedSize))
	MBRPartitions[$_EmuMMCPart]=1
	MBRPartCodes[$_EmuMMCPart]="1C"
	while true; do
		if FunctionYesNoMenu "Do you want to select an eMMC image to flash to the EmuMMC partition?"; then
			while true; do
				if FunctionFindFile "^.*.img$"; then
					local _ImgSize=$((($(stat -c%s "$retval")+(1024*1024*8)-1)/(1024*1024*8)))
					if [ $_ImgSize -gt $_EmuMMCSize ]; then
						echo "Selected image is too big\n"
						continue
					fi
					Files[$_EmuMMCPart]="$retval"
				else
					continue 2
				fi
			done
		else
			break
		fi
	done
	BootFiles[$_EmuMMCPart]="${ScriptDir}/Files/EmuMMC.zip;${ScriptDir}/Files/Atmosphere.zip"
	FunctionSetConfigured "EmuMMC"
}

function FunctionConfigEmummc {
	if ! [ "$1 " ]; then
		return 1
	fi
	local _EmuMMCPart="emummc${1}"
	if FunctionIsConfigured "EmuMMC ${1}"; then
		if FunctionIsConfiguredMenu "EmuMMC ${1}"; then
			Files[$_EmuMMCPart]=""
		else
			return 1
		fi
	fi
	while true; do
		if FunctionYesNoMenu "Do you want to select an eMMC image to flash to the EmuMMC partition?"; then
			while true; do
				if FunctionFindFile "^.*.img$"; then
					local _ImgSize=$((($(stat -c%s "$retval")+(1024*1024*8)-1)/(1024*1024*8)))
					if [ $_ImgSize -gt ${ExistingPartSize[$_EmuMMCPart]} ]; then
						echo "Selected image is too big\n"
						continue
					fi
					Files[$_EmuMMCPart]="$retval"
					break 2
				else
					continue 2
				fi
			done
		else
			break
		fi
	done
	BootFiles[$_EmuMMCPart]="${ScriptDir}/Files/EmuMMC.zip"
	FunctionSetConfigured "EmuMMC ${1}"
}

function FunctionInstallOreoEx {
	if FunctionIsConfigured "AndroidOreo"; then
		if FunctionIsConfiguredMenu "AndroidOreo"; then
			for i in ${AndroidPartitions[@]}; do
				UsedSize=$(($UsedSize-$((${PartSizes[$i]}))))
			done
		else
			return 1
		fi
	fi
	if FunctionInstallOreo; then
		FunctionSetConfigured "AndroidOreo"
	fi
}

function FunctionMain {
	while true; do
		declare Device=""
		declare PartPrefix=""
		declare UsedSize=0
		declare Size=0
		declare -A IsConfigured=()
		declare -A PartNeedsResize=()
		declare -A PartFormats=()
		declare -A Files=()
		declare -A ExistingPartSize=()
		declare -A DDExtraArgs=()
		declare -A PartSizes=()
		declare -A MBRPartitions=()
		declare -A MBRPartCodes=()
		declare -A BootFiles=()
		declare -A PartFiles=()
		declare HosPartitions=()
		declare AndroidPartitions=()
		declare QAltPartitions=()
		declare EmummcPartitions=()
		declare L4TPartitions=()
		declare ExistingParts=()

		FunctionSetDevice
		local _Device="$retval"
		local _Menu=()
		local _AdvancedMenu=()
		if FunctionSearchForExisting "$_Device"; then
			FunctionSetConfigured "NoFormat"
			_Menu=("${retval[@]}" "Save changes")
			_AdvancedMenu=("${retval1[@]}")
		else
			if ! FunctionIsConfigured "eMMC"; then
				_Menu=("Install Android" "Install L4T Ubuntu" "Add EmuMMC partition" "Save changes")
				_AdvancedMenu=("Add another EmuMMC partition" "Install second Android Q")
			else
				_Menu=("Install Android Q" "Install L4T Ubuntu" "Save changes")
			fi
		fi
		_Menu=("${_Menu[@]}" "Advanced Menu" "Back" "Exit")
		if ! FunctionIsConfigured "eMMC" && ! FunctionIsConfigured "NoFormat"; then
			if ! FunctionAddHosPart; then
				continue
			fi
		fi
		while true; do

			FunctionMenu "Menu" "${_Menu[@]}"
			local _ChosenOption="$retval"
			while true; do
				case "$_ChosenOption" in
					"Back")
						continue 3
					;;
					"Exit")
						FunctionExit
					;;
					"Install second Android Q")
						FunctionInstallAndroidQ "1"
						continue 2
					;;
					"Advanced Menu")
						FunctionMenu "Advanced Menu" "${_AdvancedMenu[@]}" "Back"
						_ChosenOption="$retval"
						if [ "$_ChosenOption" == "Back" ]; then
							continue 2
						fi
					;;
					"Fix MBR")
						FunctionFixMBR "$_Device"
						continue 2
					;;
					"Install Android")
						FunctionInstallAndroid
						continue 2
					;;
					"Install Android Oreo")
						FunctionInstallOreoEx
						continue 2
					;;
					"Install Android Q")
						FunctionInstallAndroidQ
						continue 2
					;;
					"Install L4T Ubuntu")
						FunctionInstallL4T
						continue 2
					;;
					"Add EmuMMC partition")
						FunctionAddEmuMMC "1"
						continue 2
					;;
					"Add another EmuMMC partition")
						if [ ${#EmummcPartitions[@]} -lt 1 ]; then
							echo -e "No EmuMMC partition added yet, can't add another one\n"
							continue 2
						fi
						FunctionAddEmuMMC "$((${#EmummcPartitions[@]}+1))"
						continue 2
					;;
					"Save changes")
						if ! FunctionSaveChanges "$_Device"; then
							continue 2
						else
							continue 3
						fi
					;;
					"Configure EmuMMC 1")
						FunctionConfigEmummc "1"
						continue 2
					;;
					"Configure EmuMMC 2")
						FunctionConfigEmummc "2"
						continue 2
					;;
				esac
			done
		done
	done
}


FunctionMain