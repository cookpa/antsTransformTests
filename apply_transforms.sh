#!/bin/bash -ex

# Function to check if two images are the same - fails otherwise
assert_images_same() {
    local ref=$1
    local test=$2
    local tol=$3

    # Run MeasureImageSimilarity and extract only the numeric output
    local mse=$(MeasureImageSimilarity -d 3 -m MeanSquares["$ref","$test"])

    # Ensure mse is numeric before comparing
    if [[ ! $mse =~ ^[0-9.e+-]+$ ]]; then
        echo "Error: Could not extract a valid similarity value."
        return 1
    fi

    # Compare using bc for arbitrary precision floating-point comparison
    if echo "$mse < $tol" | bc -l | grep -q 1; then
        return 0
    else
        echo "Images $ref and $test differ"
        return 1
    fi
}

output_dir=test_transforms

if [ ! -d ${output_dir} ]; then
    mkdir -p ${output_dir}
else
    echo "Output directory ${output_dir} already exists. Exiting."
    exit 1
fi

mkdir -p ${output_dir}

# check we have antsRegistration on the PATH
if ! command -v antsRegistration > /dev/null; then
  echo "Error: antsRegistration not found on PATH"
  exit 1
fi

echo "ANTs executables found on PATH: $(command -v antsRegistration)"
echo "ANTs version: $(antsRegistration --version | head -n 1)"

# Check reference transforms exist
for transform in mni_to_adni_Composite.h5 mni_to_adni_InverseComposite.h5 t1w_to_adni_Composite.h5 \
    t1w_to_adni_InverseComposite.h5; do
  if [ ! -f reference_transforms/$transform ]; then
    echo "Error: reference_transforms/$transform not found. Run registration.sh to generate them"
    exit 1
  fi
done

# Apply composite transforms, these will be our "ground truth" outputs

# output file naming: src_dest_transform.nii.gz
# eg mni_adni_ref.nii.gz is mni warped to adni using the ref transform reference_transforms/mni_to_adni_Composite.h5

antsApplyTransforms -d 3 --verbose --float \
    -o ${output_dir}/mni_adni_ref.nii.gz \
    -r reference_images/adni.nii.gz \
    -t reference_transforms/mni_to_adni_Composite.h5 \
    -i reference_images/mni.nii.gz

antsApplyTransforms -d 3 --verbose --float \
    -o ${output_dir}/adni_mni_ref.nii.gz \
    -r reference_images/mni.nii.gz \
    -t reference_transforms/mni_to_adni_InverseComposite.h5 \
    -i reference_images/adni.nii.gz

antsApplyTransforms -d 3 --verbose --float \
    -o ${output_dir}/t1w_adni_ref.nii.gz \
    -r reference_images/adni.nii.gz \
    -t reference_transforms/t1w_to_adni_Composite.h5 \
    -i reference_images/t1w.nii.gz

antsApplyTransforms -d 3 --verbose --float \
    -o ${output_dir}/adni_t1w_ref.nii.gz \
    -r reference_images/t1w.nii.gz \
    -t reference_transforms/t1w_to_adni_InverseComposite.h5 \
    -i reference_images/adni.nii.gz

# Concatenated ref transforms: mni -> adni -> t1w
antsApplyTransforms -d 3 --verbose --float \
    -o ${output_dir}/mni_t1w_ref_ref.nii.gz \
    -r reference_images/t1w.nii.gz \
    -t reference_transforms/t1w_to_adni_InverseComposite.h5 \
    -t reference_transforms/mni_to_adni_Composite.h5 \
    -i reference_images/mni.nii.gz

# Concatenated ref transforms: t1w -> adni -> mni
antsApplyTransforms -d 3 --verbose --float \
    -o ${output_dir}/t1w_mni_ref_ref.nii.gz \
    -r reference_images/mni.nii.gz \
    -t reference_transforms/mni_to_adni_InverseComposite.h5 \
    -t reference_transforms/t1w_to_adni_Composite.h5 \
    -i reference_images/t1w.nii.gz


# Now disassemble the composite transforms and apply them

# The transform numbers may be confusing
# When we disassemble Composite we get 00AffineTransform, 01DisplacementFieldTransform (forward warps)
# When we disassemble InverseComposite we get 00DisplacementFieldTransform, 01AffineTransform (inverse warps)
# Note inverse affines are already inverted, no need to do [affine.mat, 1] in calls to antsApplyTransforms

