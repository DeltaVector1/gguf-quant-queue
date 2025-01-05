#!/bin/bash

USER=""
quants=("Q6_K" "Q5_K_M" "Q4_K_M" "Q3_K_L")

quant() {
  OUTPUT_DIRECTORY="./output/$1"
  mkdir -p "$OUTPUT_DIRECTORY"

  if [ ! -f "${OUTPUT_DIRECTORY}/${1}-Q8_0.gguf" ]; then
    python convert_hf_to_gguf.py --outtype q8_0 --outfile "${OUTPUT_DIRECTORY}/${1}-Q8_0.gguf" "./downloads/${1}"
  fi

  for quant in "${quants[@]}"; do
    if [ ! -f "${OUTPUT_DIRECTORY}/${1}-${quant}.gguf" ]; then
      ./llama-quantize --allow-requantize "${OUTPUT_DIRECTORY}/${1}-Q8_0.gguf" "${OUTPUT_DIRECTORY}/${1}-${quant}.gguf" "${quant}"
    fi
  done

  find "${OUTPUT_DIRECTORY}" -type f -size +40G -print0 | while IFS= read -r -d $'\0' file; do
      filename=$(basename "${file%.*}")
      echo "splitting $filename"
     ./llama-gguf-split --split --split-max-size 30G "$file" "${OUTPUT_DIRECTORY}/${filename}" && rm "$file"
  done

  HF_HUB_ENABLE_HF_TRANSFER=1 huggingface-cli upload --private "${USER}/${1}-gguf" "${OUTPUT_DIRECTORY}" || return 0
}

while IFS= read -r line || [[ -n "$line" ]]; do
  modified_line="${line#https://}"
  IFS="/" read -ra parts <<< "$modified_line"
  x="${parts[-2]}"
  y="${parts[-1]}"

  if [ ! -f "./downloads/${x}_${y}/config.json" ]; then
    HF_HUB_ENABLE_HF_TRANSFER=1 huggingface-cli download "${x}/${y}" --local-dir="./downloads/${x}_${y}" --exclude "*global_step*" "*checkpoint*" "*.pth" "*.pt"
  fi

  quant "${x}_${y}"
done < "queue.txt"
