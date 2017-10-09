#  sample call  decrypt_tracker_key.sh
#     ./decrypt_tracker_key.sh ${fname}  GMDC_EPC5_PREPROD gm_cs_ucr_archive
#     ./decrypt_tracker_key.sh pgh1.txt  GMDC_EPC5_PREPROD
#     ./decrypt_tracker_key.sh expdp_prod_GM_CS_UCR_2_20150516_01.dmp  GMDC_EPC5_PREPROD  1
#
# receive fname  assume encrypted file ${fname}.gpg exists and decrypt it  based on flag rm the original
#
# ** this file is a proof of concept file from Paul Healy 20170508
# ** this file is functional and does some error checking but it can be made more bullet proof for actual jira implementation.
# This file modified version of decrypt_tracker_key.sh to make more generic. 
#
#################################
#
fname=${1}
opr_param_p1=${2}
opr_param_p2=${3}
rm_source_on_success=${4}
rm -f tracker_key.key
rtncd=$?
if [ $rtncd != 0 ]
then
   echo "ERROR interm tracker_key file preexists and can not delete..."
   exit 1
else
    touch tracker_key.key
    chmod 600 tracker_key.key
    echo $(opr -r ${opr_param_p1} ${opr_param_p2}) >tracker_key.key
    rtncd=$?
    if [ $rtncd != 0 ]
    then
      echo "ERROR could not create interm tracker_key file ..."
      exit 1
    fi
fi
gpg --batch --passphrase-file tracker_key.key --output ${fname} --decrypt  ${fname}
rtncd=$?
if [ $rtncd = 0 ]
then
   if [ "$rm_source_on_success" = "1" ]
   then
      rm ${fname}.gpg
   fi
else
  echo "ERROR was NOT able to successfully encrypt file..."
  exit 1
fi
rm tracker_key.key
