#! /bin/bash
set -e # stop and fail if anything stops
cd `dirname "$0"`

# Download the code from PyTorch's examples repository
[ -f code/main.py ] || wget -O code/main.py https://raw.githubusercontent.com/pytorch/examples/master/imagenet/main.py

# Download the data
ssm shell -p ex-imagenet -t download \
    --dir_files ./code -o ./output/download --no_spot \
    --cmd_line './download.sh $SSM_STATE/data'

run_training () { # args: task_name, instance_type, additional_command_params, [description] [epochs] [additional_args]
    EPOCHS=${5:-20}  # 20 epochs by default
    ADDITIONAL_ARGS=${6:-"--no_spot --force_running"} # --force_running

    echo ===== Training $EPOCHS epochs, $4...
    ssm shell -p ex-imagenet -t $1 --dir_files ./code -o ./output/$1 \
        --iit train download state FullyReplicated data/train \
        --iit val download state FullyReplicated data/val \
        --download_model --download_output \
        --it $2 $ADDITIONAL_ARGS \
        --cmd_line  "./extract.sh \$SM_CHANNEL_TRAIN/.. && \ 
                    CODE_DIR=\`pwd\` && cd \$SSM_INSTANCE_STATE &&
                    time python \$CODE_DIR/main.py --epochs $EPOCHS \$SM_CHANNEL_TRAIN/.. $3"
}

DESC="a single GPU"
run_training train-1gpu ml.p3.2xlarge "" "$DESC" &
DESC="distributed training, a single GPU"
run_training train-dist-1gpu ml.p3.2xlarge "--multiprocessing-distributed --dist-url env:// --world-size 1 --rank 0 --seed 123" "$DESC" &
DESC="distributed training, 8 GPUs"
run_training train-dist-8gpus ml.p2.8xlarge "--multiprocessing-distributed --dist-url env:// --world-size 1 --rank 0 --seed 123" "$DESC" &
DESC="distributed training, 3 instances, total 3 GPUs"
run_training train-dist-3nodes-3gpus ml.p3.2xlarge '--multiprocessing-distributed --dist-url env:// --world-size $SSM_NUM_NODES --rank $SSM_HOST_RANK --seed 123' "$DESC" \
        20 "--no_spot --ic 3" &

wait
echo "FINISHED!"
exit
