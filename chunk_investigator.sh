#!/bin/bash

file=$1


chunk=$(ncdump -h -s $file | grep Chunk)
storage=$(ncdump -h -s $file | grep Storage)
compress=$(ncdump -h -s $file | grep Deflate)

echo "Is there storage info?"
echo $storage
echo
echo "Is there chunking?"
echo $chunk
echo
echo "Is this file compressed?"
echo $compress
echo

