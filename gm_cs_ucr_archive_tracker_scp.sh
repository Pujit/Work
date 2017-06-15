#!/bin/ksh
##############################################################################
# Script Name: gm_cs_ucr_archive_tracker_scp.sh 
#              gm_cs_ucr_archive_tracker_scp.sh 

#Purpose: receive params as the path to the local server where the scp will be kept
#This  file is used to list all  the encrypted files in gm data pump folder that was created by gm_cs_ucr_archive_tracker_gpg.sh .
#Here also the .gpg  file is are  'scp'ed  to the local server, then head checksum of first 1000bytes 
#and tail checksum of last 1000bytes for each file is generated.If the head and tail of source and destination of all the files matches
# then we have safely migrated the data from soruce to destination.With this assurance we can now delete the source .gpg files to free the 
#space 
#This files are moved to the Local environment(in richfield ) using the gm_cs_ucr_archive_tracker_scp.sh
#Here the file format of the dump file created is given with grep syntax as v_gpg_file_format="GMDC_EPC5_${v_gmdc_tier}_4NODE_tracker_20170401_to_201704015_inclusiv_.*.gpg"
#
#Input parameters:(in our case the input will be the path of the local server  
#          $1 = local server path
#          
#
#Sample call: ./filename pathname                             P1										       	     
#	./gm_cs_ucr_archive_tracker_scp.sh /A/GM/GM-Tracker/wip/
#--------------------------------- Modifications -----------------------------
#
# Who                 When       What,   Where, Whyvimcat
# ------------------- ---------- ---------------------------------------------
# Pujit Koirala      20170612     Intial  Version
#
##############################################################################


#
############################################
# step 1 syntax check of input param
############################################
v_now=$(date '+%Y%m%d_%H%M%S')
echo "in dp_dmp_file_scp.sh time is $v_now  osuser is `whoami`   OS_PID=$$"

#make the  tier vairable upper and move to 96 
v_gpg_file_format="GMDC_EPC5_PREPROD_4NODE_tracker_20170401_to_201704015_inclusive_.*.gpg"
v_scp_tracker=$1

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
if (  [ "${tier}"  != "rich-pubx-90-pv.ipa.snapbs.com" ] && [ "${tier}"  != "rich-pubx-91-pv.ipa.snapbs.com" ]  )
 then tier="PREPROD"
else tier="PROD"
fi

# Test whether all paramters were specified.
if [ "$1"   	== "" ]; then  echo "$(date '+%Y%m%d_%H%M%S') ERROR:Param p1 (Dmp file base name format) is blank/missing";    exit 1;    fi


eval p1=$1
     tier="`echo $tier | tr '[a-z]' '[A-Z]'`"  #make input param uppercase

echo "params:"
echo "      p1=[${p1}]"

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
echo "debug PREPROD_DM_Oracle_Directory : [$PREPROD_DM_Oracle_Directory]"

# set variable values based on the tier.   

   v_gmdc_tier=${tier}
     if [ "${v_gmdc_tier}" = "PROD" ] && [ "`hostname | egrep 'pv|prd' | wc -l | sed -e 's/^ *//g;s/ *$//g'`" != 1 ]
     then
           echo "ERROR: you must run on a PROD server to specify a PROD target tier"
           exit 1
     fi
     # call dm_global_variables again only this time specify v_gmdc_tier so tier specific values populate the generic vars
     . ${dm_global_variables}  ${v_gmdc_tier}
	 v_gpg_file_format="GMDC_EPC5_${v_gmdc_tier}_4NODE_tracker_20170401_to_201704015_inclusive_.*.gpg"
	 v_gpg_file_format="GM_DATA_PUMP_expdp_(PROD|PREPROD)_TRACKER_.{8}_TO_.{8}_inclusive_.{2}.dmp"
						


