#!/bin/bash
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CONFIG_DIR=$SCRIPT_DIR/../config
OUTPUT_DIR=$SUPPORTING_INFO

perl $RESEQTRACK/scripts/metadata/load_from_ena.pl $RESEQTRACK_DB_ARGS $ERA_DB_ARGS -load_new -update_existing -quiet
