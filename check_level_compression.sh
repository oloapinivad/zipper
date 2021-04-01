#!/bin/bash

file=$1
TIMEFORMAT=%R

rm $DIR/*compressed*

echo $file

for deflate in 1 ; do
	echo "#####################"
	echo Deflate Level $deflate
	#time cdo -f nc4 -z zip_$deflate copy $file $file.cdo.compressed$deflate
	#time nccopy -d$deflate $file $file.nccopy.compressed$deflate
	#time nccopy -u -s -d$deflate $file $file.unsh.nccopy.compressed$deflate
	#time ncks --fl_fmt=netcdf4 -L $deflate -O $file $file.ncks.compressed$deflate

	echo "original"
	cdo -s showformat $file
	ncdump -h $file > $DIR/original.ncdump.txt
	echo du: $(du -sh $file | cut -f1)
        #echo ls: $(ls -lh $file | cut -f5 -d" ")
	echo "Access time (multiplication by 2 with CDO):"
        rm -f $file.multiplied
        time cdo -s mulc,2 $file $file.multiplied
        rm -f $file.multiplied


	#kindlist="cdo nccopy shuffling.nccopy ncks"
	kindlist="shuffling.nccopy shuffling.nccopy.chunking shuffling.nccopy.chunking.w"
	for kind in $kindlist ; do

		echo "-------"
                echo $kind
		fileout=$file.$kind.compressed$deflate

		if [[ $kind == "cdo" ]] ; then
			echo "command: cdo -s -f nc4 -z zip_$deflate"
			echo "Compression time: "
			time cdo -s -f nc4 -z zip_$deflate copy $file $fileout
		elif [[ $kind == "nccopy" ]] ; then
			echo "command: nccopy -d$deflate"
			echo "Compression time: "
			time nccopy -d$deflate $file $fileout
		elif [[ $kind == "shuffling.nccopy" ]] ; then
			echo "command: nccopy -k nc7 -w -s -d$deflate"
			echo "Compression time: "
			time nccopy -k nc7 -s -d$deflate $file $fileout
		elif [[ $kind == "shuffling.nccopy.chunking" ]] ; then
                        echo "command: nccopy -k nc7 -s -c time/1 -d$deflate"
                        echo "Compression time: "
                        time nccopy -k nc7 -s -c time/1 -d$deflate $file $fileout
		elif [[ $kind == "shuffling.nccopy.chunking.w" ]] ; then
                        echo "command: nccopy -k nc7 -s -c -w time/1 -d$deflate"
                        echo "Compression time: "
                        time nccopy -k nc7 -s -c time/1 -d$deflate $file $fileout

		elif [[ $kind == "ncks" ]] ; then
			echo "command: ncks -h --fl_fmt=netcdf4 -L $deflate -O"
			echo "Compression time: "
			time ncks -h --fl_fmt=netcdf4 -L $deflate -O $file $fileout
		fi

		cdo -s showformat $file.$kind.compressed$deflate
		echo du: $(du -sh $file.$kind.compressed$deflate | cut -f1)
		#echo ls: $(ls -lh $file.$kind.compressed$deflate | cut -f5 -d" ") 
		orgdim=$(du $file |  cut -f1)
		newdim=$(du $fileout | cut -f1)
		echo "Compression factor:" $(echo "( $orgdim / $newdim )" | bc -l | awk '{printf "%.3f\n", $1}')
		ncdump -h $fileout > $DIR/$kind.ncdump.txt
		echo "Access time (multiplication by 2 with CDO):"
		rm -f $file.multiplied
		time cdo -s mulc,2 $fileout $file.multiplied
		rm -f $file.multiplied

	done
	#echo "Operation time:"
	#time cdo -s mulc,2 $file.compressed $file.multiplied
	#orgdim=$(du $file |  cut -f1)
	#newdim=$(du $file.compressed | cut -f1)
	#du $file.compressed
	#echo "Compression factor:"
	#echo "( $orgdim / $newdim )" | bc -l

done
#rm $file.multiplied  $file.compressed
