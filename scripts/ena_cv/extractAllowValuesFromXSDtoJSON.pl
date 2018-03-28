#!/usr/bin/perl
#############################
##BACKGROUND: 
##		In the FAANG metadata preparation, at the moment, no ENA validation is provided which makes it very likely that the user uses the values not valid in the ENA metadata, 
##		particularly using values which are not allowed in the xsd files. This script extracts all allowed values for the interested columns in the experiment metadata xls template and 
##      outputs into json (which can be converted into ruleset to be displayed on the website) and tsv (which can be imported into xls template to be used in the data validation) formats.

##PREQUISITE: 
##		a pre-compiled tsv file "restricted field list.tsv" having 1st column as the name of columns which have constrained values, 2nd column as the sheet name containing such columns, 
##		3rd column containing the xsd file which to be parsed and 4th column containing the element/attribute name
##		This tsv file is prepared by the following way:
#in xsd file look for
#  <xs:simpleType name="typeLibraryStrategy">
#    <xs:restriction base="xs:string">    the option is simply defined in the base, String
#      <xs:enumeration value="WGS">
# OR
#  <xs:choice>  the choice could be a complex element type
#	 <xs:element name="SINGLE">
#by searching "xs:restriction" and "xs:choice", a list of elements/attributes with limited values is compiled and saved into "restricted field list.tsv"
#then manually comparing to the experiment metadata xls file, find the columns mapped to the found elements/attributes
#in the tsv files, lines starting with "#" or empty lines should be ignored. Each line should have four columns in the order of 1) column name, 2) which sheet this column coming from, 3) the xsd file name and 4)attribute/element name
use JSON;
use strict;
use Data::Dumper; #library for debugging purpose
use XML::Simple; #library for parsing xsd files

my $baseUrl = 'https://rawgithub.com/enasequence/schema/master/src/main/resources/uk/ac/ebi/ena/sra/schema/';

my $xmlReader = new XML::Simple;

$"=">,<";#for debugging purpose
#my %toCheck; #current implementation reads the xsd file every time, ideally should only be read once. As the xsd file is normally small, not worth spending extra time coding for that

my $numArg = scalar @ARGV;
&usage() unless ($numArg == 1 || $numArg == 2);

my $flag = 0;
if ($numArg == 2){
	&usage() unless ($ARGV[1]=~/^\d$/);
	&usage() if ($ARGV[1] != 1 && $ARGV[1] != 0);
	$flag = $ARGV[1]; 
}

#uncomment to debug individual term
#&parseXSD("SRA.common.xsd","SpotDescriptorType");
#&parseXSD("SRA.common.xsd","SequencingDirectivesType");
#&parseXSD("SRA.common.xsd","SAMPLE_DEMUX_DIRECTIVE");
#&parseXSD("SRA.submission.xsd","ACTION");
#exit;

#read in the pre-compiled TSV file
open TSV, "$ARGV[0]" || die "Could not find the tsv file\n";
#the one would be used in Excel for data validation (added by a separate VBA code)
open OUT, ">limitedValuesList.tsv";
print "deleting all existing xsd files to make sure the xsd file parsed are up-to-date\n";
system ("rm *.xsd");

my @totalInstruments;
my %totalInstruments;

my @elmts; #the data structure to be exported into json
while (my $line = <TSV>){
	chomp ($line);
	next if (length $line==0);
	next if (substr($line,0,1) eq "#");
	my  ($columnName, $sheet, $xsdFile, $entity) = split("\t",$line);
	print OUT "$columnName\t$sheet\t";
	print OUT "$xsdFile\t" if ($flag == 1);
	print OUT "$entity";
	&checkXSDfile($xsdFile);
	my %hash = %{&parseXSD($xsdFile,$entity)};
	$hash{name} = $columnName;
	$hash{expected_sheet} = $sheet;
	$hash{type} = "text";
	push(@elmts,\%hash);

	if ($columnName eq "INSTRUMENT_MODEL"){
		my @val = @{$hash{valid_values}};
		foreach my $val(@val){
			#this way could make instrument models under one type being grouped together
			unless (exists $totalInstruments{$val}){
				$totalInstruments{$val} = 1;
				push(@totalInstruments,$val);
			}
		}
	}
#	$toCheck{$xsdFile}{$entity}=1;
}
my $str = join("\t",@totalInstruments);
print OUT "INSTRUMENT_MODEL\tExperiment_ENA\t\t$str\n";
close OUT;
#print Dumper(\%toCheck);

#convert the data structure into a pretty-formated json
my $json = to_json(\@elmts,{pretty=>1});
open JSON_OUT,">ena_metadata_ruleset.json";
print JSON_OUT "$json\n";
close JSON_OUT;

#check the existance of the xsd file, if not, download from github directly using curl
sub checkXSDfile(){
	my $file = $_[0];
	return if (-e $file);
	my $fileUrl = "$baseUrl$file";
	print "Downloading file $file from link $fileUrl\n";
	system("curl -L -O $fileUrl"); #-L allow redirect -O Write output to a local file named like the remote file we get.
}

