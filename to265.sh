#!/bin/bash

######## Defaults ########
audiocodecs=aac-he,ac3
defaultvideooptions="-c:v libx265 -crf 28"
skipsizecheck=0


######## Constants ########
validaudiocodecs=orig,aac-he,aac-lc,ac3

####### Functions ########
usage()
{
	echo ""
	echo "Usage:  to265.sh <source_dir> [-a <audio_codecs>] [-s] [-t <temp_dir>]"
	echo "                                                                                "
	echo "        -a : Specifies the list of acceptable audio codec(s) for the resulting"
	echo "             file(s). If the source audio does not match, it will be converted"
	echo "             to the first one in the list."
	echo "             Valid values: orig, aac-he, aac-lc, ac3"
	echo "             Default:      aac-he,ac3"
	echo "             Example:      -a aac-he,ac3"
	echo "                           If the source audio is aac-he or ac3, it will not be"
	echo "                           converted. If the source audio does not match one of"
	echo "                           these, it will be converted to aac-he."
	echo "                                                                                "
	echo "        -s : Skips size check that the output file is smaller than the original "
	echo "                                                                                "
	echo "        -t : Specifies the location of a temporary directory in which files will"
	echo "             be processed before being moved to the source directory. If not"
	echo "             provided, files will be processed directly in the source directory."
	echo "                                                                                "
	
}

array_contains()
{
	local value="$1"
	shift
	local array=("$@")

	for v in "${array[@]}"; do
		if [[ "$v" == "$value" ]]; then
			return 1
		fi
	done
	return 0
}

set_audio_codecs()
{
	if [[ audiocodecs == "" ]]; then
		echo "No audio codec provided"
		exit 2
	fi
	
	#split by comma
	IFS=', ' read -r -a audiocodecarray <<< "$audiocodecs"
	
	local validaudiocodecsarray
	IFS=', ' read -r -a validaudiocodecsarray <<< "$validaudiocodecs"
	
	#validate
	for a in "${audiocodecarray[@]}"; do
		local ac="$a"
		array_contains "$ac" "${validaudiocodecsarray[@]}"
		local retval=$?
		if [[ $retval == 0 ]]; then
			echo "Unknown audio codec: $ac"
			exit 2
		fi
	done
	
	#audio codec will be the first one
	audiocodec=${audiocodecarray[0]}
	
	#audio options
	defaultaudiooptions=
	
	    case "$audiocodec" in
        aac-he )           	    defaultaudiooptions="-c:a libfdk_aac -profile:a aac_he"
                                ;;
        ac3 )                   defaultaudiooptions="-c:a ac3"
                                ;;
        aac-lc )                defaultaudiooptions="-c:a aac"
								;;
		orig | * )
		                        #default to none / direct copy
		                        defaultaudiooptions=
                                ;;
		esac
}

set_current_audio_options()
{
	if [[ "$audiocodec" == "orig" ]]; then
		return 0
	fi

	local file="$1"
	
	local ainfo=`ffprobe -v error -select_streams a:0 -show_entries stream=codec_name,profile,channels -of csv=nokey=1 "$file"`
	local arrinfo
	IFS=', ' read -r -a arrinfo <<< "$ainfo"
	
	#array 0 == "stream
	local aencoding=${arrinfo[1]}
	local aprofile=${arrinfo[2]}
	local achannels=${arrinfo[3]}
	
	#default to the audio options we intend to use...
	currentaudiooptions="$defaultaudiooptions"

	#...but override to nothing if we have matching audio profiles
	local codec=
	
	#convert these to one of our "codec" strings
	if [[ "$aencoding" == "ac3" ]]; then
		codec="ac3"
	elif [[ "$aencoding" == "aac" && "$aprofile" == "HE-AAC" ]]; then
		codec="aac-he"
	elif [[ "$aencoding" == "aac" && "$aprofile" == "LC" ]]; then
		codec="aac-lc"
	fi
	
	#now, if this is in the list of acceptable formats, don't convert it
	array_contains "$codec" "${audiocodecarray[@]}"
	
	local retval=$?
	
	if [[ $retval == 1 ]]; then
		currentaudiooptions=
	fi
}

set_current_video_options()
{
	local file="$1"

	#Check to see if it's already marked as x265
	currentvideooptions="$defaultvideooptions"
	if [[ "$basefilename" == *x265* ]]; then
		currentvideooptions=
	else
		#If it's not in the filename, try the more time-consuming approach of checking the properties
		vcodec=`ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$file"`
			
		if [[ "$vcodec" == "hevc" ]]; then
			currentvideooptions=
		fi
	fi
}

########## Process Parameters ###########
if [[ "$1" == "" ]]; then
	usage
	exit 1
fi

SOURCEDIR="$1"
shift

if [[ "$SOURCEDIR" == "" ]]; then
	echo "Directory must be provided."
	exit 1
fi

if [[ ! -d "$SOURCEDIR" ]]; then
	echo "Source directory [$SOURCEDIR] does not exist."
	exit 2
fi

while [ "$1" != "" ]; do
    case $1 in
        -a )           	        shift
                                audiocodecs="$1"
                                ;;
		-s )                    skipsizecheck=1
		                        ;;
		-t )					shift
								TEMPDIR="$1"
								;;
        -h | --help )           usage
                                exit
                                ;;
        * )                     echo "Unknown option $1"
								usage
                                exit 1
    esac
    shift
done

## Post-process params ##
set_audio_codecs

if [[ "$TEMPDIR" != "" && ! -d "$TEMPDIR" ]]; then
	echo "Temp directory [$TEMPDIR] does not exist."
	exit 2
elif [[ "$TEMPDIR" == "" ]]; then
	echo "Not using temporary directory."
