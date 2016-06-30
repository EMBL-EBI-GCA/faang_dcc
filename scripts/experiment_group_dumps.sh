#!/bin/bash
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CONFIG_DIR=$SCRIPT_DIR/../config
OUTPUT_DIR=$SUPPORTING_INFO


#experiment information from RST - for ERSA pipeline in JSON, and TSV for other uses
perl $SCRIPT_DIR/experiment_group_dumper.pl -output $OUTPUT_DIR/rst_experiments.json -output_format json -pretty_json  -validation_rules_file $VALIDATE_RULES/faang_experiments.metadata_rules.json $RESEQTRACK_DB_ARGS && perl $SCRIPT_DIR/experiment_group_dumper.pl -output $OUTPUT_DIR/rst_experiments.tsv -output_format tsv -json_source $OUTPUT_DIR/rst_experiments.json

