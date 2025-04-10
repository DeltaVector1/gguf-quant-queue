#!/bin/bash
USER="NewEden"
quants=("Q6_K" "Q5_K_M" "Q4_K_M" "Q3_K_L")
. ./gguf_venv/bin/activate

# Update these to point to your binaries
LLAMA_CPP_BIN=""
LLAMA_CPP_DIR=""

# do you wanna up 
read -p "Do you want to upload models to HuggingFace? (y/n): " UPLOAD_MODELS

quant() {
  local MODEL_PATH="$1"
  local MODEL_NAME="$2"
  
  OUTPUT_DIRECTORY="./output/$MODEL_NAME"
  mkdir -p "$OUTPUT_DIRECTORY"
  
  if [ ! -f "${OUTPUT_DIRECTORY}/${MODEL_NAME}-Q8_0.gguf" ]; then
    python "${LLAMA_CPP_DIR}/convert_hf_to_gguf.py" --outtype q8_0 --outfile "${OUTPUT_DIRECTORY}/${MODEL_NAME}-Q8_0.gguf" "$MODEL_PATH"
  fi
  
  for quant in "${quants[@]}"; do
    if [ ! -f "${OUTPUT_DIRECTORY}/${MODEL_NAME}-${quant}.gguf" ]; then
      "${LLAMA_CPP_BIN}/llama-quantize" --allow-requantize "${OUTPUT_DIRECTORY}/${MODEL_NAME}-Q8_0.gguf" "${OUTPUT_DIRECTORY}/${MODEL_NAME}-${quant}.gguf" "${quant}" 4
    fi
  done
  
  find "${OUTPUT_DIRECTORY}" -type f -size +40G -print0 | while IFS= read -r -d $'\0' file; do
      filename=$(basename "${file%.*}")
      echo "splitting $filename"
     "${LLAMA_CPP_BIN}/llama-gguf-split" --split --split-max-size 30G "$file" "${OUTPUT_DIRECTORY}/${filename}" && rm "$file"
  done
  
  if [[ "$UPLOAD_MODELS" == "y" || "$UPLOAD_MODELS" == "Y" ]]; then
    echo "Uploading ${MODEL_NAME} to HuggingFace..."
    HF_HUB_ENABLE_HF_TRANSFER=1 huggingface-cli upload --private "${USER}/${MODEL_NAME}-gguf" "${OUTPUT_DIRECTORY}" || return 0
  else
    echo "Skipping upload for ${MODEL_NAME}"
  fi
}

while IFS= read -r line || [[ -n "$line" ]]; do
  # Check if line is a local path or a HF URL
  if [[ "$line" == /* || "$line" == ~/* || "$line" == ./* ]]; then
    # Local path
    if [ -d "$line" ]; then
      MODEL_PATH="$line"
      MODEL_NAME=$(basename "$line")
      echo "Processing local model: $MODEL_NAME"
      quant "$MODEL_PATH" "$MODEL_NAME"
    else
      echo "Local path not found: $line"
    fi
  else
    # HF 
    modified_line="${line#https://}"
    IFS="/" read -ra parts <<< "$modified_line"
    x="${parts[-2]}"
    y="${parts[-1]}"
    MODEL_NAME="${x}_${y}"
    MODEL_PATH="./downloads/${MODEL_NAME}"
    
    if [ ! -f "${MODEL_PATH}/config.json" ]; then
      echo "Downloading model from HuggingFace: ${x}/${y}"
      mkdir -p "$MODEL_PATH"
      HF_HUB_ENABLE_HF_TRANSFER=1 huggingface-cli download "${x}/${y}" --local-dir="$MODEL_PATH" --exclude "*global_step*" "*checkpoint*" "*.pth" "*.pt"
    fi
    
    quant "$MODEL_PATH" "$MODEL_NAME"
  fi
done < "queue.txt"
