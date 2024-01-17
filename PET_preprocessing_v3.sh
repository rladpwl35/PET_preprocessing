input.nii  masked_pet.nii.gz  pet.nii  result.nii
#!/bin/sh
# script for execution of corresgisteration PET to MNI
# KYJ
#debug~ 
help()
{
	echo ""
	echo "==============================================="
	echo "==== PET preprocessing pipeline for Docker ===="
	echo "==============================================="
	echo ""
	echo ""
	echo "--> Pipeline for PET preprocessing. " 
	echo ""
	echo "	     #=====================================================================================================================================#"	
	echo ""
	echo "	       <STAGE>                   <Description>                                                         <Related option>     "
	echo ""	
	echo "		Step01	            N4 bias field correction (N.Tustison et al., 2010)					                              "			
	echo "		Step02 	            T1 <=> MNI template registration                                              --regi_mode | --Quick "
	echo "		Step03	            PET <=> T1 registration 						                              --regi_mode | --Quick "
	echo "		Step04              Nonlinear registration		      					                          --regi_mode | --Quick "
	echo "		Step05              Extract PET-SUVr values & re-calc individual CTX SUVr values		          --std_voi		"
	echo ""
	echo "    There should be a PET & T1 image in the working directory."
	echo "    The file name of each PET image should be saved as [SubjectName_PET(or pet).nii(or .nii.gz)],"
	echo "    and the file name of T1 should be [SubjectName_T1(or t1).nii(or .nii.gz)], respectively."
	echo ""
	echo "	     #=====================================================================================================================================#"
	echo ""
	echo "Usage:: >> sh PET_preprocessing.sh -s <string> <options>"
	echo ""
	echo ""
	echo "Input Argument Options::"
	echo ""
	echo ""
	echo "(1) -s <string>"
	echo "		: Subject name, it will be the prefix of the outputs generated in this process"
	echo ""
	echo "(2) --regi_mode=<\"fsl\" or \"ants\">"
	echo "		: registration method (default: \"FSL\")"
	echo ""		
	echo "(3) --reset_from=<step_name>"
	echo "		: Restart from the specified stage. e.g.--reset_from=Step02"
	echo ""
	echo "(4) --reset_to=<step_name>"
	echo "		: Run up to and including the specified stage. e.g.--reset_to=Step03"
	echo ""
	echo "(5) --Quick=<\"yes\" or \"no\">"
	echo "      : Run the antsRegistrationSyNQuick.sh instead of antsRegistrationSyN.sh when Step02,3,4:registration (default : \"yes\")"
	echo ""
	echo "(6) --std_voi=<\"cg\", \"pons\", \"wc\" or \"wcb\""
	echo "      : standard VOIs mask(CG, Pons, WC, WC+B) for extract PET-SUVr values from normalized PET images (default : \"wc\")"
	echo ""
	echo ""   
	echo ""   	



	
}
start=`date +%s.%N`
if [ $# -eq 0 ]; then help ; exit 1 ; fi




echo ''
echo ''
echo '--------------------------------------------------------------'
echo "###=== PET preprocessing pipeline. Code by KYJ ===###"
echo '--------------------------------------------------------------'
echo ''
echo ''

###===Input Argument Setting===###
optconfig="s:-:"  
while getopts "$optconfig" opt ;do
    case $opt in
    	s) sub=$OPTARG;;
		-)
			case $OPTARG in
					workdir=*) workdir=${OPTARG#*=};;
					regi_mode=*) rflag=${OPTARG#*=};;
					reset_from=*) start_step=${OPTARG#*=};;
					reset_to=*) end_step=${OPTARG#*=};;
					Quick=*) q_flag=${OPTARG#*=};;
					acpc_align=*) acpc_flag=${OPTARG#*=};;
					std_voi=*) svoi=${OPTARG#*=};;
					*)
						echo "Unknown option argument : "$OPTARG; help
            			exit 1
           			;;
			esac;;
		
        *)  
            echo "Unknown option argument : "$OPTARG; help
            exit 1
            ;;
    esac
done

###===Default Initialization===###
if [ -z ${sub} ] ;then help ; exit 1 ;fi
if [ -z ${workdir} ] ;then workdir="/mnt/apps/trr/tomcat/file_upload/analysis_pet/result/" ;fi
if [ -z ${rflag} ] ;then rflag="ants" ;fi
if [ -z ${start_step} ] ;then start_step="Step01" ;fi
if [ -z ${end_step} ] ;then end_step="Step06" ;fi
if [ -z ${q_flag} ] ;then q_flag="yes" ;fi
if [ -z ${acpc_flag} ] ;then acpc_flag="no" ;fi
if [ -z ${svoi} ] ;then svoi="wc" ;fi

