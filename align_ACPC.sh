#!/bin/bash


ref_mni=/usr/local/fsl/data/standard/MNI152_T1_1mm.nii.gz
/data/ACPCAlignment.sh --workingdir=$1_acpc --in=$1 --ref=$ref_mni --out=$1_ACPC --omat=$1_ACPC.mat