CompositeTransformUtil --disassemble \
    reference_transforms/mni_to_adni_Composite.h5 \
    ${output_dir}/mni_to_adni_disassembled \

CompositeTransformUtil --disassemble \
    reference_transforms/mni_to_adni_InverseComposite.h5 \
    ${output_dir}/adni_to_mni_disassembled \

CompositeTransformUtil --disassemble \
    reference_transforms/t1w_to_adni_Composite.h5 \
    ${output_dir}/t1w_to_adni_disassembled \

CompositeTransformUtil --disassemble \
    reference_transforms/t1w_to_adni_InverseComposite.h5 \
    ${output_dir}/adni_to_t1w_disassembled \

# Check disassembled transforms are the same as the original transforms
antsApplyTransforms -d 3 --verbose --float \
    -o ${output_dir}/mni_t1w_decomp_decomp.nii.gz \
    -r reference_images/t1w.nii.gz \
    -t ${output_dir}/adni_to_t1w_disassembled_01_AffineTransform.mat \
    -t ${output_dir}/adni_to_t1w_disassembled_00_DisplacementFieldTransform.nii.gz \
    -t ${output_dir}/mni_to_adni_disassembled_01_DisplacementFieldTransform.nii.gz \
    -t ${output_dir}/mni_to_adni_disassembled_00_AffineTransform.mat \
    -i reference_images/mni.nii.gz

assert_images_same ${output_dir}/mni_t1w_ref_ref.nii.gz ${output_dir}/mni_t1w_decomp_decomp.nii.gz 1e-6

antsApplyTransforms -d 3 --verbose --float \
    -o ${output_dir}/t1w_mni_decomp_decomp.nii.gz \
    -r reference_images/mni.nii.gz \
    -t ${output_dir}/adni_to_mni_disassembled_01_AffineTransform.mat \
    -t ${output_dir}/adni_to_mni_disassembled_00_DisplacementFieldTransform.nii.gz \
    -t ${output_dir}/t1w_to_adni_disassembled_01_DisplacementFieldTransform.nii.gz \
    -t ${output_dir}/t1w_to_adni_disassembled_00_AffineTransform.mat \
    -i reference_images/t1w.nii.gz

assert_images_same ${output_dir}/t1w_mni_ref_ref.nii.gz ${output_dir}/t1w_mni_decomp_decomp.nii.gz 1e-6

# Now recompose with CompositeTransformUtil
CompositeTransformUtil --assemble \
    ${output_dir}/t1w_to_adni_recomposed.h5 \
    ${output_dir}/t1w_to_adni_disassembled_00_AffineTransform.mat \
    ${output_dir}/t1w_to_adni_disassembled_01_DisplacementFieldTransform.nii.gz

antsApplyTransforms -d 3 --verbose --float \
    -o ${output_dir}/t1w_adni_recomp.nii.gz \
    -r reference_images/adni.nii.gz \
    -t ${output_dir}/t1w_to_adni_recomposed.h5 \
    -i reference_images/t1w.nii.gz

assert_images_same ${output_dir}/t1w_adni_ref.nii.gz ${output_dir}/t1w_adni_recomp.nii.gz 1e-6

# Same with InverseComposite - adni to mni
CompositeTransformUtil --assemble \
    ${output_dir}/adni_to_mni_recomposed.h5 \
    ${output_dir}/adni_to_mni_disassembled_00_DisplacementFieldTransform.nii.gz \
    ${output_dir}/adni_to_mni_disassembled_01_AffineTransform.mat

antsApplyTransforms -d 3 --verbose --float \
    -o ${output_dir}/adni_mni_recomp.nii.gz \
    -r reference_images/mni.nii.gz \
    -t ${output_dir}/adni_to_mni_recomposed.h5 \
    -i reference_images/adni.nii.gz

assert_images_same ${output_dir}/adni_mni_ref.nii.gz ${output_dir}/adni_mni_recomp.nii.gz 1e-6

# Compose everything into a single transform
CompositeTransformUtil --assemble \
    ${output_dir}/mni_to_t1w_fullcomposed.h5 \
    ${output_dir}/mni_to_adni_disassembled_00_AffineTransform.mat \
    ${output_dir}/mni_to_adni_disassembled_01_DisplacementFieldTransform.nii.gz \
    ${output_dir}/adni_to_t1w_disassembled_00_DisplacementFieldTransform.nii.gz \
    ${output_dir}/adni_to_t1w_disassembled_01_AffineTransform.mat