# -z 문자열이 NULL이거나 길이가 0인 경우


###===Variable Initialization===###
mkdir ${workdir}/step01 ${workdir}/step02 ${workdir}/step03 ${workdir}/step04 ${workdir}/step05 ${workdir}/acpc
tpldir='/data/standard/'
std_voi_dir="/data/std_VOI"
cal_mean_roi_dir='/data'
aalpath='/data/aal_atlas'
make_json_dir='/data'
acpc_dir='/data'


#템플릿 경로 : Fsl경로/data/standard/ ====== 도커 이미지 만들떄는 수정 해야함
#T1dir="${workdir}/T1"
#PETdir="${workdir}/PET"


start_flag=`echo $start_step | sed 's/[^1-7]//g'`    #start step을 Step02로 했으면 start_flag는 2
end_flag=`echo $end_step | sed 's/[^1-7]//g'`



#PET
#if [ -r ${workdir}${sub}_pet.nii* ]; then
#	pet_e='${sub}_pet.nii' ; pet=$(/data/remove_ext ${pet_e})
#elif [ -r ${wordir}${sub}_PET.nii* ]; then
	pet_e=${sub}'_PET.nii' ; pet=$(/data/remove_ext ${pet_e})
#else
#	echo""
#	echo "No PET file (or directory) or wrong file name (you have to change file name [subject name]_PET(pet).nii) ..."
#	echo""
#	help
	
#	exit 1
	
#fi 


# T1, ACPC align (optional)

if [ $acpc_flag = "yes" ]; then
	# find the T1
	if [ -r ${sub}_T1.nii* ]; then 
		t1_e_tmp=`ls ${sub}_T1.nii*` ; t1_tmp=$(remove_ext ${t1_e_tmp})   #remove_ext확장자 제거
	elif [ -r ${sub}_t1.nii* ]; then
		t1_e_tmp=`ls ${sub}_t1.nii*` ; t1_tmp=$(remove_ext ${t1_e_tmp})
	else
		echo""
		echo "No T1 file(or directory) or wrong file name (you have to change file name [subject name]_T1(or t1).nii)..."
		echo""
		help
		exit 1
	fi 
	
	# acpc alignment
	sh ${acpc_dir}/align_ACPC.sh ${t1_tmp}
	#========== 도커 이미지 만들떄는 수정 해야함
	
	t1_e=${t1_e_tmp/1./1_ACPC.}
	t1=$(remove_ext ${t1_e})	

elif [ $acpc_flag = "no"  ] ; then
	# find the T1
#	if [ -r ${workdir }/${sub}_T1.nii* ]; then 
		t1_e=${sub}'_T1.nii' ; t1=$(/data/remove_ext ${t1_e})
#	elif [ -r ${sorkdir}/${sub}_t1.nii* ]; then
#		t1_e='${sub}_t1.nii' ; t1=$(/data/remove_ext ${t1_e})
#	else
#		echo "No T1 file or directory..."
#		exit 1
#	fi	

#else
#	echo "Unknown option argument : --acpc_align"; help
#	exit 1
fi	

###===Notice the parced input information===###
echo ""
echo "PARCED INPUT ARGS:: "
echo ""
echo "++= Subject number : "$sub
echo "++= Registration tool will be used : "$rflag
if [ $rflag = "ants" -a $q_flag = "yes" ];then
	echo "++= Ants Syn Registration will be performed with more simplified version :: antsRegistrationSyNQuick.sh"
fi
echo "++= Processing will be performed from "$start_step
echo "++= Processing will be performed to "$end_step
echo ""
echo ""
echo "++= PET volume was successfully found : "$pet_e
echo "++= T1 volume was also identified :  "$t1_e
echo "++= Working directory is :  "$workdir



###===Actual Processing===###
###===Step01 ~ Step012===###
## T1 bias field estimation & correction ---------------------------------------------
echo ''
echo '< Step01 >    T1 bias field estimation & correction  . . .'
echo ''
## -----------------------------------------------------------------------------------	

if [ $start_flag -le 1 -a $end_flag -ge 1 ]; then #<=,-le 더 작거나 같음 ,, >=,-ge 더 크거나 같음
	N4BiasFieldCorrection -d 3 -i ${workdir}/${t1}.nii* -o [${workdir}/step01/${t1}_N4corr.nii.gz,${workdir}/step01/${t1}_N4bias.nii.gz] -c [100x80x60x30,1e-8] -s 2 -b 200
	#mv ${workdir}/${sub}_T1_* ${workdir}/acpc/ -b
	
	echo '------------- Step01 --> Done --------------'

