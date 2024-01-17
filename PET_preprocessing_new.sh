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
	echo ""   # $# : 인수의 개수
	echo ""   # -eq : 값이 같음	



	
}
start=`date +%s.%N`
if [ $# -eq 0 ]; then help ; exit 1 ; fi




#matlab -r MR2mni
#matlab -r PET2MR
#matlab -r NLR
# matlab 영상 인자 받아서 실행, shell script로 만들어서 한번에 돌아가도록 코드 짜기

echo ''
echo ''
echo '--------------------------------------------------------------'
echo "###=== PET preprocessing pipeline. Code by KYJ ===###"
echo '--------------------------------------------------------------'
echo ''
echo ''
###===Input Argument Setting===###
optconfig="s:-:"  # 옵션인수를 가지는경우에 :추가, 안 가지면 :없이 옵션만 입력:
while getopts "$optconfig" opt ;do
    case $opt in
    	s) sub=$OPTARG;;
		-)
			case $OPTARG in
					workdir=*) wdir=${OPTARG#*=};;
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
if [ -z ${wdir} ]; then wdir=`pwd` ;fi
if [ -z ${rflag} ] ;then rflag="FSL" ;fi
if [ -z ${start_step} ] ;then start_step="Step01" ;fi
if [ -z ${end_step} ] ;then end_step="Step05" ;fi
if [ -z ${q_flag} ] ;then q_flag="yes" ;fi
if [ -z ${acpc_flag} ] ;then acpc_flag="no" ;fi
if [ -z ${svoi} ] ;then svoi="wc" ;fi

# -z 문자열이 NULL이거나 길이가 0인 경우


###===Variable Initialization===###


workdir=${wdir}
tpldir='/usr/local/fsl/data/standard/'
std_voi_dir="/nasdata4/kyj0305/code/PET_prep/Centiloid/std_VOI"
mkdir ${workdir}/step01 ${workdir}/step02 ${workdir}/step03 ${workdir}/step04 ${workdir}/step05 ${workdir}/acpc

#템플릿 경로 : Fsl경로/data/standard/ ====== 도커 이미지 만들떄는 수정 해야함
#T1dir="${workdir}/T1"
#PETdir="${workdir}/PET"


start_flag=`echo $start_step | sed 's/[^1-7]//g'`    #start step을 Step02로 했으면 start_flag는 2
end_flag=`echo $end_step | sed 's/[^1-7]//g'`



#PET
if [ -r ${workdir}/${sub}_pet.nii* ]; then
	pet_e=`ls ${workdir}/${sub}_pet.nii*` ; pet=$(remove_ext ${pet_e##*/})
elif [ -r ${workdir}/${sub}_PET.nii* ]; then
	pet_e=`ls ${workdir}/${sub}_PET.nii*` ; pet=$(remove_ext ${pet_e##*/})
else
	echo""
	echo "No PET file (or directory) or wrong file name (you have to change file name [subject name]_PET(pet).nii) ..."
	echo""
	help
	exit 1
fi 


# T1, ACPC align (optional)

if [ $acpc_flag = "yes" ]; then
	# find the T1
	if [ -r ${workdir}/${sub}_T1.nii* ]; then 
		t1_e_tmp=`ls ${workdir}/${sub}_T1.nii*` ; t1_tmp=$(remove_ext ${t1_e_tmp##*/})   #remove_ext확장자 제거
	elif [ -r ${workdir}/${sub}_t1.nii* ]; then
		t1_e_tmp=`ls ${workdir}/${sub}_t1.nii*` ; t1_tmp=$(remove_ext ${t1_e_tmp##*/})
	else
		echo""
		echo "No T1 file(or directory) or wrong file name (you have to change file name [subject name]_T1(or t1).nii)..."
		echo""
		help
		exit 1
	fi 
	echo $t1_tmp	
	# acpc alignment
	sh /nasdata4/kyj0305/spm_withMatlab_docker/align_ACPC.sh ${workdir}/${t1_tmp}
	applywarp --rel --interp=nn -i ${workdir}/${t1_tmp}_bet_mask.nii.gz -r ${tpldir}avg152T1_brain.nii.gz --premat=${workdir}/${t1_tmp}_ACPC.mat -o ${workdir}/${t1_tmp}_brain_mask_ACPC.nii.gz
	#========== 도커 이미지 만들떄는 수정 해야함
	
	t1_e=${t1_e_tmp/1./1_ACPC.}
	t1=$(remove_ext ${t1_e##*/})
	echo ${t1}	

elif [ $acpc_flag = "no"  ] ; then
	# find the T1
	if [ -r ${workdir}/${sub}_T1.nii* ]; then 
		t1_e=`ls ${workdir}/${sub}_T1.nii*` ; t1=$(remove_ext ${t1_e##*/})
	elif [ -r ${workdir}/${sub}_t1.nii* ]; then
		t1_e=`ls ${workdir}/${sub}_t1.nii*` ; t1=$(remove_ext ${t1_e##*/})
	else
		echo "No T1 file or directory..."
		exit 1
	
	fi
	echo "T1 :" ${t1}	

else
	echo "Unknown option argument : --acpc_align"; help
	exit 1
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
###===Step01 ~ Step05===###
## T1 bias field estimation & correction ---------------------------------------------
echo ''
echo '< Step01 >    T1 bias field estimation & correction  . . .'
echo ''
## -----------------------------------------------------------------------------------	

if [ $start_flag -le 1 -a $end_flag -ge 1 ]; then #<=,-le 더 작거나 같음 ,, >=,-ge 더 크거나 같음
	N4BiasFieldCorrection -d 3 -i ${workdir}/${t1}.nii* -o [${workdir}/step01/${t1}_N4corr.nii.gz,${workdir}/step01/${t1}_N4bias.nii.gz] -c [100x80x60x30,1e-8] -s 2 -b 200
	mv ${workdir}/${sub}_T1_* ${workdir}/acpc/ -b
fi
echo '------------- Step01 --> Done --------------'

## T1 <=> MNI template registration ---------------------------------------------------
echo ''
echo '< Step02 >    T1 <=> MNI template registration . . .'
echo ''
## ----------------------------------------------------------------------------------- 	

#템플릿 경로 : Fsl경로/data/standard/


if [ $start_flag -le 2 -a $end_flag -ge 2 ]; then 

	if [ $rflag = "FSL" ]; then
	
	if [ $acpc_flag = "yes"  ] ; then
		
		## Affine
		flirt -in ${workdir}/step01/${t1}_N4corr.nii.gz -ref ${tpldir}/avg152T1.nii.gz -out ${workdir}/step02/MR2mni_${t1} -omat ${workdir}/step02/MR2mni_${t1}.mat -dof 12 -cost mutualinfo
		flirt -in ${workdir}/acpc/${sub}_T1_brain_mask_ACPC.nii.gz -interp nearestneighbour  -ref ${tpldir}/MNI152_T1_2mm_brain_mask.nii.gz -applyxfm -init ${workdir}/step02/MR2mni_${t1}.mat -out ${workdir}/step02/MR2mni_${t1}_brain_mask
		#@snapshot_volreg ${workdir}/step02/MR2mni_${t1}.nii.gz ${tpldir}/MNI152_T1_2mm_brain.nii.gz step02_T1_affine.jpg
		echo "finished T1 <==> MNI template linear registration"

	
	elif [ $acpc_flag = "no"  ] ; then
		## Affine
                echo "start test~!!!!"
		flirt -in ${workdir}/step01/${t1}_N4corr.nii.gz -ref ${tpldir}/avg152T1.nii.gz -out ${workdir}/step02/MR2mni_${t1} -omat ${workdir}/step02/MR2mni_${t1}.mat -dof 12 -cost mutualinfo
                flirt -in ${workdir}/acpc/${sub}_T1_bet_mask.nii.gz -interp nearestneighbour  -ref ${tpldir}/MNI152_T1_2mm_brain_mask.nii.gz -applyxfm -init ${workdir}/step02/MR2mni_${t1}.mat -out ${workdir}/step02/MR2mni_${t1}_brain_mask
                #@snapshot_volreg ${workdir}/step02/MR2mni_${t1}.nii.gz ${tpldir}/MNI152_T1_2mm_brain.nii.gz step02_T1_affine.jpg
                echo "finished T1 <==> MNI template linear registration"
	else
		echo "Unexpected arguments : --acpc_flag = "$acpc_flag ; exit 0 
	fi
	elif [ $rflag = "ants" ]; then
	
		if [ $q_flag = "yes" ];then
			antsRegistrationSyNQuick.sh -d 3 -f ${tpldir}/avg152T1.nii.gz -m ${workdir}/step01/${t1}_N4corr.nii.gz  -o ${workdir}/step02/MR2mni_${t1}_ -t a -n 1 
			antsRegistrationSyNQuick.sh -d 3 -f ${tpldir}/MNI152_T1_2mm_brain_mask.nii.gz -m ${workdir}/acpc/${sub}_T1_bet_mask.nii.gz  -o ${workdir}/step02/MR2mni_${t1}_brain_mask_ -t a -n 1 
			fslmaths ${workdir}/step02/MR2mni_${t1}_brain_mask_Warped.nii.gz -thr 0.5 -bin ${workdir}/step02/MR2mni_${t1}_brain_mask.nii.gz
		elif [ $q_flag = "no" ];then
			antsRegistrationSyN.sh -d 3 -f ${tpldir}/avg152T1.nii.gz -m ${workdir}/step01/${t1}_N4corr.nii.gz  -o ${workdir}/step02/MR2mni_${t1}_ -t a -n 1 
			antsRegistrationSyN.sh -d 3 -f ${tpldir}/MNI152_T1_2mm_brain_mask.nii.gz -m ${workdir}/acpc/${sub}_T1_bet_mask.nii.gz  -o ${workdir}/step02/MR2mni_${t1}_brain_mask_ -t a -n 1 
			fslmaths ${workdir}/step02/MR2mni_${t1}_brain_mask_Warped.nii.gz -thr 0.5 -bin ${workdir}/step02/MR2mni_${t1}_brain_mask.nii.gz
		else 
			echo "Unexpected arguments : --Quick = "$q_flag ; exit 0
		fi
		#@snapshot_volreg ${dwi}_eddy_b02t1_Warped.nii.gz ${t1}_inv_betted.nii.gz step06_1_b0_on_t1inv_nl.jpg

		echo "finished T1 <==> MNI template linear registration"
	else
		echo "Unexpected arguments : --regi_mode = "$rflag ; exit 0 

	fi

fi
echo ""
echo '------------- Step02 --> Done --------------'

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

fi
echo''
echo '------------- Step03 --> Done --------------'

## Nonlinear registration -------------------------------------------------------------
echo ''
echo '< Step04 >    PET <=> MNI Nonlinear registration  . . .'
echo ''
## -----------------------------------------------------------------------------------

if [ $start_flag -le 4 -a $end_flag -ge 4 ]; then

	if [ $rflag = "FSL" ]; then
		fslmaths ${workdir}/step02/MR2mni_${t1}.nii.gz -mul ${workdir}/step02/MR2mni_${t1}_brain_mask.nii.gz ${workdir}/step02/MR2mni_${t1}_brain.nii.gz
		fslmaths ${workdir}/step03/PET2MR_${pet}.nii* -mul ${workdir}/step02/MR2mni_${t1}_brain_mask.nii.gz ${workdir}/step03/PET2MR_${pet}_brain.nii.gz
		## Non-linear registration
		fnirt --ref=${tpldir}/avg152T1_brain.nii.gz --in=${workdir}/step02/MR2mni_${t1}_brain.nii.gz --cout=${workdir}/step04/${t1}_warp
		applywarp -i ${workdir}/step02/MR2mni_${t1}_brain.nii* -r ${tpldir}/avg152T1_brain.nii.gz -o ${workdir}/step04/NLR_${t1} --warp=${workdir}/step04/${t1}_warp
		applywarp -i ${workdir}/step03/PET2MR_${pet}_brain.nii* -r ${workdir}/step04/NLR_${t1}.nii* -o ${workdir}/step04/NLR_${pet} --warp=${workdir}/step04/${t1}_warp
		#@snapshot_volreg ${workdir}/step02/MR2mni_${t1}.nii.gz ${tpldir}/MNI152_T1_1mm_brain.nii.gz step02_T1_affine.jpg
		echo "finished T1 <==> MNI template Non-linear registration"

	elif [ $rflag = "ants" ]; then
		fslmaths ${workdir}/step02/MR2mni_${t1}_Warped.nii.gz -mul ${workdir}/step02/MR2mni_${t1}_brain_mask.nii.gz ${workdir}/step02/MR2mni_${t1}_brain.nii.gz
		fslmaths ${workdir}/step03/PET2MR_${pet}_Warped.nii* -mul ${workdir}/step02/MR2mni_${t1}_brain_mask.nii.gz ${workdir}/step03/PET2MR_${pet}_brain.nii.gz
		if [ $q_flag = "yes" ];then
			antsRegistrationSyNQuick.sh -d 3 -f ${tpldir}/avg152T1_brain.nii.gz -m ${workdir}/step02/MR2mni_${t1}_brain.nii* -o ${workdir}/step04/NLR_${t1}_ -t so -n 1 
			WarpImageMultiTransform 3 ${workdir}/step03/PET2MR_${pet}_brain.nii.gz ${workdir}/step04/NLR_${pet}.nii.gz -R ${workdir}/step04/NLR_${t1}_Warped.nii.gz ${workdir}/step04/NLR_${t1}_1Warp.nii.gz 
		elif [ $q_flag = "no" ];then
			antsRegistrationSyN.sh -d 3 -f ${tpldir}/avg152T1_brain.nii.gz -m ${workdir}/step02/MR2mni_${t1}_brain.nii* -o ${workdir}/step04/NLR_${t1}_ -t so -n 1 
			WarpImageMultiTransform 3 ${workdir}/step03/PET2MR_${pet}_brain.nii.gz ${workdir}/step04/NLR_${pet}.nii.gz -R ${workdir}/step04/NLR_${t1}_Warped.nii.gz ${workdir}/step04/NLR_${t1}_1Warp.nii.gz 
		else 
			echo "Unexpected arguments : --Quick = "$q_flag ; exit 0
		fi
	
		#@snapshot_volreg ${dwi}_eddy_b02t1_Warped.nii.gz ${t1}_inv_betted.nii.gz step06_1_b0_on_t1inv_nl.jpg
		echo "finished Non-linear registration"

	else
			echo "Unexpected arguments : --regi_mode = "$rflag ; exit 0 

	fi

fi

echo ''
echo '------------- Step04 --> Done --------------'

## Extract PET-SUVr values & re-calc individual CTX SUVr values ----------------------
echo ''
echo '< Step05 >    Extract PET-SUVr values from normalized PET images using standard VOIs(CG, Pons, WC, WC+B)'
echo '              and Re-calculate individual CTX SUVr values for each reference VOI of interest . . .'
echo ''
## -----------------------------------------------------------------------------------

#도커 빌드 시 standard voi 마스크 있는 경로 입력 수정 필수


if [ $start_flag -le 5 -a $end_flag -ge 5 ]; then 

	if [ $svoi = "cg" ]; then
		
		sv=`fslstats ${workdir}/step04/NLR_${pet}.nii.gz -k ${std_voi_dir}/voi_CerebGry_2mm.nii -m`
		fslmaths ${workdir}/step04/NLR_${pet}.nii.gz -div $sv ${workdir}/step05/CG_${sub}
		fslstats ${workdir}/step05/CG_${sub}.nii.gz -k ${std_voi_dir}/voi_ctx_2mm.nii  -m > ${workdir}/step05/CTX_SUVr_${sub}_CG	

	elif [ $svoi = "pons" ]; then	

		sv=`fslstats ${workdir}/step04/NLR_${pet}.nii.gz -k ${std_voi_dir}/voi_Pons_2mm.nii -m`
		fslmaths ${workdir}/step04/NLR_${pet}.nii.gz -div $sv ${workdir}/step05/Pons_${sub}
		fslstats ${workdir}/step05/Pons_${sub}.nii.gz -k ${std_voi_dir}/voi_ctx_2mm.nii  -m > ${workdir}/step05/CTX_SUVr_${sub}_Pons	

	elif [ $svoi = "wc" ]; then	

		sv=`fslstats ${workdir}/step04/NLR_${pet}.nii.gz -k ${std_voi_dir}/voi_WhlCbl_2mm.nii -m`
		fslmaths ${workdir}/step04/NLR_${pet}.nii.gz -div $sv ${workdir}/step05/WC_${sub}
		fslstats ${workdir}/step05/WC_${sub}.nii.gz -k ${std_voi_dir}/voi_ctx_2mm.nii  -m > ${workdir}/step05/CTX_SUVr_${sub}_WC	

	elif [ $svoi = "wcb" ]; then	

		sv=`fslstats ${workdir}/step04/NLR_${pet}.nii.gz -k ${std_voi_dir}/voi_WhlCblBrnStm_2mm.nii -m`
		fslmaths ${workdir}/step04/NLR_${pet}.nii.gz -div $sv ${workdir}/step05/WCB_${sub}
		fslstats ${workdir}/step05/WCB_${sub}.nii.gz -k ${std_voi_dir}/voi_ctx_2mm.nii -m > ${workdir}/step05/CTX_SUVr_${sub}_WCB	

	else 
		echo "Unexpected arguments : --std_voi = "$svoi ; exit 0
	fi

fi

echo ''
echo '------------- Step05 --> Done --------------'




finish=`date +%s.%N`
diff=$( echo "$finish - $start" | bc -l )

echo 'start:' $start
echo 'finish:' $finish
echo 'diff:' $diff




