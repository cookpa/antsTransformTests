#!/bin/bash

# Uncomment below if you need run-to-run reproducibility
# Might not produce identical results on different systems
# export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=1
# export ANTS_RANDOM_SEED=362321

# check we have antsRegistration on the PATH
if ! command -v antsRegistration > /dev/null; then
  echo "Error: antsRegistration not found on PATH"
  exit 1
fi

echo "ANTs executables found on PATH: $(command -v antsRegistration)"
echo "ANTs version: $(antsRegistration --version | head -n 1)"

mkdir -p reference_transforms

# function do_registration(fixed, moving, output_root)
do_intersubject_registration() {
  fixed=$1
  moving=$2
  fixed_mask=$3
  moving_mask=$4
  output_root=$5

  antsRegistration -d 3 -r [ "$fixed", "$moving", 1 ] \
    -x [ "$fixed_mask", "$moving_mask"] \
    -t Rigid[0.1] -m Mattes[ "$fixed", "$moving", 1, 32 ] -c [ 100x100x0, 1e-6, 10 ] -s 2x1x0vox -f 4x3x1 \
    -t Affine[0.1] -m Mattes[ "$fixed", "$moving", 1, 32 ] -c [ 500x500x50, 1e-6, 10 ] -s 2x1x1vox -f 4x2x1 \
    -t SyN[0.2,3,0.5] -m CC[ "$fixed", "$moving", 1, 2 ] -c [ 100x50x50x20, 1e-6, 10 ] -s 3x2x1x0vox -f 4x3x2x1 \
    --write-composite-transform 1 \
    -o $output_root \
    --verbose \
    && ants_success=1 || ants_success=0



  return $ants_success
}

t1w="reference_images/t1w.nii.gz"
t1w_mask="reference_images/t1w_mask.nii.gz"

adni="reference_images/adni.nii.gz"
adni_mask="reference_images/adni_mask.nii.gz"

mni="reference_images/mni.nii.gz"
mni_mask="reference_images/mni_mask.nii.gz"

# register T1w to ADNI
do_intersubject_registration "$adni" "$t1w" "$adni_mask" "$t1w_mask" reference_transforms/t1w_to_adni_
# register MNI to ADNI, so we get to combine forward and inverse transforms
do_intersubject_registration "$adni" "$mni" "$adni_mask" "$mni_mask" reference_transforms/mni_to_adni_
