Perl common function library
misc.pl   			version 1.1.0

ChIP Input control mappings
chip_input_control.pl
chip_input_control.sh

Check how many optional fields in FAANG actually contain meaningful values
checkOptionalFieldUsage.pl

Find mandatory field containing null value
nullInMandatory.pl

ENA controlled vocabularies
ena_cv/all_limited_columns.tsv  				input file of parseMandatoryFieldsInENAxsdFiles.pl, listing all columns with limited values
ena_cv/extractAllowValuesFromXSDtoJSON.pl       extract the allowed values into TSV file (limitedValueList.txt) and JSON file (ena_metadata_ruleset.json)
ena_cv/parseMandatoryFieldsInENAxsdFiles.pl  	output files will be mandatoryFieldsInENAxsdFiles.json|tsv
ena_cv/restricted field list.tsv   				input file of extractAllowValuesFromXSDtoJSON.pl as first parameter, only list the fields used in FAANG