#!/usr/bin/perl
use strict;
use JSON;
use Data::Dumper;
use LWP::UserAgent;

if (scalar @ARGV!=0){
	print "Usage: perl checkOptionalFieldUsage.pl\n";
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

my @sections = ("standard","organism","specimen from organism","pool of specimens","cell specimen","cell culture","cell line");
my @mandatoryTypes = qw/recommended optional/;
#test the toLowerCamelCase function
#my @test = qw/variable_name VARIABLE_NAME _var_x_short __variable__name___/;
#push (@test, "health status");
#foreach (@test){
#	print "$_\t";
#	my $str = &toLowerCamelCase($_);
#	print "$str\n";
#	my $back = &fromLowerCamelCase($str);
#	print "$back\n";
#}
#exit;

#field even contains the values listed below still will be treated as empty
my @emptyValues =("not applicable","not collected","not provided","restricted access","undef","");#the first four are predefined values available at https://www.ebi.ac.uk/seqdb/confluence/display/FAANG/Submission+of+samples+to+BioSamples
my %emptyValues;
foreach (@emptyValues){
	$emptyValues{$_}=1;
}

my %counts; #the count of optional field with meaningful values
my %optionalFields = %{&parseRulesetJSON()}; 
&getTotalNumber();

#print "Optional fields:\n";
#print Dumper(\%optionalFields);exit;
#&parseDataTest($es_host,"SAMEA6688918"); #childOf    value in array
#&parseDataTest($es_host,"SAMEA4447825"); #placetal weight, which has the value not provided
#&parseDataTest($es_host,"SAMEA4448005"); #health status      value in array of hash
#print Dumper(\%counts);
#exit;

&getData($es_host,$INDEX,$ORGANISM);
&getData($es_host,$INDEX,$SPECIMEN);
#output and calculate the average percentage
my %stats;
my %statsIncluding;
open OUT, ">optionalFieldsUsage.tsv";
print OUT "Section\tStatus\tField\tTotal Entries\tCount\tPercentage\tCount including not provided\tPercentage including\n";
foreach my $section(@sections){
	foreach my $status(@mandatoryTypes){
		if (exists $optionalFields{$section}{$status}){
			foreach my $field (@{$optionalFields{$section}{$status}}){
#				$field = &fromLowerCamelCase($field);
				print OUT "$section\t$status\t";
				print OUT &fromLowerCamelCase($field);
				print OUT "\t";
				my $count = 0;
				$count = $counts{$section}{$status}{$field} if (exists $counts{$section}{$status}{$field});
				my $total = 0;
				if ($section eq "standard"){
					$total = $counts{total}{$ORGANISM};
				}else{
					$total = $counts{total}{$section} if (exists $counts{total}{$section});
				}
				my $ratio;
				my $ratioIncluding;
				my $includingNumber;
				if($total==0){
					$ratio = "NA";
					$ratioIncluding = "NA";
					$includingNumber = 0;
				}else{
					$ratio = $count/$total;
					push (@{$stats{$section}{$status}},$ratio);
					if ($section eq "organism" || $section eq "standard"){
						push (@{$stats{animal}{$status}},$ratio);

						$includingNumber = &getNumberUsingES($ORGANISM,$field);
						$ratioIncluding = $includingNumber/$total;
						push (@{$statsIncluding{animal}{$status}},$ratioIncluding);
					}else{
						push (@{$stats{specimen}{$status}},$ratio);

						$field = &toLowerCamelCase($section).".$field";
						$includingNumber = &getNumberUsingES($SPECIMEN,$field);
						$ratioIncluding = $includingNumber/$total;
						push (@{$statsIncluding{specimen}{$status}},$ratioIncluding);
					}
					push (@{$stats{overall}{$status}},$ratio);

					push (@{$statsIncluding{$section}{$status}},$ratioIncluding);
					push (@{$statsIncluding{overall}{$status}},$ratioIncluding);
				}
				print OUT "$total\t$count\t$ratio\t$includingNumber\t$ratioIncluding\n";
			}
		}
	}
}

print OUT "\n\nAverage Percentage\nSection\tStatus\tExcluding\tIncluding\n";
my @arr = ("overall","animal","specimen",@sections);
foreach my $section(@arr){
	foreach my $status(@mandatoryTypes){
		if (exists $stats{$section}{$status}){
			my @arr = @{$stats{$section}{$status}};
			my $avg = &average(@arr);
			@arr = @{$statsIncluding{$section}{$status}};
			my $avgInc = &average(@arr);
			print OUT "$section\t$status\t$avg\t$avgInc\n";
		}
	}
}
#calculate average of an array
sub average(){
	my @data=@_;
	my $sum = 0;
	my $len = scalar @data;
	foreach my $data(@data){
		$sum += $data;
	}
	return $sum/$len;
}

#get total number of each material type available using elasticsearch aggregation function and save into %counts
#it only needs to be done for specimen, not for organism
sub getTotalNumber(){
#corresponding elasticsearch command
#	GET /faang/specimen/_search 
#	{
#    	"aggs" : {
#        	"material" : {
#            	"terms" : { "field" : "material.text" }
#        	}
#    	}
#	}
	my %hash;
	$hash{aggs}{material}{terms}{field}="material.text";
	my $requestJson = to_json(\%hash);
#	print "$requestJson\n"; #should have the same structure as the part above after _search
	my $jsonResult = &httpPost("http://$es_host/$INDEX/$SPECIMEN/_search",$requestJson);

	my @buckets = @{$$jsonResult{aggregations}{material}{buckets}};
	foreach my $bucket(@buckets){
		$counts{total}{$$bucket{key}}=$$bucket{doc_count};
	}
}
#{
#  "query": {
#    "filtered": {
#      "filter" : {
#        "exists": {
#          "field": "pedigree"
#        }
#      }
#    } 
#  }
#}
sub getNumberUsingES(){
	my ($type,$term) = @_;
	my %hash;
	$hash{query}{filtered}{filter}{exists}{field}=$term;
	my $requestJson = to_json(\%hash);
	my $host = "http://$es_host/$INDEX/$type/_search";
	my $jsonResult = &httpPost($host,$requestJson);
	my $num = $$jsonResult{hits}{total};
#	print "$num\n";	
	return $num;
}

#do a POST request and return json file
sub httpPost(){
	my ($host,$content) = @_;
	my $ua = LWP::UserAgent->new;
	# set custom HTTP request header fields
	my $req = HTTP::Request->new(POST => $host);
	$req->header('content-type' => 'application/json');
	$req->content($content);
 
	my $resp = $ua->request($req);
	my $jsonResult = "";
	if ($resp->is_success) {
    	my $message = $resp->decoded_content;
    	#print "Received reply: $message\n";
    	$jsonResult = decode_json($message);
	}else{
    	print "HTTP POST error code: ", $resp->code, "\n";
    	print "HTTP POST error message: ", $resp->message, "\n";
	}
	return $jsonResult;
}

#download the data
sub getData(){
	my ($es_host,$es_index,$es_type) = @_;
	print "Get data for $es_type from $es_index\n";
	#should use pagination when the size of data is bigger, but fail to do so now
	#https://www.elastic.co/guide/en/elasticsearch/reference/1.5/search-uri-request.html maybe useful
	#for now, just use a big number for size parameter
	my $url="$es_host/$es_index/$es_type/_search?size=20000";#set the size as 20000 as the current database size is 8441
#	my $url="$es_host/$es_index/$es_type/_search?fields=_id&size=10"; #the link to get id only, which is useful for development and debugging
	#retrieve data using curl
	my $pipe;
	open $pipe,"curl -XGET $url|";
	#convert into json which is stored in a hash, return the ref to the hash
	my $json = decode_json(&readHandleIntoString($pipe));
	#hit data are stored under the key "hits", which has the following keys: total, max_score, hits (value for this key is array ref)
	my %hits = %{$$json{hits}};
	my $hit_number = $hits{total};
	$counts{total}{$es_type} = $hit_number;
	#loop through each hit, $hit is a hash ref
	foreach my $hit(@{$hits{"hits"}}){
		&parseData($hit,$es_type);
#		print "$$hit{_id}\n";
	}
}
#parse the hash to check the usage of optional/recommended fields
sub parseData(){
	my $ref = $_[0];
	my $es_type = $_[1];
	my %entity = %{$$ref{_source}}; #elasticsearch result stores under _source

	my $material=$entity{material}{text};
	#there are several different types of specimen which leads to different data structure
	if ($es_type eq $ORGANISM){
		&checkSection(\%entity,"standard");
		&checkSection(\%entity,$material);
	}else{ #specimen
		my %tmp = %{$entity{&toLowerCamelCase($material)}};
		&checkSection(\%tmp,$material);
	}
}
#as the name suggest, it is a test, for development only, by getting a specific organism using biosample id to work out the data structure
sub parseDataTest(){
	my ($es_host,$id) = @_;
	my $es_type = $ORGANISM;
	my $url = "$es_host/$INDEX/$es_type/$id";
	print "$url\n";
	#the link from BioSample provides a direct way, but better to get all data through API/elasticsearch (es)
#	$url = "https://www.ebi.ac.uk/biosamples/api/samples/SAMEA6568918";
	my $pipe;
	open $pipe,"curl -XGET $url|";
	my $json = decode_json(&readHandleIntoString($pipe));
	my %entity=%{$$json{_source}};
	print Dumper(\%entity);
	#the codes below should be identical to parseData()
	my $material=$entity{material}{text};
	if ($es_type eq $ORGANISM){
		&checkSection(\%entity,"standard");
		&checkSection(\%entity,$material);
	}else{ #specimen
		my %tmp = %{$entity{&toLowerCamelCase($material)}};
		&checkSection(\%tmp,$material);
	}
}

#check optional fields in the given section, if found add the count by 1
sub checkSection(){
	my %hash = %{$_[0]};
	my $section = $_[1];
	return unless (exists $optionalFields{$section});#the section only has the mandatory fields
	my %sectionRule = %{$optionalFields{$section}}; #the optional and recommended fields for the given section
	foreach my $status(@mandatoryTypes){#optional or recommended
		next unless (exists $sectionRule{$status}); #check whether exists optional/recommended fields under the section
		foreach my $field(@{$sectionRule{$status}}){
			#the optional/recommended field exists in the data, need to check the value
			if (exists $hash{$field}){#can find the optional field in the data
				my $valueType = ref($hash{$field});
				my $value;
				#get the value for the field according to its different ref type
				if ($valueType eq "HASH"){
					$value = &getMeaningfulValue($hash{$field});
				}elsif($valueType eq "ARRAY"){
					foreach my $elem(@{$hash{$field}}){
						if (ref($elem) eq "HASH"){
							$value = &getMeaningfulValue($elem);
						}else{
							$value = $elem;
						}
						last if (length $value>0);
					}
				}else{ #scalar
					$value = $hash{$field};
				}
#				print "$field\t<$value>\n";
				$counts{$section}{$status}{$field}++ unless (exists $emptyValues{$value}); #the value exists in the %emptyValues should not be counted
			}
		}
	}
}

sub getMeaningfulValue(){
	my %hash = %{$_[0]};
	return $hash{text} if (exists $hash{text});
	return $hash{ontologyTerms} if (exists $hash{ontologyTerms});
	return "";
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
	my %optionalFields;
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
			if ($rule{mandatory} ne "mandatory"){
				my $field = &toLowerCamelCase($rule{name});
				$field = "description" if ($field eq "sampleDescription"); #this manual conversion is due to the discrepancy between es fields and ruleset fields
				push (@{$optionalFields{$type}{$rule{mandatory}}},$field);
			}
		}
	}
	return \%optionalFields;
}

#read the content from the file handle and concatenate into a string
sub readHandleIntoString(){
	my $fh = $_[0];	
	my $str = "";
	while (my $line = <$fh>) {
		chomp($line);
		$str .= $line;
	}
	return $str;
}
#convert a string containing _ or space into lower camel case
sub toLowerCamelCase(){
	my $str = $_[0];
	$str=~s/_/ /g; 
	$str =~ s/^\s+|\s+$//g;
	$str = lc ($str);
	$str =~s/ +(\w)/\U$1/g;
	return $str;
}
#convert a lower camel case string into words separated by space in low cases
sub fromLowerCamelCase(){
	my $str = $_[0];
	my @arr = split(/(?=[A-Z])/,$str);
	return lc(join (" ",@arr));
}
