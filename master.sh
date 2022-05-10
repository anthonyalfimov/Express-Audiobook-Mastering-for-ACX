#!/usr/bin/env bash

## Audio file level statistics functions

# Arg(1): path to audio file to measure
function getStats {
    local file="$1"

    sox "$file" -n stats 2>&1 | grep "lev dB"
}

# Arg(1): output of the `getStats` function
function getPeak {
    local stats="$1"

    printf '%s\n' "$stats" | grep Pk | tr -s ' ' | cut -d ' ' -f 4
}

# Arg(1): output of the `getStats` function
function getRMS {
    local stats="$1"

    printf '%s\n' "$stats" | grep RMS | tr -s ' ' | cut -d ' ' -f 4
}

## File name formatting function

# Arg(1): name to modify
function updateOutputName {
    local name=$(echo "$1" | tr -d ",'")        # remove punctuation
    name=$(echo "$name" | iconv -f utf-8 -t ascii//TRANSLIT//IGNORE)    # remove diacritics
    name=$(echo "$name" | tr -s ' \-_' '_')     # use '_' as the delimiter character

    echo "$name"
}

### Set global project parameters
## Compression Paremeters
fx_comp_thres="-14.0"
fx_comp_knee="2.0"

## File padding
# ACX: Each file must have no more than 5 seconds of room tone at its beginning and end.
# Other services: 0.5 - 1 second of room tone at the beginning, 1 - 5 seconds of room tone at the end.
fx_fade_length="0.1"
fx_pad_in="0.75"
fx_pad_out="2.5"

for project_path in ./input/*
do
    # Proceed only with subdirectories of `./input/`
    [[ -d "$project_path" ]] || continue

    ### Set Project file properties
    project_name=$(basename "$project_path")
    project_name=$(echo "$project_name" | tr -s ' \-_' '_')

    output_path="./output/$project_name"
    mkdir -p "$output_path"

    tmp_path="./tmp/$project_name"
    mkdir -p "$tmp_path"

    log_path="$output_path/Log_${project_name}.txt"

    # Log header
    echo "Project: $project_name" > "$log_path"
    echo "" >> "$log_path"

    # Report to consolse
    echo "Project $project_name"
    echo "Processing project files..."
    echo ""

    # Add Log header for RMS and Peak readings per file
    echo "### RMS and Peak levels" >> "$log_path"

    ### Process project files
    for input_file in "$project_path"/*.wav "$project_path"/**/*.wav
    do
        [ -e "$input_file" ] || continue

        # Set input file properties
        input_name=$(basename -s ".wav" "$input_file")
        output_name="$input_name"
        input_name=${input_name// /_}

        input_length=$(sox --i -D "$input_file")     # input file length in seconds (float)

        # Set temporary file prefix
        tmp_prefix="${tmp_path}/${input_name}"

        # Determine output subdirectory
        output_dir=$(dirname "$input_file")

        if [[ "$output_dir" == "$project_path" ]]
        then
            output_dir=''
            echo "Subdirectory: none"
        else
            output_dir=$(basename "$output_dir")
            output_dir="${output_dir// /_}/"
            echo "Subdirectory: $output_dir"
            mkdir -p "${output_path}/${output_dir}"
        fi

        # Generate output file name
        output_name=$(updateOutputName "$output_name" "$output_dir" "$project_name")

        output_file="${output_path}/${output_dir}${output_name}.wav"

        # Report to console
        echo "File: $input_file"
        printf "Duration: %.2f s\n" "$input_length"
        echo "Start processing..."

        # Log file metadata
        echo "File: ${output_dir}${output_name}" >> "$log_path"

        ## Pre-process the file
        # ACX: Each file must use 44.1kHz sampling rate
        # ACX: All files must be the same channel format. Mono files are strongly recommended.
        sox --temp "$tmp_path" "$input_file" -b 24 "${tmp_prefix}_pre.wav" \
            channels 1 \
            rate -v 44100

        ## Apply gentle compression
        # ACX: Each file must have peak values no higher than -3dB.
        # For safety, we aim for the peak levels below -4dB.
        sox --temp "$tmp_path" "${tmp_prefix}_pre.wav" "${tmp_prefix}_fx.wav" \
            norm -4.0 \
            compand 0.05,0.6 ${fx_comp_knee}:${fx_comp_thres},-4,-7

        ## Trim silence from beginning and end of the file
        sox --temp "$tmp_path" "${tmp_prefix}_fx.wav" "${tmp_prefix}_trimmed.wav" \
            pad 1.0 1.0 vad reverse vad reverse

        # Add appropriate padding with silence
        sox --temp "$tmp_path" "${tmp_prefix}_trimmed.wav" "${tmp_prefix}_mixed_0.wav" \
            fade ${fx_fade_length} 0 \
            pad ${fx_pad_in} ${fx_pad_out}

        # Report to console
        echo "> done."
        echo "Start loudness processing..."

        ## Measure and adjust loudness metrics
        # ACX: Each file must measure between -23dB and -18dB RMS.
        # For safety, we aim for the RMS levels between -22dB and -19dB.
        stats=$(getStats "${tmp_prefix}_mixed_0.wav")
        rms=$(getRMS "$stats")
        peak=$(getPeak "$stats")

        iteration=0

        while (( "$(echo "$rms < -22.0" | bc -l)" )) || (( "$(echo "$rms > -19.0" | bc -l)" ))
        do
            new_iteration=$(($iteration + 1))

            # Give up after 5 iterations
            if [ $new_iteration -gt 5 ]
            then
                touch "${output_path}/${output_dir}ERROR_${input_name}"
                break
            fi

            gain_correction=$(echo "-19.0 - $rms" | bc -l)

            if (( "$(echo "$rms < -22.0" | bc -l)" ))
            then
                # echo "Too quiet!"
                lim_threshold=$(echo "-4.0 - $gain_correction" | bc -l)
                sox --temp "$tmp_path" "${tmp_prefix}_mixed_${iteration}.wav" "${tmp_prefix}_mixed_${new_iteration}.wav" \
                    compand 0.0,0.6 8:${lim_threshold},0,${lim_threshold} ${gain_correction}
            else
                # echo "Too loud!"
                sox --temp "$tmp_path" "${tmp_prefix}_mixed_${iteration}.wav" "${tmp_prefix}_mixed_${new_iteration}.wav" \
                    gain ${gain_correction}
            fi

            rm "${tmp_prefix}_mixed_${iteration}.wav"
            iteration=$new_iteration

            stats=$(getStats "${tmp_prefix}_mixed_${iteration}.wav")
            rms=$(getRMS "$stats")
            peak=$(getPeak "$stats")
        done

        # Export the final file (mono)
        sox --temp "$tmp_path" "${tmp_prefix}_mixed_${iteration}.wav" "$output_file" channels 1

        # Report to console
        echo "> Loudness achieved after $iteration iteration(s)"

        # Log output level stats
        echo "Iterations: $iteration" >> "$log_path"
        echo "RMS:  $rms dB" >> "$log_path"
        echo "Peak: $peak dB" >> "$log_path"
        echo "" >> "$log_path"

        # Clean up temporary files
        echo "Cleaning up temporary files..."
        rm "${tmp_prefix}"*.wav
        echo "> done."
        echo ""
    done

    rm -rf "$tmp_path"

    echo "> Finished $project_name"
    echo ""
done
