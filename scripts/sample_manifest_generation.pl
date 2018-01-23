#!/usr/bin/env perl
#It is strongly recommended to read this code while referring to the sample ruleset http://www.ebi.ac.uk/vg/faang/rule_sets/FAANG%20Samples
#similar to referring to corresponding xsd file while writing codes for parsing the xml file
#This script will generate two TSV files: faang_biosample_details.tsv and faang_biosample_summary.tsv
#The detail output file is organized by sections, each section contains all columns from that section in alphabetic order. It contains all records in BioSample labelled with FAANG
#The summary output file contains the summary of each section from records meeting FAANG standard only
#The main algorithm is
#1. read from the elastic search server in two steps: organism and specimen and parsed into %data 
#2. output into detail table
#3. output into summary table
require "misc.pl";

use strict;
use warnings;
use Getopt::Long;
use Carp;
use WWW::Mechanize;
use JSON -support_by_pp;
use Search::Elasticsearch;
use Data::Dumper;
#pre-define the output file name
my $detailOutput = "faang_samples_in_biosamples.tsv";
my $summaryOutput = "biosample_summary.tsv";

#the parameters expected to be retrieved from the command line
my ($es_host, $es_index_name, $output_path);
$output_path = "/hps/cstor01/nobackup/faang/farmpipe/supporting-info";
$es_index_name = "faang";
#Parse the command line options
GetOptions(
  'es_host=s' =>\$es_host,
  'es_index_name=s' =>\$es_index_name,
  'output_path=s' =>\$output_path
);

croak "Need -es_host e.g. ves-hx-e4:9200" unless ($es_host);

my @basicHeaders = ("BioSample ID","Name","Description","Standard Met","Release date","Update date","Material","Organism","Sex","Breed","Organism ontology","Sex ontology","Breed ontology","Organization");
my %organismHeaders; #store headers for organisms
my %specimenHeaders; #store headers for specimens
my %data; #the main data structure

#1. read from the elastic search server in two steps: organism and specimen
my @indice = qw/organism specimen/;
foreach my $index(@indice){
	&getData($index);
}

#manual inspection of single record
#print Dumper($data{specimen}{SAMEA104495754});

open DETAIL,">$output_path/$detailOutput";

my @organismHeaders = sort {$a cmp $b} keys %organismHeaders;
my @specimenHeaders = sort {$a cmp $b} keys %specimenHeaders;

$" = "\t";
print DETAIL "@basicHeaders\t@organismHeaders\t@specimenHeaders\n";
foreach my $index(@indice){
	my %curr = %{$data{$index}};
	foreach my $id (sort keys %curr){
		foreach my $key(@basicHeaders,@organismHeaders,@specimenHeaders){
			if (exists $curr{$id}{$key} && defined $curr{$id}{$key}){ #standard met column may not exist if not meeting standards
				print DETAIL "$curr{$id}{$key}" if (exists $curr{$id}{$key});
			}
			print DETAIL "\t";
		}
		print DETAIL "\n";
	}
}

open SUMMARY,">$output_path/$summaryOutput";
print SUMMARY "FAANG BioSample data summary\n\n";
print SUMMARY "Summary of FAANG project sample data held in the BioSamples database at EMBL-EBI.\n\n";
print SUMMARY "Animal overview\n";
print SUMMARY "Number of records: $data{count}{organism}\n\n";
print SUMMARY "Distribution of Sex:\n".&displayHash($data{summary}{organism}{sex});
print SUMMARY "\nDistribution of Species:\n".&displayHash($data{summary}{organism}{species});
print SUMMARY "\nDistribution of Breed:\n".&displayHash($data{summary}{organism}{breed});
print SUMMARY "\nDistribution of Organization:\n".&displayHash($data{summary}{organism}{organization});

print SUMMARY "\n\nSample overview\n";
print SUMMARY "\nNumber of records: $data{count}{specimen}\n\n";
print SUMMARY "Distribution of specimen types:\n".&displayHash($data{summary}{material});
print SUMMARY "\nDistribution of Sex:\n".&displayHash($data{summary}{specimen}{sex});
print SUMMARY "\nDistribution of Species:\n".&displayHash($data{summary}{specimen}{species});
print SUMMARY "\nDistribution of Breed:\n".&displayHash($data{summary}{specimen}{breed});
print SUMMARY "\nDistribution of Organization:\n".&displayHash($data{summary}{specimen}{organization});

sub getData(){
	my $index = $_[0];
	my $url="$es_host/$es_index_name/$index/_search";
	my $pipe;
	open $pipe,"curl -XGET $url|";
	#convert into json which is stored in a hash, return the ref to the hash
	#default value for size (the number of returned matching records) is 10
	#so to retrieve all records, it requires two steps: first get the total number second set the size accordingly
	my $json = decode_json(&readHandleIntoString($pipe));
	my $numOfRecords = $$json{hits}{total}; 
	$data{count}{$index} = $numOfRecords;
	$url="$es_host/$es_index_name/$index/_search?size=$numOfRecords";
	open $pipe,"curl -XGET $url|";
 	$json = decode_json(&readHandleIntoString($pipe));
	my @hits = @{$$json{hits}{hits}};
	foreach my $hit(@hits){
		my %tmp = %$hit;
		my @tmp = sort {$a cmp $b} keys %tmp;
		my $id = $$hit{_id};
		if($index eq "organism"){
			$hit = &parseOrganism($$hit{_source});
			$data{$index}{$id} = $hit;
		}else{
			$hit = &parseSpecimen($$hit{_source});
			$data{$index}{$id} = $hit;
		}
	}
}

