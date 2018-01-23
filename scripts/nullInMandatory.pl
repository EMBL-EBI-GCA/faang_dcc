#!/usr/bin/perl
use strict;
use JSON;
use Data::Dumper;
use LWP::UserAgent;

require "misc.pl";

if (scalar @ARGV!=0){
	print "Usage: perl nullInMandatory.pl\n";
	exit 1;
}

#the faster way to get count of optional field containing values
#GET faang/organism/_search 
#{
#  "size": 10000,   
#  "query": {
#    "filtered": {
#      "filter" : {
#        "exists": {
#          "field": "birthLocationLatitude"
#        }
#      }
#    } 
#  }
#}
#which can also be used to check individual field which has no usage to see whether it is really the case, not due to coding bug

##########################################################################################################
##This script is to read the sample ruleset JSON file and check the usage of all optional/recommend fields 
##in the FAANG data portal. The FAANG data is retrieved using elasticsearch
##The background of the conversion from ruleset into elasticsearch can be found at 
##https://github.com/FAANG/faang-portal-backend/tree/master/elasticsearch
##########################################################################################################
#using typeglob way to introduce a constant variable
*INDEX = \"faang";
*ORGANISM = \"organism";
*SPECIMEN = \"specimen";
our $INDEX;
our $ORGANISM;
our $SPECIMEN;
my $es_host = "ves-hx-e4:9200";

my %counts = getTotalNumber(); #the count of optional field with meaningful values
print Dumper(\%counts);
&parseRulesetJSON();

#corresponding elasticsearch command
#	GET /faang/specimen/_search 
#	{
#    	"aggs" : {
#        	"material" : {
#            	"terms" : { "field" : "material.text" }
#        	}
#    	}
#	}
sub getTotalNumber(){
	my %hash;
	my $total = 0;
	my %counts;
	$hash{aggs}{material}{terms}{field}="material.text";
	my $requestJson = to_json(\%hash);
#	print "$requestJson\n"; #should have the same structure as the part above after _search
	my $jsonResult = &httpPost("http://$es_host/$INDEX/$SPECIMEN/_search",$requestJson);

	my @buckets = @{$$jsonResult{aggregations}{material}{buckets}};
	foreach my $bucket(@buckets){
		$counts{$$bucket{key}}=$$bucket{doc_count};
		$total += $$bucket{doc_count};
	}
	$counts{total} = $total;
	return %counts;
}

#{
#  "query": {
#    "filtered": {
#      "filter": {
#        "missing": {
#          "field": "breed"
#        }
#      }
#    }
#  },
#  "size": 60,
#  "fields": "_id"
#}
sub getMissingNumberUsingES(){
	my ($type,$term) = @_;
	my $str = "$type\t$term\t";
	my $host = "http://$es_host/$INDEX/$SPECIMEN/_search";
	if ($type eq "standard" || $type eq "organism"){
		$host = "http://$es_host/$INDEX/$ORGANISM/_search";
	}else{
		$term = &toLowerCamelCase($type).".$term" if ($term ne "derivedFrom");
	}
	my %hash;
	$hash{query}{filtered}{filter}{missing}{field}=$term;
	$hash{size} = 10000;
	$hash{fields} = "_id";
	my $requestJson = to_json(\%hash);
	my $jsonResult = &httpPost($host,$requestJson);
	my $num = $$jsonResult{hits}{total};
	unless($num == 0){
		if ($type eq "standard" || $type eq "organism"){
			my $ids = join(",",&getIDs($$jsonResult{hits}{hits}));
			print "$str$num\t$ids\n";
		}else{
			my $expected = $counts{total};#the expected number of not having that field, e.g. no record, or different specimen type
			if (exists $counts{$type}){ # not exists, then no such type of specimen data
				$expected = $counts{total} - $counts{$type};
			}	
			print "$str$num\t$expected\n" unless ($num == $expected);
		}
	}

}

sub getIDs(){
	my @hits = @{$_[0]};
	my @result;
	foreach my $hit(@hits){
		push (@result,$$hit{_id});
	}
	return @result;
}


sub parseRulesetJSON(){
	#get the latest ruleset JSON file
	my $jsonFile = "faang_samples.metadata_rules.json";
	system ("rm $jsonFile") if (-e $jsonFile);#make sure always get the latest version
	my $fileUrl = "https://raw.githubusercontent.com/FAANG/faang-metadata/master/rulesets/$jsonFile";
	system("curl -L -O $fileUrl"); #-L allow redirect -O Write output to a local file named like the remote file we get.
	#parse the downloaded JSON file
	my $pipe;
	open $pipe, "$jsonFile";
	#convert into json which is stored in a hash, return the ref to the hash
	my $json = decode_json(&readHandleIntoString($pipe));
	#rulesets are stored under rule_groups
	foreach my $rule_section_ref(@{$$json{rule_groups}}){
		my %rule_sections = %{$rule_section_ref};
		my $type = $rule_sections{name};
		#section name may be different to the values used in Material field in FAANG
		if (exists $rule_sections{condition} && exists $rule_sections{condition}{attribute_value_match} && exists $rule_sections{condition}{attribute_value_match}{Material}){
			my @tmp = @{$rule_sections{condition}{attribute_value_match}{Material}};
			$type = $tmp[0];
		}
		foreach my $rule_ref(@{$rule_sections{rules}}){
			my %rule=%{$rule_ref};
			if ($rule{mandatory} eq "mandatory"){
				my $field = &toLowerCamelCase($rule{name});
				$field = "description" if ($field eq "sampleDescription"); #this manual conversion is due to the discrepancy between es fields and ruleset fields
				&getMissingNumberUsingES($type,$field);
			}
		}
	}
}
