#!/usr/bin/perl
#############################
##BACKGROUND: 
##		This script is supposed to extract all mandatory elements (minOccurs = 1, or minOccurs attribute does not exist) and attributes (use="required") from several xsd files for ENA

##PREQUISITE: 
##		list (hard coded) all xsd files in the @xsdFiles

use JSON;
use strict;
use Data::Dumper; #library for debugging purpose
use XML::Simple; #library for parsing xsd files
$"="\t";
#my $haha = "iejifh|jiehg";
#my @haha = split(/\|/,$haha);
#print "$haha\n@haha\n";
#exit;

my $numArg = scalar @ARGV;
&usage() unless ($numArg == 1);

my $baseUrl = 'https://rawgithub.com/enasequence/schema/master/src/main/resources/uk/ac/ebi/ena/sra/schema/';

my $xmlReader = new XML::Simple;

my %elementToSkip;
#known elements definitely do NOT contain any attribute or element as its child nodes
my @elementToSkip = qw/xs:import xs:annotation xs:documentation xmlns:com xmlns:xs xs:restriction/;
foreach (@elementToSkip){
	$elementToSkip{$_} = 1;
}

open IN, "$ARGV[0]" or die "Could not find the specified file $ARGV[0]";
my %cv_values;
while (my $line=<IN>){
	chomp($line);
	my (undef,undef,$file,$tag,undef,@values) = split ("\t",$line);
	my $str = join("|",@values);
	$cv_values{$file}{$tag} = $str;
#	print "file $file\ttag <$tag>\t<$str>\n";
}

my %json_result;

my %typesInCommon;
#using typeglob way to introduce a constant variable
*COMMON_XSD = \"SRA.common.xsd";
our $COMMON_XSD;
#this statement needs to be executed first, as other xsd files may use types defined in common.xsd
&parseXSD($COMMON_XSD);

#&parseXSD("SRA.sample.xsd");
#&parseXSD("SRA.experiment.xsd");
#&parseXSD("SRA.study.xsd");
#&parseXSD("SRA.submission.xsd");
#exit;

#list of xsd files to check
my @xsdFiles = qw/SRA.experiment.xsd SRA.run.xsd SRA.sample.xsd SRA.study.xsd SRA.submission.xsd/;

open OUT, ">mandatoryFieldsInENAxsdFiles.tsv";
print OUT "xsd file\ttype\tname\tpath\tdescription\tallowed values\n";
#print "deleting all existing xsd files to make sure the xsd file parsed are up-to-date\n";
#system ("rm *.xsd");

foreach my $xsdFile(@xsdFiles){
	&checkXSDfile($xsdFile);
	&parseXSD($xsdFile);
}
close OUT;
my $json = to_json(\%json_result,{pretty=>1});
open JSON_OUT,">mandatoryFieldsInENAxsdFiles.json";
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

