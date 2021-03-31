#!/bin/bash

# script which looks for netcdf files and examine if they 
# are compressed in NetCDF format
# it also list files which are corrupted
# it provides 3 files list (zip, not zip, corrupted) and 
# a report_$user.txt file which is summarizing the analysis
# it has also a do_correct flag which is able to convert with
# nccopy all the files to netcdf4 classic zip format


# select where you want to run the script
#COREDIR=/scratch/users/paolo
#userlist=netcdf4_test
COREDIR=/work/users
#COREDIR=/work/datasets
userlist=$(ls $COREDIR)
#COREDIR=/scratch/users
userlist=arnone

# where to report the analysis
#REPORTDIR=/scratch/users/paolo/netcdf4_report
REPORTDIR=/scratch/users/paolo/netcdf-zipper/enrico2
mkdir -p $REPORTDIR

# you need to scan all the data a first time
# this creates the files list needed for the correction
do_scan=true

# correction flag
# it is doing a whole set of check before removing the old file
do_correct=true

# verbose flag
verbose=true

# loop on the user/folders
for user in $userlist ; do
	echo $user


	# set dir and logfiles
	#DIR=$COREDIR/$user

	#=========----------------------------------------------#
	DIR=$COREDIR/$user/ESMValTool2/esmvaltool_output/TEST/recipe_extreme_events_20201022_124204/preproc/extreme_events/
	#DIR=$COREDIR/$user
	# ------------------------------------------------------#
	notzipfiles=$REPORTDIR/not_compressed_files_${user}.txt
	zipfiles=$REPORTDIR/compressed_files_${user}.txt
	failedfiles=$REPORTDIR/failed_files_${user}.txt
	userreport=$REPORTDIR/report_${user}.txt

	count=0
	rm -f $userreport

	# this is an extra seciryti check
        # if the do_correct section below has been interrupted
        # this block is trying to restoring files in the middle of the operation
	echo "Safecheck, looking for *notcompressed* files in $DIR..."
	list=$(find  $DIR -type f \( -name "*.nc*notcompressed" -o -name "*.nc4*notcompressed" \) )
        for file in $list ; do
		restorefile="${file%.*}"
		echo "Restoring $restorefile ..."
		mv $file $restorefile 
        done

	# start: look for all NetCDF files in the folder
	echo "Looking for NetCDF files in $DIR... "
        echo "Finding files... it may take a while..."
	list=$(find $DIR -type f  \( -name "*.nc" -o -name "*.nc4" \) )
	echo "NetCDF file listing complete!"
	totfile=$(echo $list | wc -w) 
	echo "$totfile found!"

	# loop on filee: check if they are zip or not
	# if not, write them in the $notzipfiles
	# slow operation, a progress bar has been added
	if [[ $do_scan == true ]] ; then
		rm -f $notzipfiles $zipfiles $failedfiles
		for file in $list ; do

			# progress bar
			count=$(($count + 1))
			perc=$(echo "$count / $totfile * 100" | bc -l)
			echo -ne ".... ${perc%.*}%\r"

			# check if zip: grep con "Deflate" properties of ncdump command
			# faster approach than CDO sinfo command by 30%
			#out=$(cdo -s sinfo $file | grep zip )
			ncout=$(ncdump -h -s $file)
			if [ $? -eq 0 ]; then
			
				out=$(echo $ncout | grep DeflateLevel)

				# zip properties have been found?
				if [[  -z $out ]] ; then
					echo $file >> $notzipfiles
				else 
					echo $file >> $zipfiles
				fi
			else
				echo $file >> $failedfiles
			fi

		done
	fi

	# write the report: number of total files and number of not zip files
	echo ""
	[[ -f $notzipfiles ]] && nfile=$(cat $notzipfiles | wc -l) || nfile=0
	[[ -f $failedfiles ]] && cfile=$(cat $failedfiles | wc -l) || cfile=0
	[[ -f $zipfiles ]] && zfile=$(cat $zipfiles | wc -l) || zfile=0
	echo "In $DIR we have:" | tee -a $userreport
	echo "$user: $totfile NetCDF files" | tee -a $userreport
	echo "$user: $cfile Corrupted files have been found"| tee -a $userreport
	echo "$user: $zfile NetCDF4 Zip files have been found"| tee -a $userreport
	echo "$user: $nfile NetCDF not compressed files have been found"| tee -a $userreport

	# write the report: occupied space (not zip files) need to loop it to avoid "arg too long" error in du
	if [[ -f $notzipfiles ]] ; then
		tmpfile=tmp_$RANDOM.txt
		for file in $(cat $notzipfiles) ; do du -k $file | cut -f1 >> $tmpfile ; done
		room=$(echo "$(paste -sd+ $tmpfile | bc) / 1000 / 1000" | bc)
		#room=$(du -ch $(cat $notzipfiles ) | tail -1) 
		rm -f $tmpfile
	else 
		room=0
	fi

	# write the report: occupied space (zip file) need to loop it to avoid "arg too long" error in du
        if [[ -f $zipfiles ]] ; then
                tmpfile=tmp_$RANDOM.txt
                for file in $(cat $zipfiles) ; do du -k $file | cut -f1 >> $tmpfile ; done
                roomzip=$(echo "$(paste -sd+ $tmpfile | bc) / 1000 / 1000" | bc)
                rm -f $tmpfile
        else
                roomzip=0
        fi

	echo "$user: total occupied space is $(du -sh --block-size=1G $DIR | cut -f1) GB " | tee -a $userreport
	echo "$user: a total of $roomzip GB of NetCDF4 Zip files" | tee -a $userreport
	echo "$user: a total of $room GB of uncompressed NetCDF files" | tee -a $userreport

	# beta: correction of files
	if [[ $do_correct == true ]] ; then

		# set counters 
		failcount=0
		newcount=0
		unzipcount=0

		# logs: 3 files category
		convertedfiles=$REPORTDIR/success_converted_files_${user}.txt
        	failconvertfiles=$REPORTDIR/fail_converted_files_${user}.txt
		unzippablefiles=$REPORTDIR/unzippable_converted_files_${user}.txt

		# loop on files
		for file in $(cat $notzipfiles)  ; do

			t0=$(date +%s)

			# progress bar
			echo "$((failcount + unzipcount + newcount + 1)) / $nfile: Zipping $file ..."

			# synda exclude
			#syndacheck=$(echo $file | grep synda)
			#if [[ ! -z $syndacheck ]] ; then
			#	echo "This is a synda file, ignore it!"
			#	echo $file >> $failconvertfiles
                        #        failcount=$((failcount + 1 ))
			#	continue
			#fi

			# safeflag: if at any level something goes wrong, 
			# set it to true
			safeflag=false
			# zip flag to identify compression factor <1
			zipflag=false

			# safe procedure: move old file
			mv $file $file.notcompressed

			# if this command fails, avoid any other operation
			if [ $? -eq 1 ]; then
				echo "Impossible to operate, skipping ..."
				echo $file >> $failconvertfiles
                                failcount=$((failcount + 1 ))
				continue
			fi

			# remove compressed file for security
			rm -f  $file.compressed

			# check if a time dimension exist: if it is the case, set chunking for time to 1
			timecheck=$(ncdump -h $file.notcompressed | grep "time")
			if [[ ! -z $timecheck ]] ; then
				chunkflag="-c time/1"
			else 
				chunkflag=""
			fi

			# compress with netcdf4 classic and shuffling, deflate level 1
			# safer and more efficient option to reduce file dimension and preserve
			# file structure
			[[ $verbose == true ]] && echo "nccopy -s -k nc7 -d1 $chunkflag $file.notcompressed $file.compressed"
			nccopy -s -k nc7 -d1 $chunkflag $file.notcompressed $file.compressed

			# if the new file is created, check new file integrity and set ownership/permissions
			if [ $? -eq 0 ]; then

				orgdim=$(du $file.notcompressed |  cut -f1)
        			newdim=$(du $file.compressed | cut -f1)
				zipfactor=$(echo "( $orgdim / $newdim )" | bc -l)

				# before check if conversion is worth
				if (( $(echo "$zipfactor > 1" |bc -l) )) ; then

					echo "Compression factor: $(printf "%0.2f\n" $zipfactor)"


 					[[ $verbose == true ]] && echo "touch -r $file.notcompressed $file.compressed"
                                        touch -r $file.notcompressed $file.compressed
                                        exst3=$(echo $?)
					# fixing permission, ownsership and timestamp, heritage from previous file
					echo "Setting permission/ownership $file.compressed ..."
                                	[[ $verbose == true ]] && echo "chmod --reference=$file.notcompressed $file.compressed"
                                	chmod --reference=$file.notcompressed $file.compressed
                                	exst1=$(echo $?)
                                	[[ $verbose == true ]] && echo "chown --reference=$file.notcompressed $file.compressed"
                                	chown --reference=$file.notcompressed $file.compressed
                                	exst2=$(echo $?)

                                	# this is very slow, but check all the records
                                	[[ $verbose == true ]] && echo "cdo -s info $file.compressed >/dev/null 2>&1"
					echo "Scanning $file.compressed ..."
                                	cdo -s info $file.compressed >/dev/null 2>&1
                                	exst4=$(echo $?)

					# if file is ok and ownwership/permissions too, replace the original
					if [ $exst1 -eq 0 ] && [ $exst2 -eq 0 ] && [ $exst3 -eq 0 ] && [ $exst4 -eq 0 ] ; then

						mv $file.compressed $file
	
						# if mv is ok, remove the not compressed, increase counter and list the file
						if [ $? -eq 0 ]; then
							echo "Compression succeeded!"
							rm $file.notcompressed
							newcount=$((newcount + 1))
							echo $file >> $convertedfiles
						else
							echo "Unable to replace original file..."
							safeflag=true
						fi
					else 
						echo "Failed Permission/Ownership/Timestamp/Filecheck..." $exst1 $exst2 $exst3 $exst4
						safeflag=true
					fi
				else
					echo "Failed for compression factor smaller than one: $zipfactor"
					safeflag=true
					zipflag=true
				fi
			else
				echo "Conversion failed during ncopy..."
				safeflag=true
			fi


			# if something hasn't gone as expected, restore original file and remove compressed
			if [[ "$safeflag" = true ]] ; then
				echo "Restoring $file.notcompressed ..."
				mv $file.notcompressed $file
				if [[ "$zipflag" = true ]] ; then
					echo $file >> $unzippablefiles
					unzipcount=$((unzipcount + 1 ))
				else
					echo $file >> $failconvertfiles
					failcount=$((failcount + 1 ))
				fi
				rm -f $file.compressed
			fi
			t1=$(date +%s)
			echo "Process time: $((t1-t0)) sec"
			echo "---------------------------"

		done

		echo "$user: $newcount NetCDF files have been successfully converted to NetCDF4 classic Zip"| tee -a $userreport
		echo "$user: $failcount NetCDF files have been not been converted to NetCDF4 classic Zip (failed)"| tee -a $userreport
		echo "$user: $unzipcount NetCDF files have been not been converted to NetCDF4 classic Zip (compression factor <1)"| tee -a $userreport
		echo "$user: after this script total occupied space is $(du -sh --block-size=1G $DIR | cut -f1) GB" | tee -a $userreport
	fi
				


done