antsApplyTransforms -d 3 --verbose --float \
    -o ${output_dir}/mni_t1w_fullcomp.nii.gz \
    -r reference_images/t1w.nii.gz \
    -t ${output_dir}/mni_to_t1w_fullcomposed.h5 \
    -i reference_images/mni.nii.gz

assert_images_same ${output_dir}/mni_t1w_ref_ref.nii.gz ${output_dir}/mni_t1w_fullcomp.nii.gz 1e-6


# Recompose with antsApplyTransforms
antsApplyTransforms -d 3 --verbose --float \
    -o ${output_dir}/mni_adni_decomp.nii.gz \
    -r reference_images/adni.nii.gz \
    -t ${output_dir}/mni_to_adni_disassembled_01_DisplacementFieldTransform.nii.gz \
    -t ${output_dir}/mni_to_adni_disassembled_00_AffineTransform.mat \
    -i reference_images/mni.nii.gz

assert_images_same ${output_dir}/mni_adni_ref.nii.gz ${output_dir}/mni_adni_decomp.nii.gz 1e-6

antsApplyTransforms -d 3 --verbose --float \
    -o CompositeTransform[ ${output_dir}/mni_to_adni_recompaat.h5 ] \
    -t ${output_dir}/mni_to_adni_disassembled_01_DisplacementFieldTransform.nii.gz \
    -t ${output_dir}/mni_to_adni_disassembled_00_AffineTransform.mat \

antsApplyTransforms -d 3 --verbose --float \
    -o ${output_dir}/mni_adni_recompaat.nii.gz \
    -r reference_images/adni.nii.gz \
    -t ${output_dir}/mni_to_adni_recompaat.h5 \
    -i reference_images/mni.nii.gz

assert_images_same ${output_dir}/mni_adni_ref.nii.gz ${output_dir}/mni_adni_recompaat.nii.gz 1e-6

antsApplyTransforms -d 3 --verbose --float \
    -o CompositeTransform[ ${output_dir}/t1w_to_mni_recompaat.h5 ] \
    -t ${output_dir}/adni_to_mni_disassembled_01_AffineTransform.mat \
    -t ${output_dir}/adni_to_mni_disassembled_00_DisplacementFieldTransform.nii.gz \
    -t ${output_dir}/t1w_to_adni_disassembled_01_DisplacementFieldTransform.nii.gz \
    -t ${output_dir}/t1w_to_adni_disassembled_00_AffineTransform.mat

antsApplyTransforms -d 3 --verbose --float \
    -r reference_images/mni.nii.gz \
    -o ${output_dir}/t1w_mni_recompaat.nii.gz \
    -t ${output_dir}/t1w_to_mni_recompaat.h5 \
    -i reference_images/t1w.nii.gz

assert_images_same ${output_dir}/t1w_mni_ref_ref.nii.gz ${output_dir}/t1w_mni_recompaat.nii.gz 1e-6

# Mixed transforms - also test command line inversion of affine
antsApplyTransforms -d 3 --verbose --float \
    -o ${output_dir}/mni_t1w_ref_decompinv.nii.gz \
    -r reference_images/t1w.nii.gz \
    -t [ ${output_dir}/t1w_to_adni_disassembled_00_AffineTransform.mat, 1 ] \
    -t ${output_dir}/adni_to_t1w_disassembled_00_DisplacementFieldTransform.nii.gz \
    -t reference_transforms/mni_to_adni_Composite.h5 \
    -i reference_images/mni.nii.gz

assert_images_same ${output_dir}/mni_t1w_ref_ref.nii.gz ${output_dir}/mni_t1w_ref_decompinv.nii.gz 1e-6

# Collapse with antsApplyTransforms
antsApplyTransforms -d 3 --verbose --float \
    -o DisplacementField[ ${output_dir}/t1w_to_adni_collapsed.nii.gz ] \
    -r reference_images/adni.nii.gz \
    -t reference_transforms/t1w_to_adni_Composite.h5

antsApplyTransforms -d 3 --verbose --float \
    -o ${output_dir}/t1w_adni_collapsed.nii.gz \
    -r reference_images/adni.nii.gz \
    -t ${output_dir}/t1w_to_adni_collapsed.nii.gz \
    -i reference_images/t1w.nii.gz