sub parseOrganism(){
	my %organism = %{$_[0]};
#	print "Before parse basic\n";
#	print Dumper(\%organism);
	my @result = &parseBasic(\%organism,0);
	my %result = %{$result[0]};
	%organism = %{$result[1]};
	#deal with organism specific columns here
#	print "After parse basic\n";
#	print Dumper(\%organism);
	my %tmp = &flatten(\%organism,0,"");
	foreach my $tmp(keys %tmp){
		$result{$tmp} = $tmp{$tmp} if(defined($tmp{$tmp}));
	}
#	print Dumper(\%result);
#	print "organism header\n";
#	print Dumper(\%organismHeaders);
#	exit;
	return \%result;
}

sub parseSpecimen(){
	my %specimen = %{$_[0]};
#	print "Before parse basic\n";
#	print Dumper(\%specimen);
	my @result = &parseBasic(\%specimen,1);
	my %result = %{$result[0]};
	%specimen = %{$result[1]};
#	print "After parse basic\n";
#	print Dumper(\%specimen);
	my %tmp = &flatten(\%specimen,1,"");
	foreach my $tmp(keys %tmp){
		$result{$tmp} = $tmp{$tmp} if(defined($tmp{$tmp}));
	}
#	print Dumper(\%result);
#	print "specimen header\n";
#	print Dumper(\%specimenHeaders);
#	exit;
	return \%result;
}
#the name of sub element will be represented as element name sub element name
sub flatten(){
	my %hash = %{$_[0]};
	my $isSpecimen = $_[1];
	my $prefix = $_[2];
	my %result;
	foreach my $key(keys %hash){
		my $ref = ref($hash{$key});
		my $new_key = &fromLowerCamelCase($prefix.ucfirst($key));
		if ($ref eq "HASH"){
			my $newPrefix = $prefix.ucfirst($key);
#			print "new key: $newPrefix\n";
			my %tmp = &flatten($hash{$key},$isSpecimen,$newPrefix);
			foreach my $tmp(keys %tmp){
				$result{$tmp} = $tmp{$tmp} if(defined($tmp{$tmp}));
			}
		}elsif ($ref eq "ARRAY"){
			my @tmp = @{$hash{$key}};
			my $val = "";
			if (scalar @tmp>0){
				$ref = ref($tmp[0]);
				if($ref eq "HASH"){
					my %tmp;
					foreach my $curr(@tmp){
						$tmp{$$curr{text}}=1 if (exists $$curr{text});
					}
					$val = join(";", keys %tmp);
				}else{
					$val = join(";",@tmp);
				}
			}
			if($isSpecimen == 0){
				$organismHeaders{$new_key}++;
			}else{
				$specimenHeaders{$new_key}++;
			}
			$result{$new_key} = $val;
		}else{
			if($isSpecimen == 0){
				$organismHeaders{$new_key}++;
			}else{
				$specimenHeaders{$new_key}++;
			}
			$result{$new_key} = $hash{$key};
		}
	}
	return %result;
}

#parse the common part existing in both organism and specimen
#for the extracted information, remove from the input data structure %in
sub parseBasic(){
	my %in = %{$_[0]};
	my $isSpecimen = $_[1];
	
	if($isSpecimen == 0){ #not specimen, so organism
		$data{summary}{organism}{sex}{$in{sex}{text}}++;
		$data{summary}{organism}{species}{$in{organism}{text}}++;
		$data{summary}{organism}{breed}{$in{breed}{text}}++;
	}else{
		$data{summary}{material}{$in{material}{text}}++;
		$data{summary}{specimen}{sex}{$in{organism}{sex}{text}}++;
		$data{summary}{specimen}{species}{$in{organism}{organism}{text}}++;
		$data{summary}{specimen}{breed}{$in{organism}{breed}{text}}++;
	}

	my %result;
	foreach my $key(@basicHeaders){
		if ($key eq "Organization"){
			my %values;
			foreach my $ref(@{$in{organization}}){
				$values{$$ref{name}}++;
			}
			my @organizations = sort {$a cmp $b} keys %values;
			foreach my $organization(@organizations){
				if ($isSpecimen == 0){
					$data{summary}{organism}{organization}{$organization}++;
				}else{
					$data{summary}{specimen}{organization}{$organization}++;
				}
			}
			$result{$key} = join(";",@organizations);
			delete $in{organization};
		}elsif ($key =~/ontology/){
			my ($new_key) = split(" ",lc($key));
			if ($isSpecimen == 0){
				$result{$key} = $in{$new_key}{ontologyTerms};
				delete $in{$new_key};
			}else{
				$result{$key} = $in{organism}{$new_key}{ontologyTerms};
			}
		}else{
			my $es_key = &toLowerCamelCase($key);
			if (exists $in{$es_key}){
				if (ref($in{$es_key}) eq "HASH"){
					$result{$key} = $in{$es_key}{text};
				}else{
					$result{$key} = $in{$es_key};
					delete $in{$es_key};
				}
			}else{
				if (ref($in{organism}{$es_key})){
					$result{$key} = $in{organism}{$es_key}{text};
				}else{
					$result{$key} = $in{organism}{$es_key};
				}
			}
		}
		if ($isSpecimen > 0 && $key eq "Organism"){
			$result{$key} = $in{organism}{organism}{text};
		}
	}
	delete $in{organism} if ($isSpecimen > 0);
	delete $in{material};
	delete $in{project};
	delete $in{versionLastStandardMet};

	my @result;
	push(@result,\%result);
	push(@result,\%in);
	return @result;
}

sub displayHash(){
	my %hash = %{$_[0]};
	my $str = "";
	foreach (sort {$hash{$b} <=> $hash{$a}} keys %hash){
		$str.="$_\t$hash{$_}\n";
	}
	return $str;
}