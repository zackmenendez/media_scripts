#!/bin/bash

if [[ "$1" == "" ]]; then
	echo "Directory must be provided."
	exit 1
fi

SOURCEDIR="$1"

if [[ ! -d "$SOURCEDIR" ]]; then
	echo "Directory [$SOURCEDIR] does not exist."
	exit 2
fi

shopt -s nullglob # Sets nullglob -- makes sure we don't end up with things like "/path/*.m4v" in the loop if *.m4v has no matching files in /path
shopt -s nocaseglob # Sets nocaseglob -- matches extension as case insensitive (i.e. mkv and MKV)
shopt -s extglob # Extended options for pattern matching

process_directory()
{
	local dir=$1
	
	#echo Processing "$dir"

	# We can put a file in our directory as an instruction to skip it
	if [ -f "$dir"/.skip265 ]; then
		return 0
	fi
	
	# Depth first
	for f in "$dir"/*; do
		if [ -d "$f" ]; then
			process_directory "$f"
		fi
	done
	
	hasaacsurr=0

	for file in "$dir"/*.{avi,m4v,mkv,mp4,wmv}; do
		filename="${file##*/}"
		
		ainfo=`ffprobe -v error -select_streams a:0 -show_entries stream=codec_name,profile,channels -of csv=nokey=1 "$file"`
		
		IFS=', ' read -r -a arrinfo <<< "$ainfo"
		
		#echo "$ainfo"

		
		#arrinfo=($ainfo)
		#array 0 == "stream
		aencoding=${arrinfo[1]}
		aprofile=${arrinfo[2]}
		achannels=${arrinfo[3]}
		#echo "$file"
		#echo Encoding: "$aencoding"
		#echo Profile:  "$aprofile"
		#echo Channels: "$achannels"
		
		if [[ "$aencoding" == "aac" && "$aprofile" != "HE-AAC" && "$achannels" -gt 2 ]]; then
			#echo "Surround but not HE-AAC: $file"
			hasaacsurr=1
			break
		fi

		#Check to see if it's not marked as x265
		#if [[ "$filename" != *x265* ]]; then
		
			#If it's not in the filename, try the more time-consuming approach of checking the properties
			#vcodec=`ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$file"`
			
			#if [[ "$vcodec" != "hevc" ]]; then
			#	hasunconverted=1
			#	break
			#fi
		#fi
	done
	
	if [[ hasaacsurr -eq 1 ]]; then
		echo $dir
	fi
}

for dir in "$SOURCEDIR"; do
	process_directory $dir
done

shopt -u nullglob # Unsets nullglob
shopt -u nocaseglob # Unsets nocaseglob
shopt -u extglob # Unsets extglob