fi
## T1 <=> MNI template registration ---------------------------------------------------
echo ''
echo '< Step02 >    T1 <=> MNI template registration . . .'
echo ''
## ----------------------------------------------------------------------------------- 	



if [ $start_flag -le 2 -a $end_flag -ge 2 ]; then 

	if [ $rflag = "FSL" ]; then
		
		## Affine
		flirt -in ${workdir}/step01/${t1}_N4corr.nii.gz -ref ${tpldir}/avg152T1.nii* -out ${workdir}/step02/MR2mni_${t1} -omat ${workdir}/step02/MR2mni_${t1}.mat -dof 12 -cost mutualinfo
		#@snapshot_volreg ${workdir}/step02/MR2mni_${t1}.nii.gz ${tpldir}/avg152T1_brain.nii.gz step02_T1_affine.jpg
		echo "finished T1 <==> MNI template linear registration"

	elif [ $rflag = "ants" ]; then
	
		if [ $q_flag = "yes" ];then
			antsRegistrationSyNQuick.sh -d 3 -f ${tpldir}/avg152T1.nii.gz -m ${workdir}/step01/${t1}_N4corr.nii.gz  -o ${workdir}/step02/MR2mni_${t1}_ -t a -n 1 
		elif [ $q_flag = "no" ];then
			antsRegistrationSyN.sh -d 3 -f ${tpldir}/avg152T1.nii.gz -m ${workdir}/step01/${t1}_N4corr.nii.gz  -o ${workdir}/step02/MR2mni_${t1}_ -t a -n 1 
		else 
			echo "Unexpected arguments : --Quick = "$q_flag ; exit 0
		fi
		#@snapshot_volreg ${dwi}_eddy_b02t1_Warped.nii.gz ${t1}_inv_betted.nii.gz step06_1_b0_on_t1inv_nl.jpg

		echo "finished T1 <==> MNI template linear registration"
	else
		echo "Unexpected arguments : --regi_mode = "$rflag ; exit 0 

	fi

	echo ""
	echo '------------- Step02 --> Done --------------'

fi
## PET <=> T1 registration ------------------------------------------------------------
echo ''
echo '< Step03 >    PET <=> T1 registration . . .'
echo ''
## -----------------------------------------------------------------------------------	

if [ $start_flag -le 3 -a $end_flag -ge 3 ]; then 
	echo ""
	echo "start PET <==> T1 linear registration"
	echo ""
	if [ $rflag = "FSL" ]; then
		## Affine
		flirt -in ${workdir}/${pet}.nii* -ref ${workdir}/step02/MR2mni_${t1}.nii* -out ${workdir}/step03/PET2MR_${pet} -omat ${workdir}/step02/MR2mni_${t1}.mat -dof 12 -cost mutualinfo
		#@snapshot_volreg ${workdir}/step02/MR2mni_${t1}.nii.gz ${tpldir}/avg152T1_brain.nii.gz step02_T1_affine.jpg
		echo "finished PET <==> T1linear registration"
		echo ""

	elif [ $rflag = "ants" ]; then
	
		if [ $q_flag = "yes" ];then
			antsRegistrationSyNQuick.sh -d 3 -f ${workdir}/step02/MR2mni_${t1}_Warped.nii* -m ${workdir}/${pet}.nii* -o ${workdir}/step03/PET2MR_${pet}_ -t a -n 1 
		elif [ $q_flag = "no" ];then
			antsRegistrationSyN.sh -d 3 -f ${workdir}/step02/MR2mni_${t1}_Warped.nii* -m ${workdir}/${pet}.nii* -o ${workdir}/step03/PET2MR_${pet}_ -t a -n 1
		else 
			echo "Unexpected arguments : --Quick = "$q_flag ; exit 0
		fi
	
		#@snapshot_volreg ${dwi}_eddy_b02t1_Warped.nii.gz ${t1}_inv_betted.nii.gz step06_1_b0_on_t1inv_nl.jpg
		echo "finished PET <==> T1 linear registration"
		echo ""
	else
			echo "Unexpected arguments : --regi_mode = "$rflag ; exit 0 

	fi
	echo''
	echo '------------- Step03 --> Done --------------'

fi


## Nonlinear registration -------------------------------------------------------------
echo ''
echo '< Step04 >    PET <=> MNI Nonlinear registration  . . .'
echo ''
## -----------------------------------------------------------------------------------

