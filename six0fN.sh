#!/bin/ksh
#convert_tracker_dmp_gz_files_to_gpg.sh
##This file is used to  encrypt the gz file and generate the gpg files for all the archive tables that are already there in our location

# usage: ./gm_cs_ucr_archive_encrypt_to_gpg_local.sh 

##############################################################################
# gm_cs_ucr_archive_encrypt_to_gpg_local.sh
#-----------------------------------------------------------------------------
# Purpose: This file is used to  encrypt the gz file and generate the gpg files for all
# the archive tables that are already there in our location
#
#   
#  
# example:  just execute the script to convet  the files of the defined format in the c_source_file_dir   to .gpg                					     						       			
# ./gm_cs_ucr_archive_encrypt_to_gpg_local.sh    [folder]  [file_ls_cmd]
#--------------------------------- Modifications -----------------------------
#
# Who                 When       What,   Where, 
# ------------------- ---------- ---------------------------------------------
# Pujit Koirala      20170623     Intial  Version
#
##############################################################################



v_now=$(date '+%Y%m%d_%H%M%S')
echo "in gm_cs_ucr_archive_encrypt_to_gpg_local.sh time is $v_now  osuser is `whoami`   OS_PID=$$"

c_source_file_dir="/A/GM/GM-Tracker/wip/"  ## location of .dmp.gz files

## Determine the tier name.
tier=$(hostname)
if (  [ "${tier}"  != "rich-pubx-90-pv.ipa.snapbs.com" ]      && [ "${tier}"  != "rich-pubx-91-pv.ipa.snapbs.com" ]  )
then tier="GMDC_EPC5_PREPROD"
else tier="GMDC_EPC5_PROD"
fi


# if the file of required format is in the directory or not.If 
file_empty_check=`ls  $c_source_file_dir | egrep "*.dmp.gz"`
if [ -z "$file_empty_check" ]; then
 echo "Warning: There are no files in the $c_source_file_dir with *.dmp.gz extension"
  exit 0
fi



for files in `ls  $c_source_file_dir | egrep "*.dmp.gz"`  ; do
 
echo "Processing file: [$files]"
echo "Step 1 unzip"
#uncompress the files in the source dir using gunzip filename
gunzip -f $c_source_file_dir$files
# With gunzip the file will have extension of .dmp from .dmp.gz .So terminating the .gz extension for $files to get the .dmp file name before we encrpyt it.
filename_dmp="${files%.*}"
echo "unzip complete"
echo "step 2 encrypting file: [$filename_dmp]"
#echo "Full path for the file to be encrypted $c_source_file_dir$files GMDC_EPC5_PREPROD 1"
./encrypt.sh $c_source_file_dir$filename_dmp $tier  tracker_key 1
echo "encryption complete"
echo "---------------------------------------------------------------"
done
rtncd=$?
echo rtncd=[$rtncd]
    if [ ${rtncd} != 0 ]
    then
        echo " Unzip and encryption not successfuul "
        echo "ERROR: aborting script."
        echo rtncd=[$rtncd]
        exit 1
     fi


echo " "
##./encrypt_tracker_key.sh /A/GM/GM-Tracker/wip/GMDC_EPC5_PREPROD_4NODE_tracker_20170401_to_201704015_inclusive_02.dmp.gz GMDC_EPC5_PREPROD 1
