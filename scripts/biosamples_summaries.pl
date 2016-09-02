#!/usr/bin/env perl
use strict;
use warnings;

use Getopt::Long;

my ($biosamples_tsv, $summaryfile);

GetOptions(
  "biosamples_tsv=s"          => \$biosamples_tsv,
  "summaryfile=s"          => \$summaryfile,
);

die "Missing input and summary outfile paths" if !$biosamples_tsv || !$summaryfile;

open(BIOIN, '<', $biosamples_tsv) or die("Can't open ".$biosamples_tsv);
my @biosamples = <BIOIN>;
close BIOIN;
shift @biosamples;

my (%overview_material, %overview_centre, %organism_species, %organism_sex, %tissue_species, %tissue_organism_part, %cell_spec_species, %cell_spec_organism_part, %cell_cult_species, %cell_cult_organism_part);

foreach my $line (@biosamples){
  my @parts = split(/\t/, $line);
  my $material = $parts[4];
  my $centre = $parts[1];
  $overview_material{$material}++;
  $overview_centre{$centre}++;
  my $species = $parts[5];
  my $sex = $parts[6];
  my $organism_part = $parts[32];
  if ($material eq "organism"){
    $organism_species{$species}++;
    $organism_sex{$sex}++;
  }elsif ($material eq "tissue specimen"){
    $tissue_species{$species}++;
    $tissue_organism_part{$organism_part}++;
  }elsif ($material eq "cell specimen"){
    $cell_spec_species{$species}++;
    $cell_spec_organism_part{$organism_part}++;
  }elsif ($material eq "cell culture"){
    $cell_cult_species{$species}++;
    $cell_cult_organism_part{$organism_part}++;
  }
}


open(OUT, '>', $summaryfile) or die("Can't open ".$summaryfile);
print OUT "FAANG BioSample data summary\n\nSummary of FAANG project sample data held in the BioSamples database at EMBL-EBI.\n\n\nSample overview\n\n";
print_counts(%overview_material);
print OUT "\nInstitute\n";
print_counts(%overview_centre);
print OUT "\n\n\nSummary of Organism samples\n\nSpecies\n";
print_counts(%organism_species);
print OUT "\nSex\n";
print_counts(%organism_sex);
print OUT "\n\n\nSummary of Tissue specimen samples\n\nSpecies\n";
print_counts(%tissue_species);
print OUT "\nOrganism part\n";
print_counts(%tissue_organism_part);
print OUT "\n\n\nSummary of Cell specimen samples\n\nSpecies\n";
print_counts(%cell_spec_species);
print OUT "\nOrganism part\n";
print_counts(%cell_spec_organism_part);
print OUT "\n\n\nSummary of Cell culture samples\n\nSpecies\n";
print_counts(%cell_cult_species);
print OUT "\nOrganism part\n";
print_counts(%cell_cult_organism_part);

sub print_counts {
  my (%list) = @_;
  foreach my $item (reverse sort { $list{$a} <=> $list{$b} } keys %list) {
    printf OUT "%-31s %s\n", $item, $list{$item};
  }
}
close OUT;