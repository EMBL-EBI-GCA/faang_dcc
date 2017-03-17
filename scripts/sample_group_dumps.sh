#!/bin/bash
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CONFIG_DIR=$SCRIPT_DIR/../config
OUTPUT_DIR=$SUPPORTING_INFO

#TODO Change from using -search_tag_value FAANG to using the FAANG sample group when BioSamples have fixed issues with this


#sample information from biosamples - for information
perl $SCRIPT_DIR/sample_group_dumper.pl -output $OUTPUT_DIR/faang_samples_in_biosamples.tsv -output_format tsv -cleanup_submission_dates -inherit_attributes -validation_rules_file $VALIDATE_RULES/faang_samples.metadata_rules.json -tsv_column_file $CONFIG_DIR/sample_index_columns.txt -search_tag_field project_crt -search_tag_value FAANG

#information on samples in reseq track - for ERSA pipeline
perl $SCRIPT_DIR/sample_group_dumper.pl -output $OUTPUT_DIR/rst_samples.json -output_format json -pretty_json -cleanup_submission_dates -inherit_attributes -validation_rules_file $VALIDATE_RULES/faang_samples.metadata_rules.json $RESEQTRACK_DB_ARGS && perl $SCRIPT_DIR/sample_group_dumper.pl -output $SUPPORTING_INFO/rst_samples.tsv -output_format tsv -json_source $OUTPUT_DIR/rst_samples.json -tsv_column_file $CONFIG_DIR/sample_index_columns.txt
