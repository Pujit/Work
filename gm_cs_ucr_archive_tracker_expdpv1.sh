#!/bin/ksh
##############################################################################
# gm_cs_ucr_archive_tracker_expdp.sh 
#-----------------------------------------------------------------------------
# Purpose: receive 1params, build parfile, run it.The tracker table name used here is different than the production table name.
#should change the name when we go for production.
#
#   
#   p1   source_dbs=${source_dbs}           examples include:  gmdc_epc5_PREprod_4node 
#
# example:                    					p1     						       			
# ./gm_cs_ucr_archive_tracker_expdp.sh    gmdc_epc5_PREprod_4node   
#
#--------------------------------- Modifications -----------------------------
#
# Who                 When       What,   Where, Whyvimcat
# ------------------- ---------- ---------------------------------------------
# Pujit Koirala      20170602     Intial  Version
#
##############################################################################
v_now=$(date +%Y%m%d_%H%M%S)
echo "in expdp_gm_cs_ucr_tracker.sh time is $v_now  osuser is `whoami`   OS_PID=$$"
									# dot in our profile so we inherent OPR and oracle_home settings
. ~/.bash_profile  2> /dev/null  
unalias rm  2> /dev/null  				# In case alias with -i option exists.
									## Get the tier from where the  dump file is created.
tier=$(hostname)
if (  [ "${tier}"  != "rich-pubx-90-pv.ipa.snapbs.com" ]      && [ "${tier}"  != "rich-pubx-91-pv.ipa.snapbs.com" ]  )
then tier="PREPROD"
else tier="PROD"
fi

									# Name of this script file, without path.