#parse one xsd file to extract all mandatory attributes/elements
sub parseXSD(){
	my $xsdFile = $_[0];
#	print "Parsing the xsd file <$xsdFile>\n";
	my $data = $xmlReader->XMLin("$xsdFile");
#	print Dumper($data);
#	return;

	#parse the xsd file and save into the middle data structure %result
	my %result;
	#walk through all nodes (subhashes) starting from the root element
	#which is implemented by adding all hash refs into an array (@nodes) and take one out of the array, when the array is empty, the tree has been checked thoroughly
	my @nodes;
	my @parents; #record the content of parent nodes which is necessary to check whether the current node is an element or not ($parent eq "xs:element"), this data structure has the same length as @nodes
	my @paths;
	#insert the root node to start with
	push (@nodes,$data);
	push (@parents, "root");
	push (@paths,"");

	while (scalar @nodes>0){ #the node array is not empty
		#take the next element from the array
		my %curr = %{shift (@nodes)};
		my $parent = shift (@parents);
		my $path = shift (@paths);
		#check the child nodes
		foreach (keys %curr){
			next if (exists $elementToSkip{$_});
			#the attribute is straightforward, looking for use 
			if ($_ eq "xs:attribute"){#Attributes are optional by default. To specify that the attribute is required, use the "use" attribute e.g. <xs:attribute name="lang" type="xs:string" use="required"/>
				if (exists $curr{$_}{use} && $curr{$_}{use} eq "required"){
					$path = substr($path,2) if(substr($path,0,2) eq "::");#remove the first :: as $path initialized as "", then "$path::$_"
#					print OUT "$xsdFile\tattribute\t$curr{$_}{name}\tNA\t$path\n";
					$result{$path}{$curr{$_}{name}}{type}="NA";
					$result{$path}{$curr{$_}{name}}{desc} = $curr{$_}{"xs:annotation"}{"xs:documentation"} if (exists $curr{$_}{"xs:annotation"} && exists $curr{$_}{"xs:annotation"}{"xs:documentation"});
				}
				next;
			}
			# the value of name attribute in the elements (the thing this script is designed to extract) can be represented in two ways:
			# 1. as the node (dealt with by several lines below) and 2. the value for the key "name" under the node of "xs:element" (dealt with by the lines directly below) 
			if ($_ eq "xs:element"){
				if(exists $curr{$_}{name}){
					unless (exists $curr{$_}{minOccurs} && $curr{$_}{minOccurs} eq "0"){
						$path = substr($path,2) if(substr($path,0,2) eq "::");#remove the first :: as $path initialized as "", then "$path::$_"
#						print OUT "$xsdFile\telement\t$curr{$_}{name}\t";
						my $type = "";
						if (exists $curr{$_}{type}){
#							print OUT "$curr{$_}{type}";
							$type = "$curr{$_}{type}";
						}elsif(exists $curr{$_}{"xs:complexType"} || exists $curr{$_}{"xs:simpleType"}){
#							print OUT "inline type";
							$type = "inline type";
						}
#						print OUT "\t$path\n" ;
						$result{$path}{$curr{$_}{name}}{type}=$type;
						$result{$path}{$curr{$_}{name}}{desc} = $curr{$_}{"xs:annotation"}{"xs:documentation"} if (exists $curr{$_}{"xs:annotation"} && exists $curr{$_}{"xs:annotation"}{"xs:documentation"});
					}
				}
			}
			my $currPath = $path;
			$currPath = "$path::$_" unless (substr($_,0,3) eq "xs:");
			#depends on the type of the value
			my $value = $curr{$_};
			my $ref = ref($value);
			if ($ref eq ""){ #scalar, means reaching a leaf node, nothing needs to be done 
#				print "scalar\t$value\n";
			}elsif($ref eq "ARRAY"){ # ref of array, in this scenario, so far only one level of arrays is observed
				my @arr = @{$value};
				foreach my $a(@arr){
					if (ref($a) eq "HASH"){
#						print "array ref: $_\n";
						push (@nodes,$a);
						push (@parents, $_);
						push (@paths, $currPath);
					}
				}
			}elsif($ref eq "HASH"){ #ref of hashes, need to add child nodes into to-do node list
				if(exists $curr{$_}{minOccurs} && $curr{$_}{minOccurs} eq "0"){
					#print "optional $_\n";
				}else{
					push (@nodes,$curr{$_});
					push (@parents, $_);
					push (@paths, $currPath);
					unless (substr($_,0,3) eq "xs:"){
						if ($parent eq "xs:element"){
							$path = substr($path,2) if(substr($path,0,2) eq "::");#remove the first :: as $path initialized as "", then "$path::$_"
							my $type = "";
#							print OUT "$xsdFile\telement\t$_\t";
							if (exists $curr{$_}{type}){
#								print OUT "$curr{$_}{type}";
								$type = "$curr{$_}{type}";
							}elsif(exists $curr{$_}{"xs:complexType"} || exists $curr{$_}{"xs:simpleType"}){
#								print OUT "inline type";
								$type = "inline type";
							}
#							print OUT "\t$path\n" ;
							$result{$path}{$_}{type} = $type;
							$result{$path}{$_}{desc} = $curr{$_}{"xs:annotation"}{"xs:documentation"} if (exists $curr{$_}{"xs:annotation"} && exists $curr{$_}{"xs:annotation"}{"xs:documentation"});
						}
					}
				}
			}else{ #should not happen
				print "Unrecognized\n";
			}
		}
	}
#	print Dumper(\%result);return;
	#some xsd files use types defined in the SRA.common.xsd
	if ($xsdFile eq $COMMON_XSD){
		%typesInCommon = %result;
	}
	#in the %result, there are three types: 
	#1) elements at the root level in the xsd file (under key '')
	#2) type defined separated (under multiple keys having the name of types) 
	#3) sub_elements defined in root level elements (under multiple keys having the name containing ::) 
	my @sub_elements;
	foreach my $elmt(keys %result){
		next if ($elmt eq "");
		my $len = scalar (split ("::",$elmt));
		if ($len>1){
			push (@sub_elements,$elmt);
		}
	}
#	print Dumper(\@sub_elements);
	my %type_element_mapping;
	my @toPrint;
	#for every element at the root level
	foreach my $root_level_element(keys %{$result{""}}){
		my @todo;
		my @parents;
		my @types;
		my $type = $result{""}{$root_level_element}{type};
		my $desc = "";
		$desc = $result{""}{$root_level_element}{desc} if (exists $result{""}{$root_level_element}{desc});
#		print "$root_level_element with type $type\n";next;
		push (@toPrint,&printEntity($xsdFile,$root_level_element,$type,"",$desc));

		if (exists $result{$type}){
			$type_element_mapping{$type}{$root_level_element}=1;
			foreach my $element_in_type(keys %{$result{$type}}){
				push (@todo, $element_in_type);
				push (@parents, $type); 
				push (@types, $result{$type}{$element_in_type}{type});
			}

			while (scalar @todo>0){
				my $curr = shift @todo;
				my $parent = shift @parents;
				my $type = shift @types;

				push (@toPrint,&printEntity($xsdFile,$curr, $type,$parent));
				if ($type eq "inline type"){
					my $toMatch="$parent::$curr";
					my @candidates;
					my $maxLen = -1;
					foreach my $candidate(@sub_elements){
						my $idx = rindex($toMatch,$candidate);
						if ($idx>-1){
							my $len = length $toMatch;
							my $canLen = length $candidate;
							$maxLen = $canLen if ($canLen > $maxLen);
							if(($canLen+$idx)==$len){#match at the end
								push (@candidates,$candidate);
							}
						}
					}
					foreach my $candidate(@candidates){
						if (length $candidate == $maxLen){
							my %hash = %{$result{$candidate}};
							foreach my $name (keys %hash){
								unshift (@todo, $name);
								unshift (@parents, $toMatch);
								unshift (@types, $hash{$name}{type});
							}
						}
					}
				}elsif($type=~/^com:/){#the type refers to the type defined in SRA.common.xsd
					my $actualType = $';
#					print "$actualType\n";
#					print "found in common\n" if (exists $typesInCommon{$actualType});
				}elsif($type=~/^xs:/){#the primitive type, e.g. xs:int
				}else{#the type defined separately
					if (exists $result{$type}){
						$type_element_mapping{$type}{$curr}=1;
						foreach my $element_in_type(keys %{$result{$type}}){
							push (@todo, $element_in_type);
							push (@parents, "$parent::$type"); 
							push (@types, $result{$type}{$element_in_type}{type});
						}
					}
				}
			}
		}
		push (@toPrint,"");
	}

#	print Dumper(\%type_element_mapping);
	foreach my $line(@toPrint){
		if ($line eq ""){
			print OUT "\n";
			next;
		}
		my @tmp = split("\t",$line);
		my @arr = split("::",$tmp[3]);
		my $str = "";
		foreach my $elmt(@arr){
			if (exists $type_element_mapping{$elmt}){
				my @names = sort {$a cmp $b} keys %{$type_element_mapping{$elmt}};
				my $abc = join("\|",@names);
				$str .= "::$abc";
			}else{
				$str .= "::$elmt";
			}
		}
		$str = substr($str,2);
		$tmp[3] = $str;
		$line = join("\t",@tmp);
		print OUT "$line\n";
		&saveIntoJson($line);
#		print "$line\n";
	}
}

