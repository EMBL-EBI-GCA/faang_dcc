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

my $baseUrl = 'https://rawgithub.com/enasequence/schema/master/src/main/resources/uk/ac/ebi/ena/sra/schema/';

my $xmlReader = new XML::Simple;

my %elementToSkip;
#known elements definitely do NOT contain any attribute or element as its child nodes
my @elementToSkip = qw/xs:import xs:annotation xs:documentation xmlns:com xmlns:xs xs:restriction/;
foreach (@elementToSkip){
	$elementToSkip{$_} = 1;
}

my $numArg = scalar @ARGV;
&usage() unless ($numArg == 0);
$"="\t";
#&parseXSD("SRA.sample.xsd");
#&parseXSD("SRA.study.xsd");
#&parseXSD("SRA.common.xsd");
#&parseXSD("SRA.submission.xsd");
#exit;

#list of xsd files to check
my @xsdFiles = qw/SRA.experiment.xsd SRA.run.xsd SRA.sample.xsd SRA.study.xsd SRA.submission.xsd SRA.common.xsd/;

open OUT, ">mandatoryFieldsInENAxsdFiles.tsv";
print OUT "xsd file\ttype\tname\telement type\tpath\n";
#print "deleting all existing xsd files to make sure the xsd file parsed are up-to-date\n";
#system ("rm *.xsd");

foreach my $xsdFile(@xsdFiles){
	&checkXSDfile($xsdFile);
	&parseXSD($xsdFile);
}
close OUT;

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
					$path = substr($path,2) if((length $path)>0);#remove the first :: as $path initialized as "", then "$path::$_"
					print OUT "$xsdFile\tattribute\t$curr{$_}{name}\tNA\t$path\n";
				}
				next;
			}
			# the value of name attribute in the elements (the thing this script is designed to extract) can be represented in two ways:
			# 1. as the node (dealt with by several lines below) and 2. the value for the key "name" under the node of "xs:element" (dealt with by the lines directly below) 
			if ($_ eq "xs:element"){
				if(exists $curr{$_}{name}){
					unless (exists $curr{$_}{minOccurs} && $curr{$_}{minOccurs} eq "0"){
						$path = substr($path,2) if((length $path)>0);#remove the first :: as $path initialized as "", then "$path::$_"
						print OUT "$xsdFile\telement\t$curr{$_}{name}\t" ;
						if (exists $curr{$_}{type}){
							print OUT "$curr{$_}{type}";
						}elsif(exists $curr{$_}{"xs:complexType"} || exists $curr{$_}{"xs:simpleType"}){
							print OUT "inline type";
						}
						print OUT "\t$path\n" ;
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
							$path = substr($path,2) if((length $path)>0);#remove the first :: as $path initialized as "", then "$path::$_"
							print OUT "$xsdFile\telement\t$_\t";
							if (exists $curr{$_}{type}){
								print OUT "$curr{$_}{type}";
							}elsif(exists $curr{$_}{"xs:complexType"} || exists $curr{$_}{"xs:simpleType"}){
								print OUT "inline type";
							}
							print OUT "\t$path\n" ;
						}
					}
				}
			}else{ #should not happen
				print "Unrecognized\n";
			}
		}
	}
}

sub usage(){
	print "Usage: perl parseMandatoryFieldsInENAxsdFiles.pl\n";
	exit 1;
}
