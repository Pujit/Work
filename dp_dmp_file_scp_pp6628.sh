#!/bin/ksh
##############################################################################
# Script Name: dp_dmp_file_scp_pp6628.sh
# ----------------------------------------------------------------------------
# Purpose: Copy Data Pump dump files to a destination server. The destination
#          is determined by settings in ./dm_global_variables for our input param $3 (database_tier)
#          This script will be called from a "wrapper/launcher"
#          script which will ssh to the required user ID (sagm) and will
#          direct all stdout and stderr to a log file. This script will not
#          redirect output or errors.
#
# Input parameters:
#          $1 = Source directory path
#          $2 = Data move file group basename. Format: {expdp}_{tirename}_MinDate_TO_maxdate_*.dmp
#          $3 = database tier [PSIC|PREprod|PROD] (this is our database tier and this param dictates what the dotin of "dm_global_variables" gives us.
#
# Sample call:                         P1					       		P2							P3			
#	./dp_dmp_file_scp_pp6628.ksh	    /				home/pp6628           expdp_Preprod_20160418_TO_20160418_inclusive6628.dmp			preprod	
#										/data/spoepc_dataload/gm_data_pump
#   ./dp_dmp_file_scp_pp6628.sh /home/pp6628 expdp_Preprod_20160418_TO_20160418_inclusive6628.dmp preprod
#    ./dp_dmp_file_scp.ksh    /oemexport/GM/ 					 GM_CEPC_TARGET_AMT9_GMPUBI4_GRP_5_20150903_0933				psic
#
#
# If variable "DM_Oracle_Directory_folder" is defined than we will do a direct scp of files onto that folder
# This also implies that we have an oracle directory variable "DM_Oracle_Directory" that maps to this folder (we check that it does).
# However if variable "DM_Oracle_Directory_folder" is blank (as it is for PSIC) than that means we do not have
# a NAS folder which also an Oracle directory. The only way to get files into such a tier (as PSIC) is to
# stage the files on another tier that as a NAS/Oracle directory and then "slide" those files from Preprod onto PSIC
# via a file_transfer over db_link.
#
# starting with V1.2  this shell script handles file transfer to target directly by SCP or indirectly by SCPing to an interm host and sliding.
#
# -------------------------------- Modifications -----------------------------
# Who                 When     What, Where, Why
# ------------------- -------- ---------------------------------------------
# 
##############################################################################
#
############################################
# step 1 syntax check of input params
############################################
v_now=$(date '+%Y%m%d_%H%M%S')
echo "in dp_dmp_file_scp.sh time is $v_now  osuser is `whoami`   OS_PID=$$"
tm_start=$SECONDS

															# Name of this script file, without path.