sub printEntity(){
	my ($xsd,$name,$type,$parent,$desc)=@_;
	my $result = "$xsd\t";
	if ($type eq "NA"){
		$result .= "attribute\t$name\t";
	}else{
		$result .= "element\t$name\t";
	}
	if ($desc =~/^\s+/){
		$desc = $';
	}
	if ($desc =~/\s+$/){
		$desc = $`;
	}
	$desc =~s/\n//g;
	$desc =~s/\t/ /g;
	$desc =~s/ +/ /g;
	$result .= "$parent\t$desc\t";
	if ($type=~/^com:/){
		$type = $';
		$xsd = $COMMON_XSD;
	}
	if (exists $cv_values{$xsd}{$type}){
		$result .= $cv_values{$xsd}{$type};
	}elsif (exists $cv_values{$xsd}{$name}){
		$result .= $cv_values{$xsd}{$name};
	}
	return $result;
}

sub saveIntoJson(){
	my $input = $_[0];
	my ($xsd,$type,$name,$path,$desc,$value) = split("\t",$input);
	my %hash;
	$hash{name}=$name;
	$hash{path}=$path;
	$hash{desc}=$desc if (length $desc>0);
	if(length $value>0){
		my @arr = split(/\|/,$value);
		@{$hash{allowed_values}}=@arr;
	}
	push(@{$json_result{$xsd}{$type}},\%hash);
}

sub usage(){
	print "Usage: perl parseMandatoryFieldsInENAxsdFiles.pl <allowed values list>\n";
	exit 1;
}
