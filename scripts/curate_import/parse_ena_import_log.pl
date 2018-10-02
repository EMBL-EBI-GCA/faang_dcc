#parse the sample import log file to summarize the error type etc. 
#the log is mainly printed by        
#print ERR "$biosampleId\t$validationResult{$ruleset}{detail}{$biosampleId}{type}\terror\t$validationResult{$ruleset}{detail}{$biosampleId}{message}\n";
use strict;
use Data::Dumper;
require "misc.pl";

my $include_warning = 0; #1 means include warning, while 0 means exclude warning
my $output_all_submissions = 0; #1 means output every submission even there is no error

my $es_host = "http://ves-hx-e4:9200/faang/dataset/_search?size=100";
my %datasets = &getDatasets($es_host);
#my %datasets;
open IN, $ARGV[0];
my %errors;

my %exps_in_dataset;
#parse the local import error log file
while (my $line =<IN>){
	chomp($line);
	my ($exp_id,$dataset_id,undef,$overall,$detail) = split("\t",$line);
	push (@{$exps_in_dataset{$dataset_id}},$exp_id);
	next unless ($overall eq "error" || $include_warning == 1); #continue only if error or set to include warnings
	my @errors = split(";",$detail);
	my %msgs;#use hash to avoid duplicate error in the same experiment record
	foreach my $error(@errors){
		#one error message is in the format of (WARNING)id_number:attribute not in rule set
		#category either error or warning, msg in the form of field_name:error_detail
		my ($category,$msg) = split(/\)/,$error);
		$category = substr($category,1);#remove the starting (

		next if (lc($category) eq "warning" && $include_warning == 0);
		$msgs{$msg} = lc($category);
	}
	if (scalar keys %msgs > 0){
		#separate error message into error or warning (when include_warning = 0, do not deal with them)
		foreach my $msg (keys %msgs){
			push (@{$errors{$exp_id}{$msgs{$msg}}},$msg);
		}
	}
}
#print Dumper(\%errors);
#exit;
#generate submission error report
$"=", ";
my $count = 0;
foreach my $dataset(sort {$a cmp $b} keys %datasets){
	next if ($datasets{$dataset}{standardMet} eq 'FAANG'); #meet the standard, no need to worry about errors
	delete $exps_in_dataset{$dataset};
	my $str = "ENA Study id: $dataset\n";
	$str .= "Secondary accession: $datasets{$dataset}{secondaryAccession}\n";
	$str .= "Title: $datasets{$dataset}{title}\n";
	$str .= &printArray($dataset,"species", "Animals");
	$str .= &printArray($dataset,"instrument", "Instruments");
	$str .= &printArray($dataset,"centerName", "Centres");
	$count++;

	my %error_type;
	foreach my $one (@{$datasets{$dataset}{experiment}}){
		my $exp_id = $$one{accession};
		%error_type = &add_error($exp_id,\%error_type);
	}

	if (scalar keys %error_type > 0 || $output_all_submissions == 1){
		print "$str\n";
	}
	&printErrors(\%error_type);
}

print "Datasets not imported into data portal:\n";
foreach my $dataset_id(sort {$a cmp $b} keys %exps_in_dataset){
	print "ENA Study id: $dataset_id\n";
	my %error_type;
	my @exps = @{$exps_in_dataset{$dataset_id}};
	foreach my $exp_id(@exps){
		%error_type = &add_error($exp_id,\%error_type);
	}
	&printErrors(\%error_type);
}

sub printErrors(){
	my %error_type = %{$_[0]};
	if (scalar keys %error_type > 0 || $output_all_submissions == 1){
		foreach my $error(keys %error_type){
			my ($type, $field, $detail) = split(":",$error);
			print "List of fields that are in $type: $field\nSummary of $type: $detail\n";
			my @tmp = sort keys %{$error_type{$error}};
			print "Affected experiment records: @tmp\n\n";
		}
		print "\n\n\n";
	}
}

sub add_error(){
	my ($exp_id,$hashref) = @_;
	my %error_type = %$hashref;
	#some records are totally valid
	return %error_type unless (exists $errors{$exp_id});
	my @errors = @{$errors{$exp_id}{error}};
	foreach my $msg(@errors){
		$error_type{"error:$msg"}{$exp_id}=1;
	}
	if ($include_warning == 1){
		foreach my $msg (@{$errors{$exp_id}{warning}}){
			$error_type{"warning:$msg"}{$exp_id}=1;
		}
	}
	return %error_type;
}

sub printArray(){
	my ($dataset,$key,$display) = @_;
	my @data = ();

	if (exists $datasets{$dataset}{$key}){
		foreach my $one(@{$datasets{$dataset}{$key}}){
			if(ref($one) eq 'HASH'){
				push (@data, $$one{text});
			}else{
				push (@data, $one);
			}
		}
	}
	return "$display: @data\n";
}

sub getDatasets(){
#	print "$_[0]\n";
	my $fh;
	my $json_text = &fetch_json_by_url($_[0]);
#	print "Total: $$json_text{hits}{total}\n";
	my @datasets = @{$$json_text{hits}{hits}};
	my %result;
	foreach my $one(@datasets){
		my %dataset = %{$$one{'_source'}};
		my $dataset_id = $$one{'_id'};
		%{$result{$dataset_id}} = %dataset;
	}
  return %result;
}
