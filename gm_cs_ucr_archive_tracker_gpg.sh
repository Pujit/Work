#!/bin/ksh
##############################################################################
# Script Name: gm_cs_ucr_archive_tracker_gpg.sh 
#This  script is used to list the files in gm_data_pump folder that was exported in the form of .dmp files from tracker_archive table
#Here the dmp file is encrypted using gpg encryption and the encrypted file is generted in this folder with .gpg extension.
# Before running this file we shoul have the format of the dump files that will be generated from script gm_cs_ucr_tracker_expdp.sh
#This files are moved to the Local environment(in richfield ) using the script gm_cs_ucr_tracker_scp.sh 
# 
#
#Input parameters:(in our case the input will be and the path of the local server P1 tier p2 format of file  
#
#          #          $1 = Data move file group basename. Format: {expdp}_{tirename}_MinDate_TO_maxdate_*.dmp
#          
#
#Sample call: by providing the sample dump files                              P1										       	     
#	./PP6628_temp.sh   GMDC_EPC5_PREPROD_4NODE_tracker_20170401_to_201704015_inclusiv.*.dmp	


#
############################################
# step 1 syntax check of input param
############################################
v_now=$(date '+%Y%m%d_%H%M%S')
echo "in dp_dmp_file_scp.sh time is $v_now  osuser is `whoami`   OS_PID=$$"
v_encryption_key="/data/spoepc_dataload/scripts/encrypt_tracker_key.sh"

tm_start=$SECONDS

# Name of this script file, without path.
script_file=${0##*/}
# Path to this script. Other scripts are there also. Full path is retrieved then dissected to get clean path.
script_path=$(whence $0) # whence returns full path and may include '.' or '..' if this script called using a relative path.

# If script_path has one or more '/./' in it, remove the '.' notation.
while [[ -z ${script_path##*/./*} ]]; do               # ${script_path##*/./*} is null if script_path contains a '/./'
  script_path=${script_path%/./*}/${script_path##*/./} # Remove the last "/./"
done
# If one or more ".." relative paths were used to call this script, remove them from script_path.
while [[ -z ${script_path##*/../*} ]]; do       # There is a ".." in the path.
  front_path=${script_path%%/../*}              # The path up to the first "..".
  front_path=${front_path%/*}                   # The front_path with the lowest level directory removed.
  # The path to the script file with the "next upper" level directory removed.
  script_path=${front_path}/${script_path#*/../} # Combine $front_path with everything after the first "..".
done

script_path=${script_path%/*}  # Remove the script file name and last / of the path.

#Determining the tire name
tier=$(hostname)
if (  [ "${tier}"  != "rich-pubx-90-pv.ipa.snapbs.com" ]      && [ "${tier}"  != "rich-pubx-91-pv.ipa.snapbs.com" ]  )

  then tier="PREPROD"
else tier="PROD"
fi


# Test whether all paramters were specified.
if [ "$1"   	== "" ]; then  echo "$(date '+%Y%m%d_%H%M%S') ERROR:Param p1 (Dmp file base name) is blank/missing";    exit 1;    fi


eval p1=$1
     tier="`echo $tier | tr '[a-z]' '[A-Z]'`"  #make tier in uppercase


echo "params:"
echo "      p1=[${p1}]"


source_file_basename=$p1

# Set up basic opr,scp,ssh access by sourcing aliases and env variables.
dm_global_variables=${script_path}/dm_global_variables.sh


#checks if the file  dm_global_variables is present in the given path
if  [ -f   ${dm_global_variables} ]
then
    . ${dm_global_variables}
else
    echo "FATAL_ERROR: file [${dm_global_variables}] does NOT exist"
    exit 1
fi
. ${dm_global_variables}
echo "PREPROD_DM_Oracle_Directory : [$PREPROD_DM_Oracle_Directory]"


# set variable values based on the tier.   

   v_gmdc_tier=${tier}
     if [ "${v_gmdc_tier}" = "PROD" ] && [ "`hostname | egrep 'pv|prd' | wc -l | sed -e 's/^ *//g;s/ *$//g'`" != 1 ]
     then
           echo "ERROR: you must run on a PROD server to specify a PROD target tier"
           exit 1
     fi
     # call dm_global_variables again only this time specify v_gmdc_tier so tier specific values populate the generic vars
     . ${dm_global_variables}  ${v_gmdc_tier}


if [ "${DM_Oracle_Directory_folder}"  != "" ]
then
# Make sure that the source folder in GMDC is there .If this folder is not there  abort the process.
      
      Source_Server_location=$DM_Dspoepc_server
      Source_dir_location=$DM_Oracle_Directory_folder
	  
		echo "Source_Server_location	=	[{$Source_Server_location}]		"
		echo "Source_dir_location		=   [${DM_Oracle_Directory_folder}]	"
		
    if  [ "${Source_Server_location}"  = "" ] || [ "${Source_dir_location}"  = "" ]
      then
         echo "one or more required variables is empty probably an issue with dotin file dp_global_variables"
         echo "var Source_server_location...............[${Source_Server_location}]"
         echo "var Source_dir_location...........[${Source_dir_location}]"
         exit 1
    fi
fi	

#################################################
# step 2 syntax check/validity of source files
#################################################
# Test the source directory to verify it exists and have write permission on the dir.
if ! ssh ${Source_Server_location} test -w ${Source_dir_location}; then
    echo "$(date '+%Y%m%d_%H%M%S') ${script_file}: Destination directory ${Source_dir_location} does not exist or is not writable on remote server ${Source_Server_location}."
    echo "$(date '+%Y%m%d_%H%M%S') ${script_file}: Terminating script with error status."
    exit 1
fi

echo " Source_Server_location=[${Source_Server_location}]	"
echo " and   Source_dir_location=  [$Source_dir_location]	"
echo " source_file_basename= [${source_file_basename}]		"



for files in `ssh $Source_Server_location "ls $Source_dir_location | grep $source_file_basename" ` ; do
#for files in `ssh $Source_Server_location "ls $Source_dir_location| grep $source_file_basename"`;do
echo "Filenames=[$files]"

#check if the file is listed by the above command
#The above ls command can give the files that matches .dmp,.dmp.gpg, .dmp.xxx etc
# to make sure that the file that needs to be encrypted should have .dmp ext. We do not take the file if it has .dmp.xxx extention
#all we need is only .dmp files extension at the last
filename=$(basename "$files")
extension="${filename##*.}"
filename="${filename%.*}"
echo "extension=${extension}"
   if [ $extension != 'dmp' ]; then
	echo " ERROR: the file is not dmp file. So not creating the encryption"
    else
    echo "Greating the .gpg file in the GMDC environment for  $files "
    `ssh $Source_Server_location "$v_encryption_key  $Source_dir_location/$files gmdc_epc5_PREprod 1"`
    echo "Encryption Success"
  fi
echo ""

done
rtncd=$?
echo rtncd=[$rtncd]
    if [ ${rtncd} != 0 ];
    then
        echo " Encryption not succssful "
        echo "ERROR: aborting script."
        echo rtncd=[$rtncd]
        exit 1
    fi

tm_end=$SECONDS
echo "Seconds elapsed: $((tm_end - tm_start))"