script_file=${0##*/}
									# Path to this script. Other scripts are there also. Full path is retrieved then dissected to get clean path.
script_path=$(whence $0) 					# whence returns full path and may include '.' or '..' if this script called using a relative path.

									# If script_path has one or more '/./' in it, remove the '.' notation.
while [[ -z ${script_path##*/./*} ]]; do               # ${script_path##*/./*} is null if script_path contains a '/./'
	script_path=${script_path%/./*}/${script_path##*/./} # Remove the last "/./"
done
									# If one or more ".." relative paths were used to call this script, remove them from script_path.
while [[ -z ${script_path##*/../*} ]]; do       	# There is a ".." in the path.
  front_path=${script_path%%/../*}              	# The path up to the first "..".
  front_path=${front_path%/*}                  	# The front_path with the lowest level directory removed.
									# The path to the script file with the "next upper" level directory removed.
  script_path=${front_path}/${script_path#*/../} # Combine $front_path with everything after the first "..".
done

script_path=${script_path%/*}  			# Remove the script file name and last / of the path.


									# Set environment variables and alias needed for utility programs.
 ${script_path}/dotin_batch_commands



									# Define descriptively named variables for positional parameters.
 v_schema_str=GM_CS_UCR_ARCHIVE
 v_source_dbs=${1}
 

v_schema_str=`echo ${v_schema_str}                 	  	  | tr "[:upper:]" "[:lower:]"`    #force lower
v_source_dbs=`echo ${v_source_dbs}                		| tr "[:lower:]" "[:upper:]"`    #force UPPER
 
if ( [ "$v_source_dbs" == "GMDC_EPC5_PROD_4NODE" ] || [ "$v_source_dbs" == "GMDC_EPC5_PROD" ] ) && [ "$tier" != "Prod" ]
then  
	echo " ERROR: You must be in PROD tier to request the PROD database"
	exit 1
fi



echo "params:"
echo "                       v_schema_str=[${v_schema_str}]"
echo "                       v_source_dbs=[${v_source_dbs}]"
echo ""
echo ""
echo ""
if [ "$1"   == "" ]; then  echo "`date '+%Y%m%d_%H%M%S'` ERROR:Param p1 (v_schema_str ) is blank/missing";    exit 1;    fi
										#FYI: $3  is an optional param, ok if blank/missing.


var_fullyqualified_parfile=/tmp/expdp_gm_cs_ucr_tracker_${PPID}.par


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


											# Obtaining password from OPR 
var_password_result=$(echo $(opr -r $v_source_dbs $v_schema_str))

if [  "${var_password_result}"  == "" ]
then
    echo "ERROR: could NOT retreive password for GM_ADMIN@${v_source_dbs}"
    echo "ERROR: aborting script."
    exit 1
fi


v_sql_result=`sqlplus  -r 1 -s /nolog <<EOF
    whenever sqlerror exit 1 rollback
    connect $v_schema_str/$var_password_result@${v_source_dbs}
    set echo off feedback off timing off time off pagesize 0
EOF`
rtncd=$?
if [  "${rtncd}"  != "0" ]
then
    echo "ERROR: Could not Login. $v_schema_str@${v_source_dbs}"
    echo "ERROR: aborting script."
    exit 1
fi


											# the min and max date is here 

v_sql_result=`sqlplus  -r 1 -s /nolog <<EOF
    whenever sqlerror exit 1 rollback
	 connect $v_schema_str/$var_password_result@${v_source_dbs}
	set echo off feedback off timing off time off pagesize 0
	with Master as(
    select partition_util_pkg.get_dt_for_partition_name(table_name,partition_name) DT
    from user_tab_partitions where table_name ='TRACKER' and partition_name !='P1') 
    select to_char(min(DT),'YYYYMMDD')||'_TO_'|| to_char(max(DT),'YYYYMMDD') mx from master;
EOF`
rtncd=$?
if [  "${rtncd}"  != "0" ]


then
    echo "ERROR: could  min max partition dates. "
    echo "ERROR: aborting script."
    exit 1
fi
if [ "${v_sql_result}" == "_TO_" ]
then 
  echo "NOTICE: Source table has  no partition other than the P1 partition. Aborting the process. "
  exit 0
fi



v_source_dbs_lower=`echo ${v_source_dbs} | tr "[:upper:]" "[:lower:]"`

echo "Parameter file: "$var_fullyqualified_parfile

echo "#################################################################################################"  		>$var_fullyqualified_parfile
echo "# expdp_${v_schema_str}_${v_source_dbs}.par"                                                              				>> $var_fullyqualified_parfile
echo "#      run: expdp ${v_schema_str}@${v_source_dbs}    PARFILE=expdp_${v_schema_str}_${v_source_dbs}.par"   	>> $var_fullyqualified_parfile
echo "#  monitor: expdp ${v_schema_str}@${v_source_dbs}    attach=zzzexpdp_tracker"                     			>> $var_fullyqualified_parfile
echo "#"                                                                                                        							>> $var_fullyqualified_parfile
echo "# parfile was dynamically built: "                                                                        					>> $var_fullyqualified_parfile
echo "#         v_schema_str=${v_schema_str}"                                                                   					>> $var_fullyqualified_parfile
echo "#         v_schema_str=${v_schema_str}"                                                                   					>> $var_fullyqualified_parfile
echo "#         v_source_dbs=${v_source_dbs}"                                                                   					>> $var_fullyqualified_parfile
echo "#"                                                                                                        							>> $var_fullyqualified_parfile
echo "#####################################################################################################"    	>> $var_fullyqualified_parfile
echo "#####################################################################################################"    	>> $var_fullyqualified_parfile
echo "JOB_NAME=zzzexpdp_tracker"                                                                                					>> $var_fullyqualified_parfile
echo "directory=GM_DATA_PUMP"                                                                                   						>> $var_fullyqualified_parfile
echo "logfile=GM_DATA_PUMP:expdp_${tier}_TRACKER_${v_sql_result}_inclusive.expdp_log"                          		>> $var_fullyqualified_parfile
echo "FILESIZE=20G"                                                                                             						>> $var_fullyqualified_parfile
echo "DUMPFILE=GM_DATA_PUMP:expdp_${tier}_TRACKER_${v_sql_result}_inclusive_%U.dmp"                             		>> $var_fullyqualified_parfile
echo "estimate=statistics"                                                                                      						>> $var_fullyqualified_parfile
echo "PARALLEL=1"                                                                                               						>> $var_fullyqualified_parfile
echo "flashback_time=systimestamp"                                                                              					>> $var_fullyqualified_parfile
echo "REUSE_DUMPFILES=YES"                                                                                      						>> $var_fullyqualified_parfile
		#echo "EXCLUDE=STATISTICS"                                                                                      >> $var_fullyqualified_parfile
echo "include=table:\"IN('TRACKER')\""                                                                         					 >> $var_fullyqualified_parfile
echo ""
echo ""
echo "dynamic parfile has been built: ${var_fullyqualified_parfile}"
cat $var_fullyqualified_parfile

echo ""
echo ""
echo "...  calling run_expdp_parfile.ksh"
   ${script_path}/run_expdp_parfile.ksh   $v_schema_str   $v_source_dbs  $var_password_result  $var_fullyqualified_parfile   ora-xxxxx,ora-yyyyy
    rtncd=$?
 -f $var_fullyqualified_parfile 2> /dev/null

if [[ $rtncd -ne 0 ]]; then
  echo "$script_file: fatal error from called script \"run_expdp_parfile.ksh\""
  echo "$script_file: see prior messages..."
  exit 1
fi
echo ""
echo ""
echo ""
echo "`date '+%Y%m%d_%H%M%S'`: expdp was successful"
echo ""

# To reach here we have successfully exported table gm_CS_UCR_archive.TRACKER
# to avoid any confusion we should truncate the source and drop the partitions
# as to leave the archive tracker table in a pristine state for next time.
  echo "v_schema_str= [${v_schema_str}]"
  echo "v_source_dbs= [${v_source_dbs}]"
sqlplus  -r 1 -s /nolog <<EOF
    whenever sqlerror exit 1 rollback
    connect $v_schema_str/$var_password_result@${v_source_dbs}
    set echo off feedback off timing off time off pagesize 0 serveroutput on size 1000000
	DECLARE
      C_TABLE_NAME VARCHAR2(100) := 'TRACKER';
      v_rec user_tab_partitions%ROWTYPE;
      v_partition_refcur SYS_REFCURSOR;
      v_active_schema VARCHAR2(20) ;
      v_sql           VARCHAR2(1000) ;
	BEGIN
       --step 1 populate a refcursor variable which returns the list of Archive tracker partitions to drop.
      execute immediate 'BEGIN  partition_util_pkg.RETURN_PARTITION_LIST(:1, :2); END;'
      using in c_table_name, in out v_partition_refcur;
       --step 2 since we have just exported our data it is safe to truncate source table.
      Execute immediate 'truncate table '||C_TABLE_NAME ; 
        --step 3 since we have just truncated the table it is safe to now loop thru the refcursor and drop the empty partitions. 
      LOOP
        FETCH v_partition_refcur INTO v_rec;
        EXIT   WHEN v_partition_refcur%NOTFOUND;
              v_sql :=
                    'partition_util_pkg.drop_empty_partition('''
                    ||v_rec.table_name
                    || ''','''
                    || v_rec.partition_name
                    || ''')';
               EXECUTE IMMEDIATE ' begin ' || v_sql || '; end;';
      
        
        dbms_output.put_line(v_rec.table_name ||' '||v_rec.partition_name) ;
      END LOOP;
  CLOSE v_partition_refcur;
END;
/
EOF
rtncd=$?
if [  "${rtncd}"  != "0" ]
then
    echo "ERROR encountered when trying to Drop the partitions of ${v_schema_str}.TRACKER@${v_source_dbs}"
    echo "ERROR: aborting script."
    exit 1
fi

echo "rtncd=[$rtncd]"



