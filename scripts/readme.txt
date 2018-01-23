Perl common function library
misc.pl   			version 1.1.0

Manifest file generation
sample_manifest_generation.pl  	generate both detail and summary manifest files of BioSample from ES 
biosamples_tsv_git.run			automatically commit to repository
ftp_biosample_dumps.sh			ftp the generated manifest files to FTP site

ChIP Input control mappings
chip_input_control.pl
chip_input_control.sh

Check how many optional fields in FAANG actually contain meaningful values
checkOptionalFieldUsage.pl

Find mandatory field containing null value
nullInMandatory.pl

Unknown usage
cleanup_archive.sh
experiment_data_dumper.pl
experiment_data_dumps.sh
sample_group_dumper.pl
sample_group_dumps.sh
sample_group_maintenance.pl
sync_metadata.sh
update_current_tree.sh


ENA controlled vocabularies
ena_cv/all_limited_columns.tsv  				input file of parseMandatoryFieldsInENAxsdFiles.pl, listing all columns with limited values
ena_cv/extractAllowValuesFromXSDtoJSON.pl       extract the allowed values into TSV file (limitedValueList.txt) and JSON file (ena_metadata_ruleset.json)
ena_cv/parseMandatoryFieldsInENAxsdFiles.pl  	output files will be mandatoryFieldsInENAxsdFiles.json|tsv
ena_cv/restricted field list.tsv   				input file of extractAllowValuesFromXSDtoJSON.pl as first parameter, only list the fields used in FAANG