assert_images_same ${output_dir}/t1w_adni_ref.nii.gz ${output_dir}/t1w_adni_collapsed.nii.gz 1e-6

# Collapse linear
antsApplyTransforms -d 3 --verbose --float \
    -o Linear[ ${output_dir}/t1w_to_mni_collapsed_linear.mat ] \
    -t ${output_dir}/adni_to_mni_disassembled_01_AffineTransform.mat \
    -t ${output_dir}/t1w_to_adni_disassembled_00_AffineTransform.mat

antsApplyTransforms -d 3 --verbose --float \
    -o ${output_dir}/t1w_mni_collapsed_linear.nii.gz \
    -r reference_images/mni.nii.gz \
    -t ${output_dir}/t1w_to_mni_collapsed_linear.mat \
    -i reference_images/t1w.nii.gz

antsApplyTransforms -d 3 --verbose --float \
    -o ${output_dir}/t1w_mni_linear_linear.nii.gz \
    -r reference_images/mni.nii.gz \
    -t ${output_dir}/adni_to_mni_disassembled_01_AffineTransform.mat \
    -t ${output_dir}/t1w_to_adni_disassembled_00_AffineTransform.mat \
    -i reference_images/t1w.nii.gz

assert_images_same ${output_dir}/t1w_mni_collapsed_linear.nii.gz ${output_dir}/t1w_mni_linear_linear.nii.gz 1e-6

# Collapse linear inverse
antsApplyTransforms -d 3 --verbose --float \
    -o Linear[ ${output_dir}/mni_to_t1w_collapsed_linear.mat, 1 ] \
    -t ${output_dir}/adni_to_mni_disassembled_01_AffineTransform.mat \
    -t ${output_dir}/t1w_to_adni_disassembled_00_AffineTransform.mat \


antsApplyTransforms -d 3 --verbose --float \
    -o ${output_dir}/mni_t1w_collapsed_linear.nii.gz \
    -r reference_images/t1w.nii.gz \
    -t ${output_dir}/mni_to_t1w_collapsed_linear.mat \
    -i reference_images/mni.nii.gz

antsApplyTransforms -d 3 --verbose --float \
    -o ${output_dir}/mni_t1w_linear_linear.nii.gz \
    -r reference_images/t1w.nii.gz \
    -t [ ${output_dir}/t1w_to_adni_disassembled_00_AffineTransform.mat, 1 ] \
    -t [ ${output_dir}/adni_to_mni_disassembled_01_AffineTransform.mat, 1 ] \
    -i reference_images/mni.nii.gz

assert_images_same ${output_dir}/mni_t1w_collapsed_linear.nii.gz ${output_dir}/mni_t1w_linear_linear.nii.gz 1e-6


# Compose linear
antsApplyTransforms -d 3 --verbose --float \
    -o CompositeTransform[ ${output_dir}/mni_to_t1w_composed_linear.h5 ] \
    -t ${output_dir}/adni_to_t1w_disassembled_01_AffineTransform.mat \
    -t [ ${output_dir}/adni_to_mni_disassembled_01_AffineTransform.mat, 1 ]

antsApplyTransforms -d 3 --verbose --float \
    -o ${output_dir}/mni_t1w_composed_linear.nii.gz \
    -r reference_images/t1w.nii.gz \
    -t ${output_dir}/mni_to_t1w_composed_linear.h5 \
    -i reference_images/mni.nii.gz

assert_images_same ${output_dir}/mni_t1w_composed_linear.nii.gz ${output_dir}/mni_t1w_collapsed_linear.nii.gz 1e-6


# MINC
antsApplyTransforms -d 3 --verbose --float \
    -o CompositeTransform[ ${output_dir}/mni_to_adni_minc.xfm ] \
    -t reference_transforms/mni_to_adni_Composite.h5

antsApplyTransforms -d 3 --verbose --float \
    -o ${output_dir}/mni_adni_minc.nii.gz \
    -r reference_images/adni.nii.gz \
    -t ${output_dir}/mni_to_adni_minc.xfm \
    -i reference_images/mni.nii.gz

assert_images_same ${output_dir}/mni_adni_ref.nii.gz ${output_dir}/mni_adni_minc.nii.gz 1e-6


echo "All tests passed"
exit 0