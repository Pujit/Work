#!/bin/ksh
##############################################################################
# ++ impdp_active_schema_into_fb.ksh
#-----------------------------------------------------------------------------
# Purpose: receive params, build parfile, run it.
#
#   p1   base_schema_str                         examples include:  MACE  or HTRG_WEB
#   p2   source_dbs=${source_dbs}                examples include:  gmdcPROD  or gmdc_epc5_PROD
#   p3   target_dbs=${target_dbs}                examples include:  gmdcPROD  or gmdc_epc5_PROD
#   p4   comma_sep_list_allowable_errorcodes     optional param syntax is comma sep no spaces:  ora-xxxxx,ora-yyyy
#
# example:                   p1      p2        p3
# ./expdp_active_schema.ksh  mace   gmdcprod   ora-xxxxx,ora-yyyyy
#
#--------------------------------- Modifications -----------------------------
#
# Who                 When       What, Where, Why
# ------------------- ---------- ---------------------------------------------
# Paul Healy          201502016  Intial Version
#
##############################################################################
v_now=`date '+%Y%m%d_%H%M%S'`
echo "in run_expdp_parfile.sh time is $v_now  osuser is `whoami`   OS_PID=$$"
unalias rm  2> /dev/null  # In case alias with -i option exists.

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

# Set environment variables and alias needed for utility programs.
. ${script_path}/dotin_batch_commands

# Set environment variables and alias needed for utility programs.
. ${script_path}/dotin_batch_commands



# Define descriptively named variables for positional parameters.
 v_base_schema_str=${1}
 v_source_dbs=${2}
 v_target_dbs=${3}
 v_comma_sep_list_allowable_errorcodes=${4}

                    v_base_schema_str=`echo ${v_base_schema_str}                     | tr "[:upper:]" "[:lower:]"`    #force lower
                         v_source_dbs=`echo ${v_source_dbs}                          | tr "[:lower:]" "[:upper:]"`    #force UPPER
                         v_target_dbs=`echo ${v_target_dbs}                          | tr "[:lower:]" "[:upper:]"`    #force UPPER
v_comma_sep_list_allowable_errorcodes=`echo ${v_comma_sep_list_allowable_errorcodes} | tr "[:lower:]" "[:upper:]"`    #force UPPER

echo "params:"
echo "                       v_base_schema_str=[${v_base_schema_str}]"
echo "                            v_source_dbs=[${v_source_dbs}]"
echo "                            v_target_dbs=[${v_target_dbs}]"
echo "   v_comma_sep_list_allowable_errorcodes=[${v_comma_sep_list_allowable_errorcodes}]"
echo ""
echo ""
echo ""

if [ "$1"   == "" ]; then  echo "`date '+%Y%m%d_%H%M%S'` ERROR:Param p1 (v_base_schema_str                   ) is blank/missing";    exit 1;    fi
if [ "$2"   == "" ]; then  echo "`date '+%Y%m%d_%H%M%S'` ERROR:Param p2 (v_source_dbs                        ) is blank/missing";    exit 1;    fi
if [ "$3"   == "" ]; then  echo "`date '+%Y%m%d_%H%M%S'` ERROR:Param p3 (v_target_dbs                        ) is blank/missing";    exit 1;    fi
#FYI: $3  is an optional param, ok if blank/missing.

var_fullyqualified_parfile=/tmp/impdp_active_schema_into_fb_${PPID}.par
rm -f  $var_fullyqualified_parfile
touch $var_fullyqualified_parfile
if [[ $? -ne 0 ]]; then
  echo "$script_file: error creating var_fullyqualified_parfile=[${var_fullyqualified_parfile}]"
  echo "$script_file: Terminating script with error status."
  exit 1
fi


