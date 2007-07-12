package Bio::EnsEMBL::IdMapping::TinyGene;

=head1 NAME


=head1 SYNOPSIS


=head1 DESCRIPTION


=head1 METHODS


=head1 LICENCE

This code is distributed under an Apache style licence. Please see
http://www.ensembl.org/info/about/code_licence.html for details.

=head1 AUTHOR

Patrick Meidl <meidl@ebi.ac.uk>, Ensembl core API team

=head1 CONTACT

Please post comments/questions to the Ensembl development list
<ensembl-dev@ebi.ac.uk>

=cut


use strict;
use warnings;
no warnings 'uninitialized';

use Bio::EnsEMBL::IdMapping::TinyFeature;
our @ISA = qw(Bio::EnsEMBL::IdMapping::TinyFeature);

use Bio::EnsEMBL::Utils::Exception qw(throw warning);


sub start {
  my $self = shift;
  $self->[2] = shift if (@_);
  return $self->[2];
}


sub end {
  my $self = shift;
  $self->[3] = shift if (@_);
  return $self->[3];
}


sub strand {
  my $self = shift;
  $self->[4] = shift if (@_);
  return $self->[4];
}


sub seq_region_name {
  my $self = shift;
  $self->[5] = shift if (@_);
  return $self->[5];
}


sub biotype {
  my $self = shift;
  $self->[6] = shift if (@_);
  return $self->[6];
}


sub display_name {
  my $self = shift;
  $self->[7] = shift if (@_);
  return $self->[7];
}


sub add_Transcript {
  my $self = shift;
  my $tr = shift;

  unless ($tr && $tr->isa('Bio::EnsEMBL::IdMapping::TinyTranscript')) {
    throw('Need a Bio::EnsEMBL::IdMapping::TinyTranscript.');
  }

  push @{ $self->[8] }, $tr;
}


sub get_all_Transcripts {
  return $_[0]->[8] || [];
}


sub length {
  my $self = shift;
  return ($self->end - $self->start + 1);
}


1;

