import nibabel as nib
import numpy as np
import os, sys

# Load PET image and ROI mask
pet_image_path = sys.argv[1]
out_path = sys.argv[2]
voi_mask_path = sys.argv[3]
sub = sys.argv[4]

pet_image = nib.load(pet_image_path)
voi_mask =  nib.load(voi_mask_path)

# Get the data arrays
pet_data = pet_image.get_fdata()
voi_data = voi_mask.get_fdata()

# Caculate SUVr 

reference = np.multiply(pet_data, voi_data)
reference_mean = np.mean(reference[reference>0])
suvr = np.divide(pet_data, reference_mean)

for i in range(1,117):
	roi_mask_path = f'/data/aal_atlas/aal2_{i}.nii'
	roi_mask = nib.load(roi_mask_path)
	roi_data = roi_mask.get_fdata()
	roi_data = np.where(roi_data > 0, 1, 0)
	# Apply ROI mask to PET data
	roi_pet_data = np.multiply(suvr, roi_data)

	# Calculate mean intensity within the ROI
	mean_intensity_roi = np.mean(roi_pet_data[roi_pet_data > 0])


	print(f"Mean intensity within {i} ROI: {mean_intensity_roi}")

	with open(f'{out_path}/{sub}.txt','a+') as f:
		f.write(str(i) + '\t' + str(mean_intensity_roi))
		f.write('\n')

