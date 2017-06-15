#  sample call  encrypt_key.sh
#     ./decrypt_encrypt_key.sh ${fname}  ${opr_param_p1)  ${opr_param_p2}   ${del_source_fn_ind}
#     ./encrypt_key.sh pgh1.txt  GMDC_EPC5_PREPROD  tracker_key  1
#     ./encrypt_key.sh expdp_prod_GM_CS_UCR_2_20150516_01.dmp  GMDC_EPC5_PREPROD tracker_key   1
#
# receive fname encrypt it so {fname}.gpg exists  based on flag rm the original
#
# ** this file is a proof of concept file from Paul Healy 20170508
# ** this file is functional and does some error checking but it can be made more bullet proof for actual jira implementation.
#
#################################
#
fname=${1}
opr_param_p1=${2}
opr_param_p2=${3}
rm_source_on_success=${4}

rm -f encrypt_key.key
rtncd=$?
if [ $rtncd != 0 ]
then
   echo "ERROR interm encrypt_key file preexists and can not delete..."
   exit 1
else
    touch encrypt_key.key
    chmod 600 encrypt_key.key
	v_pswd=$(opr -r ${opr_param_p1} ${opr_param_p2})
	if [ "${v_pswd}" == "" ]
	then
      echo "ERROR could not retrive password from opr hence ..."
      echo "ERROR could not create interm encrypt_key file"
      exit 1
	else
	    echo $v_pswd>encrypt_key.key
	fi
fi
gpg2  --batch --passphrase-file encrypt_key.key --symmetric  --no-encrypt-to --no-default-recipient  ${fname}
rtncd=$?
if [ $rtncd = 0 ]
then
   if [ "$rm_source_on_success" = "1" ]
   then
       rm ${fname}
   fi
else
  echo "ERROR was NOT able to successfully encrypt file..."
  exit 1
fi
rm encrypt_key.key