#search the term in the specified xsd file and return all allowed values for that term
sub parseXSD(){
	my $xsdFile = $_[0];
	my $term = $_[1];
	print "Checking <$term> in the xsd file <$xsdFile>\n";
	my $data = $xmlReader->XMLin("$xsdFile");
	my %result;
	#walk through all nodes (subhashes) starting from the root element
	#which is implemented by adding all hash refs into an array (@nodes) and take one out of the array, when the array is empty, the tree has been checked thoroughly
	my @nodes;
#	print Dumper($data);
	push (@nodes,$data);
	my $found; # the ref of the node (a sub hash) matching to the term
	while (scalar @nodes>0){ #the node array is not empty
		my %curr = %{shift (@nodes)};
		foreach (keys %curr){

			if($term eq $_){ #found the term, quit the current searching loop and parse the matching node only
				$found = $curr{$_};
				print "found for $term\n";
	#			print Dumper($found);exit;
				last;
			}
			#if there are extra attribute in the element, the name will be 
			if ($_ eq "xs:element"){
				if(exists $curr{$_}{name} && $curr{$_}{name} eq $term){
					$found = $curr{$_};
					print "found for $term\n";
					last;
				}
			}
			#depends on the type of the value
			my $value = $curr{$_};
			my $ref = ref($value);
			if ($ref eq ""){ #scalar, means reaching a leaf node, nothing needs to be done 
#				print "scalar\t$value\n";
			}elsif($ref eq "ARRAY"){ #array of refs, in this scenario, so far only one level of arrays is observed
				my @arr = @{$value};
				foreach my $a(@arr){
					if (ref($a) eq "HASH"){
						push (@nodes,$a);
					}
				}
			}elsif($ref eq "HASH"){ #add this child node into node list
				push (@nodes,$curr{$_});
			}else{ #should not happen
				print "Unrecognized\n";
			}
		}
	}
#	print Dumper($found);
	die "NOT found <$term>\n" unless (defined($found));

	@nodes = (); #recycle the data structure to walk through the found node
	push (@nodes,$found);
	my @result; #to store the allowed values
	while(scalar @nodes>0){
		my %curr = %{shift (@nodes)};
		foreach (keys %curr){
			if ($_ eq "xs:enumeration"){
				my $arrref = &parseEnumeration($curr{$_});
				@result = @{$arrref};
				last;
			}elsif($_ eq "xs:choice"){
				@result = keys %{$curr{"xs:choice"}{"xs:element"}};
				last;
			}else{
				my $value = $curr{$_};
				my $ref = ref($value);
				if($ref eq "ARRAY"){ #array 
					my @arr = @{$value};
					foreach my $a(@arr){
						if (ref($a) eq "HASH"){
							push (@nodes,$a);
						}
					}
				}elsif($ref eq "HASH"){ #add this child node into node list
					push (@nodes,$curr{$_});
				}
			}
		}	
	}
	my $str = join("\t",@result);
	print OUT "\t\t$str\n";
	$result{valid_values} = \@result;
	#Attributes are optional by default. To specify that the attribute is required, use the "use" attribute use="optional"
	$result{mandatory} = "optional" if(exists $$found{"use"} && $$found{"use"} eq "optional"); #without mandatory key assuming it is mandatory
	print "\n";
#	print Dumper(\%result);exit;
	return \%result;
}

sub parseEnumeration(){
	my $ref = $_[0];
	my @result;
	if (ref($ref) eq "ARRAY"){
		my @arr = @{$ref};
		foreach my $hashref(@arr){
			push (@result,$$hashref{value});
		}
	}else{
		push (@result, $$ref{value});
	}
	return \@result;
}

sub testReadInJSON(){
	open IN, "generated.json";
	my $json = "";
	while (my $line=<IN>){
		$json .= $line;
	}
	my $text = decode_json ($json);
	print Dumper($text);
}

sub testWriteToJSON(){
	my @elmts;
	for (my $i=1;$i<4;$i++){
		my %hash;
		$hash{id} = $i;
		$hash{value} = "$i * $i equals ".($i*$i);
		my @a;
		for (my $j=0;$j<$i;$j++){
			push(@a,$j);
		}
		$hash{arr} = \@a;
		push (@elmts,\%hash);
	}
#	my $json = JSON->new;
	
	my $str = to_json(\@elmts,{pretty=>1});
	print "$str\n\n";
#	print Dumper(\@elmts);
#$json_text = JSON->new->utf8->encode($perl_scalar)
#$json = $json->pretty([$enable])
	my $json_str = encode_json (\@elmts);
	print "$json_str\n";
}

sub usage(){
	print "Usage: perl extractAllowValuesFromXSDtoJSON.pl <restricted field list> [flag indicating whether including xsd file in result]\n";
	print "The restricted field list contains the information of element/attributes which have limited allowed values in the xsd files. It must be a TSV file and have four columns in the order:\n";
	print "1. the name of the columns requiring limited values\n2. the tab (aka work sheet) name which contains those columns\n";
	print "3. the name of xsd file and\n4. element/attribute containing the allowed values.\n";
	print "The flag can only have two values: 1 for including or 0 for not including (default value).\n";
	exit 1;
}

#         "allow_multiple": 1,
#         "mandatory": "optional",
#          "name": "delivery ease",
#          "description": "Did the delivery require assistance",
#          "type": "text",
#          "valid_values": [
#            "normal autonomous delivery",
#            "c-section",
#            "vetinarian assisted"
#          ]