script_file=${0##*/}
															# Path to this script. Other scripts are there also. Full path is retrieved then dissected to get clean path.
script_path=$(whence $0) 											# whence returns full path and may include '.' or '..' if this script called using a relative path.

															# If script_path has one or more '/./' in it, remove the '.' notation.
while [[ -z ${script_path##*/./*} ]]; do              						 # ${script_path##*/./*} is null if script_path contains a '/./'
  script_path=${script_path%/./*}/${script_path##*/./} 					# Remove the last "/./"
done
															# If one or more ".." relative paths were used to call this script, remove them from script_path.
while [[ -z ${script_path##*/../*} ]]; do      							 # There is a ".." in the path.
  front_path=${script_path%%/../*}              							# The path up to the first "..".
  front_path=${front_path%/*}                   							# The front_path with the lowest level directory removed.
																# The path to the script file with the "next upper" level directory removed.
  script_path=${front_path}/${script_path#*/../} 						# Combine $front_path with everything after the first "..".
done

script_path=${script_path%/*}  									# Remove the script file name and last / of the path.

															# Test whether all paramters were specified.
if [ "$1"   == "" ]; then  echo "$(date '+%Y%m%d_%H%M%S') ERROR:Param p1 (Source directory path)      is blank/missing";    exit 1;    fi
if [ "$2"   == "" ]; then  echo "$(date '+%Y%m%d_%H%M%S') ERROR:Param p3 (Data move file group basename) is blank/missing"; exit 1;    fi
if [ "$3"   == "" ]; then  echo "$(date '+%Y%m%d_%H%M%S') ERROR:Param p3 (Data move file group basename) is blank/missing"; exit 1;    fi

eval p1=$1
eval p2=$2
     p3="`echo $3 | tr '[a-z]' '[A-Z]'`" 							 #make input param uppercase


echo "params:"
echo "      p1=[${p1}]"
echo "      p2=[${p2}]"
echo "      p3=[${p3}]"

															# Define descriptively named variables for positional parameters.
source_dir=${p1%/}     										 # Strip off ending / if it exists.
group_base_name=$p2
echo "First"
echo $PREPROD_DM_Oracle_Directory
														# Set up basic opr,scp,ssh access by sourcing aliases and env variables.
dm_global_variables=${script_path}/dm_global_variables.sh
#
#
if  [ -f   ${dm_global_variables} ]
then
    . ${dm_global_variables}
else
    echo "FATAL_ERROR: file [${dm_global_variables}] does NOT exist"
    exit 1
fi
. ${dm_global_variables}
echo "PREPROD_DM_Oracle_Directory : [$PREPROD_DM_Oracle_Directory]"

# Determine the SBS environment tier and set variable values.
if ( [ "${p3}"  != "PSIC" ] && [ "${p3}"  != "PREPROD" ] && [ "${p3}"  != "PROD" ] ) || [ "${p3}"  == "" ]
then
    echo "ERROR: param p3 is requred to be one of [PSIC|PREPROD|PROD]"
    echo "       p3=[$p3]"
    exit 1
else
   

   v_gmdc_tier=${p3}
     if [ "${v_gmdc_tier}" = "PROD" ] && [ "`hostname | egrep 'pv|prd' | wc -l | sed -e 's/^ *//g;s/ *$//g'`" != 1 ]
     then
           echo "ERROR: you must run on a PROD server to specify a PROD target tier"
           exit 1
     fi
     # call dm_global_variables again only this time specify v_gmdc_tier so tier specific values populate the generic vars
     . ${dm_global_variables}  ${v_gmdc_tier}
     destination=${DM_Dspoepc_server}

	 echo "DM_Dspoepc_server= [${DM_Dspoepc_server}"]
fi
# echo "debug point a: var destination.............................................................[${destination}]"
# echo "debug point a: var destination_dir.....................................................[${destination_dir}]"
# echo "debug point a: var DM_slide_server_for_scp...................................[${DM_slide_server_for_scp}]"
# echo "debug point a: var DM_slide_folder_for_scp...................................[${DM_slide_folder_for_scp}]"
# echo "debug point a: var DM_slide_files_from_dbs...................................[${DM_slide_files_from_dbs}]"
# echo "debug point a: var DM_slide_files_from_Oracle_Directory..............[${DM_slide_files_from_Oracle_Directory}]"
# echo "debug point a: var DM_slide_dblink.....................................................[${DM_slide_dblink}]"
echo "DM_Oracle_Directory_folder 1: [${DM_Oracle_Directory_folder}]"
if [ "${DM_Oracle_Directory_folder}"  != "" ]
then # this is the typical case we will scp our files directly onto this GMDC tier via
      use_slide_method=0
      destination=$DM_Dspoepc_server
      destination_dir=${DM_Oracle_Directory_folder}
      if  [ "${destination}"  = "" ] || [ "${destination_dir}"  = "" ]
      then
         echo "one or more required variables is empty probably an issue with dotin file dp_global_variables"
         echo "var destination...............[${destination}]"
         echo "var destination_dir...........[${destination_dir}]"
         exit 1
      fi
else
     # to reach here then according to our "dotin" of "dp_global_variables" this tier
     # does NOT have a NAS folder which is mapped to an ORACLE directory. (This is probably PSIC).
     # as such we need to scp our files to some other GMDC server (probably PREprod)
     # and then "slide" those files onto intended tier.
      use_slide_method=1
      destination=$DM_slide_server_for_scp
      destination_dir=$DM_slide_folder_for_scp

      if  [ "${destination}"  = "" ] || [ "${destination_dir}"  = "" ] ||
          [ "${DM_slide_server_for_scp}"              = "" ] ||
          [ "${DM_slide_folder_for_scp}"              = "" ] ||
          [ "${DM_slide_files_from_dbs}"              = "" ] ||
          [ "${DM_slide_files_from_Oracle_Directory}" = "" ] ||
          [ "${DM_slide_dblink}"                      = "" ]
      then
         echo "one or more required variables is empty probably an issue with dotin file dp_global_variables"
         echo "var destination............................[${destination}]"
         echo "var destination_dir........................[${destination_dir}]"
         echo "var DM_slide_server_for_scp................[${DM_slide_server_for_scp}]"
         echo "var DM_slide_folder_for_scp................[${DM_slide_folder_for_scp}]"
         echo "var DM_slide_files_from_dbs................[${DM_slide_files_from_dbs}]"
         echo "var DM_slide_files_from_Oracle_Directory...[${DM_slide_files_from_Oracle_Directory}]"
         echo "var DM_slide_dblink........................[${DM_slide_dblink}]"
         exit 1
      else
         echo ""
         echo ""
         echo "Notice: according to ./ dm_global_variables.sh a direct NAS mount on ${v_gmdc_tier} does not exit"
         echo "        as such are forced to SCP files to ${v_gmdc_tier}"
         echo "        by first scp'ing onto  ${DM_slide_files_from_dbs} [${DM_slide_folder_for_scp}]  "
         echo "        and then \"sliding\" those files onto ${v_gmdc_tier} via gm_admin database link [${DM_slide_dblink}]"
         echo "        this of course is a extra step that will add some elapsed time that we do not endure if a direct NAS mount existed"
         echo ""
      fi
fi
if  [ "${p4}" != "" ] || [ "${p5}" != "" ] || [ "${p6}" != "" ] || [ "${p7}" != "" ] || [ "${p8}" != "" ] || [ "${p9}" != "" ]
then
     echo "ERROR:  unknown/extra params in commandline  (p4=[${p4}]   p5=[${p5}]   p6=[${p6}]   p7=[${p7}]   p8=[${p8}]   p9=[${p9}])"
     exit 1
fi

#
#################################################
# step 2 syntax check/validity of source files
#################################################
# Test the source directory to verify it exists.
if [[ ! -d $source_dir ]]; then
    echo "$(date '+%Y%m%d_%H%M%S') ${script_file}: Source directory location not found."
    echo "$(date '+%Y%m%d_%H%M%S') ${script_file}: Terminating script with error status."
    exit 1
fi


#
############################################
# step 3 syntax check of target scp
############################################
# Test access to GMDC server and check whether the destination directory exists
#      if use_slide_method=0 then this is our final target, if use_slide_method=1 then this is the interm "slide"  target
#

# echo "debug point b: var destination.......................................................................[${destination}]"
# echo "debug point b: var destination_dir..............................................................[${destination_dir}]"
# echo "debug point b: var DM_slide_server_for_scp..............................................[${DM_slide_server_for_scp}]"
# echo "debug point b: var DM_slide_folder_for_scp..............................................[${DM_slide_folder_for_scp}]"
# echo "debug point b: var DM_slide_files_from_dbs.............................................[${DM_slide_files_from_dbs}]"
# echo "debug point b: var DM_slide_files_from_Oracle_Directory......................[${DM_slide_files_from_Oracle_Directory}]"
# echo "debug point b: var DM_slide_dblink............................................................[${DM_slide_dblink}]"


if ! ssh ${destination} test -w ${destination_dir}; then
    echo "$(date '+%Y%m%d_%H%M%S') ${script_file}: Destination directory ${destination_dir} does not exist or is not writable on remote server ${destination}."
    echo "$(date '+%Y%m%d_%H%M%S') ${script_file}: Terminating script with error status."
    exit 1
fi
echo "destinition= [${destination_dir}]"

#
##########################################################################################
# step 4 We want to avoid spending time scp'ing (or sliding) files onto a target
#        only to have the import step blow up because there is a disconnect between
#        what the GM dba defined an oracle directory to mean
#        and the target folder that this shell script is placing files.
#        it only took a few seconds to reach this piont in the shells script
#        lets confirm that IF variable "${DM_Oracle_Directory_folder}" is NOT blank
#        then its contents exactly match view dba_directories for db_link ${DM_Oracle_Directory}
#        if ${DM_Oracle_Directory_folder} is blank then that means we slide files onto
#        ${DM_Oracle_Directory} using DBMS_FILE_TRANSFER.put_file which by definiton
#        means the landing location of the files must be the folder that ${DM_Oracle_Directory} uses
##########################################################################################
    #
    #  4.1    populate username/paswword variables onto target database, confirm they work
    echo "DM_dbs....................$DM_dbs              "
    export  var_username_result=gm_cs_ucr_archive
    export  var_target_dbs=$DM_dbs
    export  var_app_user_pswd=`opr -r   $var_target_dbs  $var_username_result `

    if  [ "${var_app_user_pswd}"  == "" ]
    then
        echo "ERROR: var_app_user_pswd is empty."
        echo "       this is likely because this command did NOT succeed: \"opr -r   $var_target_dbs  $var_username_result\""
        exit 1
    fi

    echo "confirming logon credentials for ${var_username_result}@${var_target_dbs}"
    v_sql_result=`sqlplus  -r 1 -s  /nolog <<EOF
              whenever sqlerror exit 1 rollback
              connect ${var_username_result}@${var_target_dbs}/${var_app_user_pswd}
    EOF`
    rtncd=$?
    if [ ${rtncd} != 0 ]
    then
        echo "ERROR: could NOT log into database as: [${var_username_result}@${var_target_dbs}]  "
        echo "ERROR: aborting script."
        echo rtncd=[$rtncd]
        echo v_sql_result=[$v_sql_result]
        exit 1
     fi
     var_DM_dbs_pswd=$var_app_user_pswd


    #
    # verify oracle directory and NAS folder of our Scp are logically consistent with each other.
    #
    v_sql_result=`sqlplus  -r 1 -s  /nolog <<EOF
              whenever sqlerror exit 1 rollback
              connect ${var_username_result}@${DM_dbs}/${var_DM_dbs_pswd}
              SET PAGESIZE 0 trimout on trimspool on linesize 333  feedback off timing off
              select DIRECTORY_PATH from dba_directories where directory_name = '${DM_Oracle_Directory}';
EOF`
    rtncd=$? 
#   echo "Length of v_sql_result is $(expr "${v_sql_result}" : '.*')" 
    
    if [ ${rtncd} != 0 ]  || ( [ "${DM_Oracle_Directory_folder}"  != "$v_sql_result" ] && [ ""${DM_Oracle_Directory_folder}"" != "" ]  )
    then
        echo "NOTICE: if dotin variable DM_Oracle_Directory_folder is defined to a value (which it needs to be for a direct SCP to occur"
        echo "        echo that that value MUST match the oracle data dictionary settings for the corresponding ORACLE directory"
        echo ""
        echo "ERROR: could NOT confirm the target folder of our SCP  matches the definition of the ORACLE directory"
        echo "       this means even if we succeed in the SCP, a subsequent impdp may (will) fail."
        echo "       Since this step takes minutes to hours better to blow up now so the issue can be fixed ASAP"
        echo ""
        echo "       The issue is mis-match of settings between us and GMDC."
        echo "       This could be the fault of the GM dba who setup the Oracle directory"
        echo "       or it could be a typo in the \"dotin\" file ./dm_global_variables.sh"
        echo ""
        echo "relevelant info:                                      "
        echo "     database.........................................[${DM_dbs}]"
        echo "     Oracle_Directory.................................[${DM_Oracle_Directory}]"
        echo "     dotin variable DM_Oracle_Directory_folder........[${DM_Oracle_Directory_folder}]"    
        echo       oracle data dictonary definiton..................[${v_sql_result}] 
        echo "ERROR: aborting script."
        echo rtncd=[$rtncd]
        echo v_sql_result=[$v_sql_result]
        exit 1
     fi

#
##########################################################################################
# step 5 syntax check of slide params/system (assuming we are using slide method)
##########################################################################################
if [ "$use_slide_method" = "1" ]
then
    #
    # step 5.1  pre-delete files on target server, if we do not do this the slide command will fail.
    #
    v_sql_result=`sqlplus  -r 1 -s  /nolog <<EOF
              whenever sqlerror exit 1 rollback
              connect ${var_username_result}@${DM_dbs}/${var_DM_dbs_pswd}
        DECLARE
        -- delete_file_from_oracle_directory.sql
        --
            v_file_1    UTL_FILE.FILE_TYPE;
            procedure delete_file(in_directory varchar2, in_filename varchar2); -- foreward declaration
            procedure delete_file(in_directory varchar2, in_filename varchar2) is
            BEGIN
                v_file_1  := UTL_FILE.FOPEN  (in_directory, in_filename, 'a');
                             utl_file.fremove(in_directory, in_filename);
            END       delete_file;
        begin
             delete_file(upper(trim('${DM_Oracle_Directory}')),'${group_base_name}_01.dmp');
             delete_file(upper(trim('${DM_Oracle_Directory}')),'${group_base_name}_02.dmp');
             delete_file(upper(trim('${DM_Oracle_Directory}')),'${group_base_name}_03.dmp');
             delete_file(upper(trim('${DM_Oracle_Directory}')),'${group_base_name}_04.dmp');
             delete_file(upper(trim('${DM_Oracle_Directory}')),'${group_base_name}_05.dmp');
             delete_file(upper(trim('${DM_Oracle_Directory}')),'${group_base_name}_06.dmp');
             delete_file(upper(trim('${DM_Oracle_Directory}')),'${group_base_name}_07.dmp');
             delete_file(upper(trim('${DM_Oracle_Directory}')),'${group_base_name}_08.dmp');
             delete_file(upper(trim('${DM_Oracle_Directory}')),'${group_base_name}_09.dmp');
             delete_file(upper(trim('${DM_Oracle_Directory}')),'${group_base_name}_10.dmp');
        end;
/

EOF`
    rtncd=$?
    if [ ${rtncd} != 0 ]
    then
        echo "Prior to performing a slide of files we need to ensure prior copies of these files do NOT exist on $v_gmdc_tier"
        echo "ERROR: could NOT predelete ${v_gmdc_tier} files from oracle directory ${DM_Oracle_Directory}"
        echo "ERROR: aborting script."
        echo rtncd=[$rtncd]
        echo v_sql_result=[$v_sql_result]
        exit 1
     fi
     echo "$v_sql_result"

  ###################################
  # step 5.2
  #   prove variable DM_slide_files_from_dbs works (logon as gm_admin)
  #    5.2.1 once logged on prove variable DM_slide_files_from_Oracle_Directory exists (query dba_directories once loggged)
  #    5.2.2 once logged on prove variable DM_slide_dblink                      exists (query dba_db_links)
  ###################################

    echo "DM_slide_files_from_dbs....................$DM_slide_files_from_dbs "
    export  var_username_result=gm_cs_ucr_archive
    export  var_target_dbs=$DM_slide_files_from_dbs
    export  var_app_user_pswd=`opr -r   $var_target_dbs  $var_username_result `

    if  [ "${var_app_user_pswd}"  == "" ]
    then
        echo "ERROR: var_app_user_pswd is empty."
        echo "       this is likely because this command did NOT succeed: \"opr -r   $var_target_dbs  $var_username_result\""
        exit 1
    fi

    echo "confirming logon credentials for ${var_username_result}@${var_target_dbs}"
    v_sql_result=`sqlplus  -r 1 -s  /nolog <<EOF
              whenever sqlerror exit 1 rollback
              connect ${var_username_result}@${var_target_dbs}/${var_app_user_pswd}
EOF`
    rtncd=$?
    if [ ${rtncd} != 0 ]
    then
        echo "ERROR: could NOT log into database as: [${var_username_result}@${var_target_dbs}]  "
        echo "ERROR: aborting script."
        echo rtncd=[$rtncd]
        echo v_sql_result=[$v_sql_result]
        exit 1
     fi
     var_DM_slide_files_from_dbs_pswd=$var_app_user_pswd

     echo "checking \"slide\" database \"$DM_slide_files_from_dbs\" if needed oracle directory and db_link exist"
     v_sql_result=`sqlplus  -r 1 -s  /nolog <<EOF
              whenever sqlerror exit 1 rollback
              connect ${var_username_result}@${DM_slide_files_from_dbs}/${var_DM_slide_files_from_dbs_pswd}
     declare
     v_dummy varchar2(200) := '';
     begin
         select directory_path into v_dummy from dba_directories where directory_name = upper('${DM_slide_files_from_Oracle_Directory}');
         select db_link        into v_dummy from user_db_links
          where
             db_link like upper('${DM_slide_dblink}.%') /* match on main portion ignore stuff like .MRP.EDC.NAM.GM.COM */
          or db_link    = upper('${DM_slide_dblink}') /* direct match */;
      end;
/
EOF`
  rtncd=$?
    if [ ${rtncd} != 0 ]
    then
        echo "ERROR: encountered issue determining if \"slide\" database \"${DM_slide_files_from_dbs}\" has the needed oracle directory and db_link objects"
        echo "       Please review the error message as well as confirm if:"
        echo "        oracle directory exists........ [${DM_slide_files_from_Oracle_Directory}]"
        echo "       and database link exists ....... [${DM_slide_dblink}]"
        echo " one or the other (or both) are missing"
        echo "ERROR: aborting script."
        echo "rtncd=[$rtncd]"
        echo "v_sql_result=[$v_sql_result]"
        exit 1
    fi

fi




#
##########################################################################################
# step 6 do the real work of the scp (and slide if using slide method )
##########################################################################################

# List the source files to transfer
echo "---------------------------------------------------"
echo "Files to transfer before compress:"
ls -l ${source_dir}/${group_base_name}
echo "--------------------${source_dir}-------------------------------"

# Transfer the files, one by one if "use_slide_method=1" slide immedatly after transfer
for source_file in ${source_dir}/${group_base_name}
do
  if [ "$use_slide_method" = "1" ]
  then
      echo "$(date '+%Y%m%d_%H%M%S') : Transferring to slide server ${source_file} ..."
  else
      echo "$(date '+%Y%m%d_%H%M%S') : Transferring  ${source_file} ..."
  fi
    INFILE=$(whence ${0})
    var_path=${source_file%/*}
    var_file=${source_file##*/}
    var_base=${var_file%.*}         #this string handles embedded periods
     var_ext=${var_file##*.}        #this string handles embedded periods
     source_file_basename="${var_base}.${var_ext}"
	 echo "var_ext= [${var_ext}]"
	 echo "var_base= [${var_base}]"
	 echo "source_file_basename=[${var_base}.${var_ext}]"
	 echo "source_file=[${source_file}]"
	 echo "destination=[${destination}]"
	 echo "destination_dir=[${destination_dir}]"
	 
	 echo "`ssh ${destination} gzip ${destination_dir}/${source_file_basename}`"

  scp -p ${source_file} ${destination}:${destination_dir}
  rtncd=$?
  if [[ $rtncd -ne 0 ]]; then
      echo "$(date '+%Y%m%d_%H%M%S') ${script_file}: Error during scp of ${source_file}."
      echo "$(date '+%Y%m%d_%H%M%S') ${script_file}: Terminating script with error status."
      exit 1
  fi

  #
  # we can not trust source file on richfield to have the priv mask needed in GMDC
  # so despite the "-p" on the scp command let us overide the file privs of the GMDC copy of this file...
    ssh  ${destination} chmod 774 ${destination_dir}/$source_file_basename
    rtncd=$?
    if [ ${rtncd} != 0 ]
    then
        echo "ERROR: could set file privs on file just copied onto gmdc"
        echo         "  command: ssh  ${destination} chmod 774 ${destination_dir}/$source_file_basename"
        echo "ERROR: aborting script."
        exit 1
     fi
	 echo "checkpoint"
      ##############################################################################################################################
      # begin GMCSPUB-6071
      ####################
      #     Provide a sanity check that our scp actually worked.
      #     we "should" be able to rely on a zero return code from scp as proof the file is perfectly transfered.
      #     however as a sanity check let us calculate a check sum on source and on target.
      #     if these match then we have proof they match.
      #     a check sum on the entire file takes "way" too long.
      #     however if there really was a file transmission corruption
      #     or if we have two files of the exact same name but different weeks
      #     if the byte count of the files are the same ("ls" command)
      #     and a checksum of the last 1000 blocks are the same then we have as much proof as we need that files match
      #     both an 'ls' command  and a checksum of 1000 blocks are sub-second fast.
      #     so doing these checks gives us peace of mind as virtually zero cost.
      ##############################################################################################################################
      check_sum_source=`tail -1000b ${source_file} |cksum`
      rtncd=$?
      if [ ${rtncd} != 0 ]
      then
          echo "ERROR: could NOT calculate check sum on source file : [${source_file}]  "
          echo "ERROR: aborting script."
          exit 1
       fi

      check_sum_target=`ssh ${destination} tail -1000b ${destination_dir}/${source_file_basename} |cksum`
      rtncd=$?
      if [ ${rtncd} != 0 ]
      then
          echo "ERROR: could NOT calculate check sum on target file : [${destination_dir}/${source_file_basename}]  "
          echo "ERROR: aborting script."
          exit 1
       fi

       byte_cnt_source=`ls -la ${source_file} | awk '{ print $5}'`
       rtncd=$?
       if [ ${rtncd} != 0 ]
       then
          echo "ERROR: could NOT obtain byte count on source file : [${source_file}]  "
          echo "ERROR: aborting script."
          exit 1
        fi

       byte_cnt_target=`ssh ${destination} ls -la ${destination_dir}/${source_file_basename}  | awk '{ print $5}'`
       rtncd=$?
       if [ ${rtncd} != 0 ]
       then
          echo "ERROR: could NOT obtain byte count on target file : [${destination_dir}/${source_file_basename}]  "
          echo "ERROR: aborting script."
          exit 1
        fi
       if    [ "$check_sum_source"  != "$check_sum_target" ] || [  "$byte_cnt_source"  != "$byte_cnt_target" ]
       then
          echo "ERROR: scp to target seems to have failed, aborting script"
          echo "        check_sum_source............${check_sum_source}"
          echo "        check_sum_target............${check_sum_target}"
          echo ""
          echo "        byte_cnt_source............${byte_cnt_source}"
          echo "        byte_cnt_target............${byte_cnt_target}"
          echo "ERROR: aborting script."
          exit 1
       fi
       ## to reach here we "know" file scp was a success, we have a zero return code from the SCP command, byte counts match, (trailing) check sums match.
       ####################
       # end  GMCSPUB-6071
       ##############################################################################################################################

  echo "$(date '+%Y%m%d_%H%M%S') : Transfer of ${source_file} complete including setting mask to 774"
  if [ "$use_slide_method" = "1" ]
  then
     echo "$(date '+%Y%m%d_%H%M%S') : now \"sliding\" file onto $v_gmdc_tier database ${DM_dbs} "
     v_sql_result=`sqlplus  -r 1 -s  /nolog <<EOF
              whenever sqlerror exit 1 rollback
              connect ${var_username_result}@${DM_slide_files_from_dbs}/${var_DM_slide_files_from_dbs_pswd}
      DECLARE
         v_file_1   UTL_FILE.FILE_TYPE;
      BEGIN

         DBMS_FILE_TRANSFER.put_file (source_directory_object        => '${DM_slide_files_from_Oracle_Directory}',
                                      source_file_name               => '$source_file_basename',
                                      destination_directory_object   => '${DM_Oracle_Directory}',
                                      destination_file_name          => '$source_file_basename',
                                      destination_database           => '${DM_slide_dblink}');
      END;
/
EOF`
  rtncd=$?
    if [ ${rtncd} != 0 ]
    then
        echo "ERROR: encountered \"sliding\" file"
        echo "       Please review the error messages for further details"
        echo "                                                                                                                                         "
        echo "         DBMS_FILE_TRANSFER.put_file (source_directory_object        => '${DM_slide_files_from_Oracle_Directory}',                       "
        echo "                                      source_file_name               => '$source_file_basename',                                         "
        echo "                                      destination_directory_object   => '${DM_Oracle_Directory}',                                        "
        echo "                                      destination_file_name          => '$source_file_basename',                                         "
        echo "                                      destination_database           => '${DM_slide_dblink}');                                           "
        echo ""
        echo "ERROR: aborting script."
        echo "rtncd=[$rtncd]"
        echo "v_sql_result=[$v_sql_result]"
        exit 1
    fi
    echo "$(date '+%Y%m%d_%H%M%S') :\"slide\" of file to target tier complete"
    #
    # to reach here we have successfully "slide" file onto target database
    # as to not polute the interm (slide) server we should delete the file from it
    # so the only location in GMDC the file resides is the intended target tier (probabliy psic).
    ssh  ${destination} rm -f ${destination_dir}/$source_file_basename
    rtncd=$?
    if [ ${rtncd} != 0 ]
    then
        echo "ERROR: could delete file from interm (slide) server"
        echo         "  command: ssh  ${destination} rm -f ${destination_dir}/$source_file_basename"
        echo "ERROR: aborting script."
        echo rtncd=[$rtncd]
        echo v_sql_result=[$v_sql_result]
        exit 1
     fi
    echo "$(date '+%Y%m%d_%H%M%S') : delete of interm file from \"slide\" server is complete"
    echo ""
    echo ""
  fi
  echo ""
done

echo "---------------------------------------------------"
echo "Files are  successfully on target server:"
if [ "$use_slide_method" = "1" ]
then
    echo "The scp of files onto the tareget tier required using the \"slide\" method."
    echo "    Since a direct NAS mount to this folder does not exist"
    echo "    a directory listing of the files on the target tier is not possible"
else
    echo "${destination} ls -l ${destination_dir}/${var_base}*.dmp"
	ssh  ${destination} ls -l ${destination_dir}/${var_base}*.dmp
fi
echo "---------------------------------------------------"
echo "checkpoint"

echo "$(date '+%Y%m%d_%H%M%S') ${script_file}: Dump file copy of group $group_base_name completed successfully."
echo  "script success"
tm_end=$SECONDS
echo "Seconds elapsed: $((tm_end - tm_start))"
