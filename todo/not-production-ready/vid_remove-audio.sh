#!/bin/bash

# $1 is input, $2 is output
ffmpeg -i "$1" -vcodec copy -an "$2"