fi

shopt -s nullglob # Sets nullglob -- makes sure we don't end up with things like "/path/*.m4v" in the loop if *.m4v has no matching files in /path
shopt -s nocaseglob # Sets nocaseglob -- matches extension as case insensitive (i.e. mkv and MKV)
shopt -s extglob # Extended options for pattern matching

sizebefore=`du -sh "$SOURCEDIR"`
sizebefore=`echo $sizebefore |cut -f1`

#This syntax will look in the main directory and subdirectories
for file in "$SOURCEDIR"/*.{avi,m4v,mkv,mp4,wmv} "$SOURCEDIR/"**/*.{avi,m4v,mkv,mp4,wmv}; do
#for file in "$SOURCEDIR"/*.{avi,m4v,mkv,mp4,wmv}; do
	filepath="$file"
	echo Processing: "$filepath"
	
	#Get the filename from the path
	filename="${filepath##*/}"
	
	#Get the base filename without extension
	basefilename="${filename%.*}"

	#Set the current video options
	set_current_video_options "$file"
	
	#Set the current audio options
	set_current_audio_options "$file"

	echo "Video Options for $file: $currentvideooptions"
	echo "Audio Options for $file: $currentaudiooptions"
	
	if [[ "$currentaudiooptions" == "" && "$currentvideooptions" == "" ]]; then
		echo "Nothing to do for file [$file], skipping."
	else
		#Get file directory since we could be here by recursion
		filedir=`dirname "$file"`
		
		#Before doing anything, if it has anything in brackets, rename it, since Bash on Windows isn't handling brackets well
		if [[ "$filename" == *'['*']'* ]]; then
			#Replace the brackets with parens
			newfilename="${filename/\[/(}"
			newfilename="${newfilename/\]/)}"
			newfilepath="$filedir"/"$newfilename"
			
			mv "$filepath" "$newfilepath"
			
			retval=$?
			
			if [ $retval -ne 0 ]; then
				echo "Failed to move $filepath to $newfilepath"
				exit 1
			fi
			
			echo New file name: "$newfilename"
			
			filename="$newfilename"
			filepath="$newfilepath"
			#Get the base filename without extension
			basefilename="${filename%.*}"
		fi
		
		#extension="${filename##*.}"
		#echo $filename
		#echo $extension

		if [[ "$currentvideooptions" != "" ]]; then
			#Replace any instance of h264 or x264 or H.264 in the source file with x265
			outfilename="${basefilename//[xXhH]?(.)264/x265}"
		
			#If the filename is still the same, it didn't contain a 264 annotation, so add x265 to end
			if [[ "$basefilename" == "$outfilename" ]]; then
				outfilename="$basefilename".x265
			fi
		else
				outfilename="$basefilename"
		fi
		
		#TODO: Replace variants of DD[P] with AAC, etc.
		if [[ "$currentaudiooptions" != "" ]]; then
			if [[ "$audiocodec" == "aac-he" || "$audiocodec" == "aac-lc" ]]; then
				outfilename="${outfilename//.DD?(P)/.AAC}"
			elif [[ "$audiocodec" == "ac3" ]]; then
				outfilename="${outfilename//.AAC/.DD}"
			fi
		fi
		
		#always use mkv container
		outfilename="$outfilename".mkv
		
		#Finally, the out path
		outpath="$filedir"/"$outfilename"
		echo Out path: "$outpath"
		
		if [[ "$TEMPDIR" == "" ]]; then
			temppath="$outpath"
		else
			temppath="$TEMPDIR"/"$outfilename"
		fi
	
		
		#Doctor up the paths to escape special chars
		#filepath="$(printf '%q' "$filepath")"
		#outpath="$(printf '%q' "$outpath")"
		
		#Do it!
		#ffmpeg -i "$filepath" -c copy -c:v libx265 -crf 28 -c:a aac "$temppath"
		#For now, preserve the original audio track(s) instead of converting

		#Split options into array to make Bash happy
		IFS=', ' read -r -a vopts <<< "$currentvideooptions"
		IFS=', ' read -r -a aopts <<< "$currentaudiooptions"
		
		ffmpeg -i "$filepath" -c copy "${vopts[@]}" "${aopts[@]}" "$temppath"
		retval=$?
		
		if [ $retval -ne 0 ]; then
			#failed - remove output file
			echo Encoding Failed.
			if [ -f "$temppath" ]; then
				echo Removing: "$temppath"
				rm "$temppath"
			fi
		else
			#success 
			#compare to make sure resulting file is actually smaller
			sourcefilesize=`du "$filepath"|cut -f1`
			outfilesize=`du "$temppath"|cut -f1`
			
			if [[ $skipsizecheck == 1 || $outfilesize -lt $sourcefilesize ]]; then
				#move from temppath to outpath
				if [[ "$temppath" != "$outpath" ]]; then
					mv "$temppath" "$outpath"
					retval=$?
					
					if [ $retval -ne 0 ]; then
						echo "Failed to move file from temp path: $temppath to: $outpath"
						exit 3
					fi
				fi
				
				if [[ "$filepath" != "$outpath" ]]; then
					#success - remove source file
					echo Success.  Removing: "$filepath"
					rm "$filepath"
				fi
			else
				#surprising - result is larger, so delete converted
				echo Out file is larger than source file.  Deleting out file.
				rm "$temppath"
			fi
		fi
	fi
done

shopt -u nullglob # Unsets nullglob
shopt -u nocaseglob # Unsets nocaseglob
shopt -u extglob # Unsets extglob

#report
sizeafter=`du -sh "$SOURCEDIR"`
sizeafter=`echo $sizeafter |cut -f1`
echo "Size before: $sizebefore"
echo "Size after: $sizeafter"