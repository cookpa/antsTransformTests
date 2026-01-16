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

output_dir=test_transform_imagetype

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

# Check reference transform exists - we will only need one for this test
for transform in t1w_to_adni_Composite.h5 ; do
  if [ ! -f reference_transforms/$transform ]; then
    echo "Error: reference_transforms/$transform not found. Run registration.sh to generate them"
    exit 1
  fi
done

# Apply composite transform and check that it is consistent with the output from antsRegistration

antsApplyTransforms -d 3 --verbose --float \
    -o ${output_dir}/t1w_adni_aat.nii.gz \
    -r reference_images/adni.nii.gz \
    -t reference_transforms/t1w_to_adni_Composite.h5 \
    -i reference_images/t1w.nii.gz

assert_images_same reference_transforms/t1w_to_adni_deformed.nii.gz ${output_dir}/t1w_adni_aat.nii.gz 1e-6

# time series warp

# combine the inputs into a time series
ImageMath 4 ${output_dir}/t1w_adni_timeseries.nii.gz TimeSeriesAssemble \
    2 0 \
    reference_images/t1w.nii.gz \
    reference_images/t1w.nii.gz \
    reference_images/t1w.nii.gz \
    reference_images/t1w.nii.gz \
    reference_images/t1w.nii.gz

antsApplyTransforms -d 3 --verbose --float \
    -o ${output_dir}/t1w_adni_timeseries_aat.nii.gz \
    -r reference_images/adni.nii.gz \
    -t reference_transforms/t1w_to_adni_Composite.h5 \
    -i ${output_dir}/t1w_adni_timeseries.nii.gz \
    -e 3 \
    -n Linear

spacing=$( PrintHeader ${output_dir}/t1w_adni_timeseries_aat.nii.gz 1 )

if [[ ! "$spacing" == "1.5x1.5x1.5x2" ]]; then
    echo "Error: spacing does not match expected time series spacing."
    exit 1
fi

# Disassemble the deformed time series
ImageMath 4 ${output_dir}/t1w_adni_ts_component_.nii.gz TimeSeriesDisassemble \
    ${output_dir}/t1w_adni_timeseries_aat.nii.gz

# Warp should be applied to each volume independently
for ((i=0; i<5; i++)) do
    assert_images_same reference_transforms/t1w_to_adni_deformed.nii.gz ${output_dir}/t1w_adni_ts_component_100${i}.nii.gz 1e-6
done

# end time series

# multi-channel tests

# Closest thing we can make is a vector image, however it should not be reoriented
ImageMath 3 ${output_dir}/t1w_multicomp.nii.gz ComponentToVector \
    reference_images/t1w.nii.gz \
    reference_images/t1w.nii.gz \
    reference_images/t1w.nii.gz

antsApplyTransforms -d 3 --verbose --float \
    -o ${output_dir}/t1w_adni_multicomp_aat.nii.gz \
    -r reference_images/adni.nii.gz \
    -t reference_transforms/t1w_to_adni_Composite.h5 \
    -i ${output_dir}/t1w_multicomp.nii.gz \
    -e 4 \
    -n Linear

shape=$( PrintHeader ${output_dir}/t1w_adni_multicomp_aat.nii.gz 2 )

if [[ ! "$shape" == "144x183x157" ]]; then
    echo "Error: output shape does not match expected shape."
    exit 1
fi

# extract each component and compare to the single-channel warp
for ((i=0; i<3; i++)); do
    ImageMath 3 ${output_dir}/t1w_adni_multicomp_component_${i}.nii.gz ExtractVectorComponent \
        ${output_dir}/t1w_adni_multicomp_aat.nii.gz $i

    assert_images_same reference_transforms/t1w_to_adni_deformed.nii.gz ${output_dir}/t1w_adni_multicomp_component_${i}.nii.gz 1e-6
done

echo "All tests passed"
exit 0