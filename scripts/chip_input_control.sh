#!/bin/bash
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CONFIG_DIR=$SCRIPT_DIR/../config
OUTPUT_DIR=$SUPPORTING_INFO

perl $SCRIPT_DIR/chip_input_control.pl $RESEQTRACK_DB_ARGS -output_file $OUTPUT_DIR/input_lookup_auto.json