if [ "${DM_Oracle_Directory_folder}"  != "" ]
then
# Make sure that the source folder in GMDC is there .If this folder is not there  abort the process.
      
      Source_Server_location=$DM_Dspoepc_server
      Source_dir_location=$DM_Oracle_Directory_folder
	  #v_gpg_file_format="GMDC_EPC5_PREPROD_4NODE_tracker_20170401_to_201704015_inclusive_.*.gpg"
	 # "expdp_${tier}_TRACKER.*. dmp"
	  
		echo "Source_Server_location	=	[{$Source_Server_location}]		"
		echo "Source_dir_location		=   [${DM_Oracle_Directory_folder}]	"
		echo "v_gpg_file_format=[$v_gpg_file_format]"
		
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
# Test the source directory which has .gpg file exists and have write permission on the dir.
if ! ssh ${Source_Server_location} test -w ${Source_dir_location}; then
    echo "$(date '+%Y%m%d_%H%M%S') ${script_file}: Destination directory ${Source_dir_location} does not exist or is not writable on remote server ${Source_Server_location}."
    echo "$(date '+%Y%m%d_%H%M%S') ${script_file}: Terminating script with error status."
    exit 1
fi
echo "test"
if ! ( test -w ${v_scp_tracker} ); then
    echo "$(date '+%Y%m%d_%H%M%S') ${script_file}: Local directory ${v_scp_tracker} does not exist or it has not writable permission."
    echo "$(date '+%Y%m%d_%H%M%S') ${script_file}: Terminating script with error status."
    exit 1
fi

echo " Source_Server_location=[${Source_Server_location}]	"
echo " and   Source_dir_location=  [$Source_dir_location]	"


for files in `ssh ${Source_Server_location} ls ${Source_dir_location}| egrep $v_gpg_file_format` ; do

#If there is already the same file present in the destinition folder then remove it before scp begins
rm ${v_scp_tracker}$files

echo "Current scp  file in progress [$files] "
`scp -p ${Source_Server_location}:${Source_dir_location}/$files $v_scp_tracker`
rtncd=$?
			if [  "${rtncd}"  != "0" ]
			then
				echo "ERROR: Files transfer from source to destinition not successfully "
				echo "ERROR: aborting script."
				exit 1
			else echo "Files  successfully transfered."	
			fi


#Verification of source file and destinition are intact after file transfer.Few head blocks  and few Tail blocks
#formform the source and destinition of each file  is compared to find if the source and destinition are intact.
v_head_local=`head -1000b $v_scp_tracker/$files |cksum`
#v_head_local_cksum_val=$(echo $v_head_local | awk '{print $2}')
v_head_remote=`ssh ${Source_Server_location} head -1000b  ${Source_dir_location}/$files |cksum`
echo "-----------------------HEAD-----------------------------------------------------------------------------------------	"
echo " v_head_local  			= 	 	[${v_head_local}] 			"
echo "  v_head_remote			=    	[${v_head_remote}]			"
 
 v_tail_local=`tail -1000b $v_scp_tracker$files |cksum`
 v_tail_remote=`ssh ${Source_Server_location} tail -1000b  ${Source_dir_location}/$files |cksum`
  
echo "-------------------------TAIL------------------------------------------------------------------------------------------	"
echo "  v_tail_local  			= 	 	[${v_tail_local}] 			"
echo "  v_tail_remote			=    	[${v_tail_remote}]			"

	
	if [ "$v_tail_local" != "$v_tail_remote" ] && [ "$v_head_local" != "$v_head_remote" ]; then  
 		echo " ERROR: Data mismatch between source and destination for filename = [${files}] "
		echo ""
		exit 1
		else 
		echo "The file has been copied successfully  and is intact with  the sorce file as the head and tail count for the files matches."
##After successful file transfer we will drop the source files.
		echo "Deleting  source file from GMDC ............."
		`ssh ${Source_Server_location} rm ${Source_dir_location}/$files`
		 rtncd=$?
			if [  "${rtncd}"  != "0" ]
			then
				echo "ERROR: Files not dropped successfully from source schema"
				echo "ERROR: aborting script."
				exit 1
			else echo "Files Deleted successfully"	
			fi
	fi
done
tm_end=$SECONDS
echo "Seconds elapsed: $((tm_end - tm_start))"