# Make sure the utility file run_expdp_parfile.ksh exists
if [[ ! -s ${script_path}/run_expdp_parfile.ksh ]]; then
  echo "$script_file: INSTALLATION ERROR: utility file run_expdp_parfile.ksh is missing/empty"
  echo "$script_file: Terminating script with error status."
  echo "           utility_file=[${script_path}/run_expdp_parfile.ksh.sh]"
  exit 1
fi

if [ "$v_source_dbs" = "GMDC_EPC4_PROD" ]  || [ "$v_source_dbs" = "GMDC_EPC4_PREPROD" ]
then
     v_target_schema=${v_base_schema_str}_ONLINE_FALLBACK   
     v_source_schema1=${v_base_schema_str}_ONLINE
     v_source_schema2=${v_base_schema_str}_ONLINE_p2
fi

if [ "$v_source_dbs" = "GMDC_EPC5_PROD" ] || [ "$v_source_dbs" = "GMDC_EPC5_PREPROD" ]
then
     v_target_schema=GM_CS_${v_base_schema_str}_FB   
     v_source_schema1=GM_CS_${v_base_schema_str}_1
     v_source_schema2=GM_CS_${v_base_schema_str}_2
fi

v_source_dbs_lower=`echo ${v_source_dbs} | tr "[:upper:]" "[:lower:]"`
echo "###########################################################################################################" >> $var_fullyqualified_parfile
echo "# impdp_${v_base_schema_str}_${v_source_dbs}.par"                                                            >> $var_fullyqualified_parfile
echo "#      run: impdp ${v_target_schema}@${v_target_dbs} PARFILE=${var_fullyqualified_parfile}"                  >> $var_fullyqualified_parfile
echo "#  monitor: impdp ${v_target_schema}@${v_target_dbs} attach=zzzimpdp_active_schema"                          >> $var_fullyqualified_parfile
echo "#"                                                                                                           >> $var_fullyqualified_parfile
echo "#"                                                                                                           >> $var_fullyqualified_parfile
echo "###########################################################################################################" >> $var_fullyqualified_parfile
echo "JOB_NAME=zzzimpdp_active_schema"                                                                             >> $var_fullyqualified_parfile
echo "directory=GM_DATA_PUMP"                                                                                      >> $var_fullyqualified_parfile
echo "logfile=GM_DATA_PUMP:impdp_${v_base_schema_str}_${v_source_dbs_lower}.impdp_log"                             >> $var_fullyqualified_parfile
echo "DUMPFILE=GM_DATA_PUMP:expdp_${v_base_schema_str}_${v_source_dbs_lower}_%U.dmp"                               >> $var_fullyqualified_parfile
echo "remap_schema=${v_source_schema1}:${v_target_schema}"                                                >> $var_fullyqualified_parfile
echo "remap_schema=${v_source_schema2}:${v_target_schema}"                                                >> $var_fullyqualified_parfile
echo "REMAP_TABLESPACE=gm_epc5:gm_epc5"                                                                            >> $var_fullyqualified_parfile
echo "PARALLEL=5"                                                                                                  >> $var_fullyqualified_parfile
echo "TABLE_EXISTS_ACTION=REPLACE"                                                                                 >> $var_fullyqualified_parfile
#
#
#
echo ""
echo ""
echo "dynamic parfile has been built: ${var_fullyqualified_parfile}"
cat $var_fullyqualified_parfile


echo ""
echo ""
echo "...  calling run_impdp_parfile.ksh"
    ${script_path}/run_impdp_parfile.ksh   $v_target_schema   $v_target_dbs  0  $var_fullyqualified_parfile   "${v_comma_sep_list_allowable_errorcodes}"
    rtncd=$?
rm -f $var_fullyqualified_parfile 2> /dev/null

if [[ $rtncd -ne 0 ]]; then
  echo "$script_file: fatal error from called script \"run_impdp_parfile.ksh\""
  echo "$script_file: see prior messages..."
  exit 1
fi
echo ""
echo ""
echo ""
echo "`date '+%Y%m%d_%H%M%S'`: success"
echo "$script_file: completed successfully."
