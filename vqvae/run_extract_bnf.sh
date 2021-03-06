#!/usr/bin/env bash

stage=0
stop_stage=3
gpu=0
bnf_name=csid # "id" or "csid" or "token"
model_dir=exp/vqvae_librispeech
output_txt=true

[ -f path.sh ] && . ./path.sh; 
. utils/parse_options.sh || exit 1;

if [ -f vqvae/path.sh ]; then
    echo "Change the environment with vqvae/path.sh"
    . vqvae/path.sh
fi
. parse_options.sh

if [ $# -ne 2 ]; then
  echo "Usage: $0 <data-dir> <bnf-data-dir>"
  echo "e.g.: $0 data/train exp/train_bnf"
  echo "Options: "
  echo "  --nj <nj>                                        # number of parallel jobs"
  echo "  --gpu <gpu>                                      # ID of GPU."
  echo "  --bnf-name <csid>                                # bottlecneck feature type:"
  echo "                                                   # 1. token: VQ token"
  echo "                                                   # 2. id: VQ token ID"
  echo "                                                   # 3. csid: combined VQ token ID"
  echo "  --model-dir <exp/vqvae_librispeech>              # vqvae model dir."
  echo "  --output-txt <true>                              # output txt or not. if not, output ark and scp files"
  exit 1;
fi

data_dir=$1
bnf_data_dir=$2

# you might not want to do this for interactive shells.
set -e

feature_config="$(find "${model_dir}" -name "config_feature*.json" -print0 | xargs -0 ls -t | head -n 1)"
model_config="$(find "${model_dir}" -name "config_vqvae*.json" -print0 | xargs -0 ls -t | head -n 1)"
model_file="$(find "${model_dir}" -name "model*.pt" -print0 | xargs -0 ls -t | head -n 1)"
stats_file="$(find "${model_dir}" -name "stats*.pt" -print0 | xargs -0 ls -t | head -n 1)"

echo "get feature config: $feature_config"
echo "get model config: $model_config"
echo "get model file: $model_file"
echo "get stats file: $stats_file"

if [ $stage -le 0 -a $stop_stage -ge 0 ]; then
    utils/copy_data_dir.sh $data_dir $bnf_data_dir/melspec
    utils/data/resample_data_dir.sh 16000 $bnf_data_dir/melspec
fi

# Feature preprocessing
if [ $stage -le 1 -a $stop_stage -ge 1 ]; then
    # Extract features
    python vqvae/feature_extraction.py -c $feature_config \
        -T $bnf_data_dir/melspec -F $bnf_data_dir/melspec/data \
        -K "mel"
    # Feature normalization
    utils/copy_data_dir.sh $bnf_data_dir/melspec $bnf_data_dir/melspec_cmvn
    python vqvae/feature_normalization.py -c $feature_config \
        -T $bnf_data_dir/melspec_cmvn -F $bnf_data_dir/melspec_cmvn/data \
        -S $stats_file \
        -K "mel"            
fi

# Extracing token feature
if [ $stage -le 2 -a $stop_stage -ge 2 ]; then
    python vqvae/inference_bnf.py \
        -c $model_config \
        -d $bnf_data_dir/melspec_cmvn \
        -o $bnf_data_dir \
        -K "mel-${bnf_name}" \
        -m $model_file -g $gpu \
        --output_txt $output_txt
fi

echo "Finish extracting VQVAE bottleneck features"
