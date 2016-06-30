# FAANG Data Coordination Centre infrastructure

This repo contains tools to support FAANG DCC activities at EMBL-EBI.

The infrastructure stack requires comprises several components


## Code Dependencies


This code depends directly upon

 * [reseqtrack](https://github.com/EMBL-EBI-GCA/reseqtrack)
 * [BioSD](https://github.com/EMBL-EBI-GCA/BioSD) 
 * [eHive](https://github.com/Ensembl/ensembl-hive)
 * [validate-metadata](https://github.com/FAANG/validate-metadata)
 * [FAANG metadata rules](https://github.com/FAANG/faang-metadata/tree/master/rulesets)

## File archive site

This is a resilient file archiving system hosted at EMBL-EBI. It is publicly visible at [http://ftp.faang.ebi.ac.uk/ftp/](http://ftp.faang.ebi.ac.uk/ftp/). It is also available over ftp, aspera and GridFTP protocols. 

## Reseqtrack database

This mirrors metadata and tracks files, both archived and  in the pre-archiving staging area. The code for this was originally developed for the 1000 genomes project and is available on [github](https://github.com/EMBL-EBI-GCA/reseqtrack).

## Processing

We will use the following definitions in command line arguments

    RESEQTRACK=/path/to/reseqtrack/
    FAANG_CODE=/path/to/faang_dcc
    VALIDATE=/path/to/validate-metadata
    VALIDATE\_RULES=/path/to/faang_metadata/rules
    SUPPORTING\_INFO=/path/to/supporting-info
    
    RESEQTRACK\_DB\_PASS=*password*
    RESEQTRACK\_DB\_HOST=*hostname*
    RESEQTRACK\_DB\_PORT=*port number*
    RESEQTRACK\_DB\_USER=*database user*
    RESEQTRACK\_DB\_NAME=*database schema name*
    RESEQTRACK_DB_ARGS="-dbhost $RESEQTRACK_DB_HOST -dbuser $RESEQTRACK_DB_USER -dbpass $RESEQTRACK_DB_PASS -dbport $RESEQTRACK_DB_PORT -dbname $RESEQTRACK_DB_NAME"
    
    ERA_DB_USER=*ERA database username*
    ERA_DB_PASS=*ERA database password*
    ERA_DB_NAME=*Name of ERA database*
    ERA_DB_ARGS="-era_dbuser $ERA_DB_USER -era_dbpass $ERA_DB_PASS -era_dbname $ERA_DB_NAME"
    
    ENSEMBL\_HIVE_DIR=/path/to/ensembl-hive
    HIVE\_DB\_OPTS="-hive_host $RESEQTRACK_DB_HOST -hive_user $RESEQTRACK_DB_USER -hive_pass $RESEQTRACK_DB_PASS -hive_port $RESEQTRACK_DB_PORT"
    
### Metadata retrieval

Projects/studies should be added to Reseqtrack  using their study ID. 

    $RESEQTRACK/scripts/metadata/load_from_ena.pl $RESEQTRACK_DB_ARGS $ERA_DB_ARGS -new_study *study ID*

Metadata should be updated from ENA reguarly:

    $RESEQTRACK/scripts/metadata/load_from_ena.pl $RESEQTRACK_DB_ARGS $ERA_DB_ARGS -load_new -update_existing -quiet

### FASTQ file retrieval

FASTQ files are retrieved from ENA using an eHive pipeline, configured in `config/get_fastq_pipe_conf`. Placeholders in the config file should be replaced, then the pipeline can be registered in the reseqtrack DB like so:

    $RESEQTRACK/scripts/pipeline/load_pipeline_from_conf.pl $RESEQTRACK_DB_ARGS -file $FAANG_CODE/config/get_fastq_pipe_conf -read

The eHive database should be initialised, seeded and run like this:

    perl $RESEQTRACK/scripts/pipeline/init_hive_db.pl $RESEQTRACK_DB_ARGS -pipeline_name GetProjectFastq -ensembl_hive_dir $ENSEMBL_HIVE_DIR $HIVE_DB_OPTS
    perl $RESEQTRACK/scripts/pipeline/run_pipeline.pl $RESEQTRACK_DB_ARGS $HIVE_DB_OPTS -pipeline_name GetProjectFastq -submission_options '-R"select[lustre]"' -run -loop

The eHive database can be retired after use:

    perl $RESEQTRACK/scripts/pipeline/retire_hive_db.pl $RESEQTRACK_DB_ARGS -pipeline_name GetProjectFastq

### Data delivery to Ensembl Regulation

The Ensembl Regulation will analyse FAANG ChIP-Seq data using their ERSA system. To facilitate this, we have created software to convert information from ENA and BioSamples into a form that ERSA can use. Metadata and FASTQ files should be loaded prior to invoking this pipeline.

The pipeline can be registered in the reseqtrack DB like this:

    $RESEQTRACK/scripts/pipeline/load_pipeline_from_conf.pl $RESEQTRACK_DB_ARGS -file $FAANG_CODE/config/ersa_fastq_delivery_conf -read

The eHive database should be initialised, seeded and run like this:

    perl $RESEQTRACK/scripts/pipeline/init_hive_db.pl $RESEQTRACK_DB_ARGS -pipeline_name DeliverErsaFastq -ensembl_hive_dir $ENSEMBL_HIVE_DIR $HIVE_DB_OPTS
    perl $RESEQTRACK/scripts/pipeline/run_pipeline.pl $RESEQTRACK_DB_ARGS $HIVE_DB_OPTS -pipeline_name DeliverErsaFastq -submission_options '-R"select[lustre]"' -run -loop

The hive database can be retired after use:

    perl $RESEQTRACK/scripts/pipeline/retire_hive_db.pl $RESEQTRACK_DB_ARGS -pipeline_name DeliverErsaFastq

This pipeline depends on several pieces of supporting information.

 * BioSample information, as the JSON serialisation of `Bio::Metadata::Entity` objects. 
 * Experiment information, as the JSON serialisation of `Bio::Metadata::Entity` objects
 * Mappings of ChIP Input run to use in the analysis of non-input ChIP runs, as simple JSON attribute-value pairs. Multiple files can be specified, the earliest in the list taking precedence. This is to allow mappings to be generated automatically, but overruled manually if required.
 
This supporting information can be produced by scripts in this repository, see the following sections.

### BioSample and experiment serialisation

BioSample information is serialised as JSON for use in the delivery to Ensembl Regulation pipeline, and in tabular form for general consumption. This is implemented in these scripts:

 *  `scripts/sample_group_dumps.sh`. 
 * `scripts/experiment_group_dumps.sh`
 
### ChIP Input control mappings

The ERSA pipeline needs to know which ChIP input runs should be used as a control when peak calling non-input ChIP runs. 

The mapping files must conatain key-value pairs, in JSON format, e.g.

    {
       "ERR572239" : "ERR572273",
       "ERR572165" : "ERR572128",
       "ERR572201" : "ERR572146"
    }

The key should be the run ID for the non-input ChIP, the value should be the run ID for the input ChIP to use as control.

This mapping is produced automatically by `scripts/chip_input_control.sh`, the results are written to `$SUPPORTING_INFO/input_lookup_auto.json`. The automatic mappings can be overriden by changing `$SUPPORTING_INFO/input_lookup_manual.json`.

### Archive maintenance

The archiving processes require regular cleanup, this is managed through `scripts/cleanup_archive.sh`. A tree file listing the contents of the archive is maintained by running `scripts/update_current_tree.sh`.

### BioSample group maintenance

FAANG BioSamples are identified with the a `project` attribute of `FAANG`. All FAANG samples are added to a single [BioSamples group](http://www.ebi.ac.uk/biosamples/group/SAMEG307473). This is accomplished through `scripts/sample_group_maintenance`. At present display of this group has some issues, causing it to appear empty.  



