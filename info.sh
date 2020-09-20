#!/bin/bash

if [[ "$1" == "" ]]; then
	echo "No file provided"
	exit 1
fi

file=$1

if [[ ! -f "$file" ]]; then
	echo File does not exist: "$file"
	exit 2
fi

echo Analyzing: "$file"

# number of video streams
numv=`ffprobe -v error -show_entries stream=codec_type "$file" | grep "codec_type=video" | wc -w`

echo Number of video streams: $numv

# encodings
ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$file"

# number of audio streams
numa=`ffprobe -v error -show_entries stream=codec_type "$file" | grep "codec_type=audio" | wc -w`

echo Number of audio streams: $numa

# encodings
ainfo=`ffprobe -v error -select_streams a:0 -show_entries stream=codec_name,profile,channels -of default=noprint_wrappers=1:nokey=1 "$file"`
arrinfo=($ainfo)
aencoding=${arrinfo[0]}
aprofile=${arrinfo[1]}
achannels=${arrinfo[2]}
echo Encoding: $aencoding
echo Profile: $aprofile
echo Channels: $achannels