if [ $start_flag -le 4 -a $end_flag -ge 4 ]; then 
	if [ $rflag = "FSL" ]; then
		## Non-linear registration
		fnirt --ref=${tpldir}/avg152T1.nii.gz --in=${workdir}/step02/MR2mni_${t1}.nii.gz --cout=${workdir}/step04/${t1}_warp
		applywarp -i ${workdir}/step02/MR2mni_${t1}.nii* -r ${tpldir}/avg152T1.nii* -o ${workdir}/step04/NLR_${t1} --warp=${workdir}/step04/${t1}_warp
		applywarp -i ${workdir}/step03/PET2MR_${pet}.nii* -r ${workdir}/step04/NLR_${t1}.nii* -o ${workdir}/step04/NLR_${pet} --warp=${workdir}/step04/${t1}_warp
		#@snapshot_volreg ${workdir}/step02/MR2mni_${t1}.nii.gz ${tpldir}/avg152T1_brain.nii.gz step02_T1_affine.jpg
		echo "finished T1 <==> MNI template Non-linear registration"
	elif [ $rflag = "ants" ]; then
	
		if [ $q_flag = "yes" ];then
			antsRegistrationSyNQuick.sh -d 3 -f ${tpldir}/avg152T1.nii.gz -m ${workdir}/step02/MR2mni_${t1}_Warped.nii* -o ${workdir}/step04/NLR_${t1}_ -t so -n 1 
			WarpImageMultiTransform 3 ${workdir}/step03/PET2MR_${pet}_Warped.nii.gz ${workdir}/step04/NLR_${pet}.nii.gz -R ${workdir}/step04/NLR_${t1}_Warped.nii.gz ${workdir}/step04/NLR_${t1}_1Warp.nii.gz 
		elif [ $q_flag = "no" ];then
			antsRegistrationSyN.sh -d 3 -f ${tpldir}/avg152T1.nii.gz -m ${workdir}/step02/MR2mni_${t1}_Warped.nii* -o ${workdir}/step04/NLR_${t1}_ -t so -n 1 
			WarpImageMultiTransform 3 ${workdir}/step03/PET2MR_${pet}_Warped.nii.gz ${workdir}/step04/NLR_${pet}.nii.gz -R ${workdir}/step04/NLR_${t1}_Warped.nii.gz ${workdir}/step04/NLR_${t1}_1Warp.nii.gz 
		else 
			echo "Unexpected arguments : --Quick = "$q_flag ; exit 0
		fi
	
		#@snapshot_volreg ${dwi}_eddy_b02t1_Warped.nii.gz ${t1}_inv_betted.nii.gz step06_1_b0_on_t1inv_nl.jpg
		echo "finished Non-linear registration"

	else		
			echo "Unexpected arguments : --regi_mode = "$rflag ; exit 0 

	fi
	echo ''
	echo '------------- Step04 --> Done --------------'
fi

## Extract PET-SUVr values & re-calc individual CTX SUVr values ----------------------
echo ''
echo '< Step05 >    Extract PET-SUVr values from normalized PET images using standard VOIs(CG, Pons, WC, WC+B)'
echo '              and Re-calculate individual CTX SUVr values for each reference VOI of interest . . .'
echo ''
## -----------------------------------------------------------------------------------

#도커 빌드 시 standard voi 마스크 있는 경로 입력 수정 필수


if [ $start_flag -le 5 -a $end_flag -ge 5 ]; then 


	if [ $svoi = "cg" ]; then

	python3 ${cal_mean_roi_dir}/cal_mean_roi.py ${workdir}/step04/NLR_${sub}_PET.nii.gz ${workdir} /data/std_VOI/voi_CerebGry_2mm.nii ${sub}

	elif [ $svoi = "pons" ]; then
	
	python3 ${cal_mean_roi_dir}/cal_mean_roi.py ${workdir}/step04/NLR_${sub}_PET.nii.gz ${workdir} /data/std_VOI/voi_CerebGry_2mm.nii ${sub}

	elif [ $svoi = "wc" ]; then
	
	python3 ${cal_mean_roi_dir}/cal_mean_roi.py ${workdir}/step04/NLR_${sub}_PET.nii.gz ${workdir} /data/std_VOI/voi_CerebGry_2mm.nii ${sub}
        

	elif [ $svoi = "wcb" ]; then
	
	python3 ${cal_mean_roi_dir}/cal_mean_roi.py ${workdir}/step04/NLR_${sub}_PET.nii.gz ${workdir} /data/std_VOI/voi_CerebGry_2mm.nii ${sub}
     

	else
                echo "Unexpected arguments : --std_voi = "$svoi ; exit 0
	fi

	echo ''
	echo '------------- Step05 --> Done --------------'


fi



finish=`date +%s.%N`
diff=$( echo "$finish - $start" | bc -l )

echo 'start:' $start
echo 'finish:' $finish
echo 'diff:' $diff

