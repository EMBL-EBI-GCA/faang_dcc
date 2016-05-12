#!/bin/bash
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CONFIG_DIR=$SCRIPT_DIR/../config
OUTPUT_DIR=$SCRIPT_DIR #change this location

#TODO Change from using -search_tag_value FAANG to using the FAANG sample group when BioSamples have fixed it

#unprocessed sample informatio
perl $SCRIPT_DIR/sample_group_dumper.pl -output $OUTPUT_DIR/faang_samples.json -output_format json -search_tag_field project -search_tag_value FAANG && \ 
	perl $SCRIPT_DIR/sample_group_dumper.pl -output $OUTPUT_DIR/faang_samples.inherit.json -output_format json -cleanup_submission_dates -inherit_attributes -json_source $OUTPUT_DIR/faang_samples.json && \
	perl $SCRIPT_DIR/sample_group_dumper.pl -output $OUTPUT_DIR/faang_samples.inherit.tsv -output_format tsv -tsv_column_file $CONFIG_DIR/sample_index_columns.txt -json_source $OUTPUT_DIR/faang_samples.inherit.json
