#
# BioPerl module for Bio::EnsEMBL::Utils::GTF_handler
#
# Cared for by Elia Stupka <elia@sanger.ac.uk>
#
# Copyright Elia Stupka
#
# You may distribute this module under the same terms as perl itself

# POD documentation - main docs before the code

=head1 NAME

Bio::EnsEMBL::Utils::GTF_handler - Comparison of two clones

=head1 SYNOPSIS

    GTF_handler->new();

    #To parse a GTF file, build genes, and write them to a db
    GTF_handler->parse_file($file);

    #To dump genes in GTF format
    GTF_handler->dump_genes($file,@genes);

=head1 DESCRIPTION

This module is a handler for the GTF format, i.e. a GTF parser and dumper.

Dumping genes is done simply by calling the dump_genes method and passing an
array of genes and a filhandle.

Parsing GTF files is done in three steps, first parsing a file, then mapping
golden path coordinates to ensembl coordinates, and finally writing genes to a database.

=head1 CONTACT

Ensembl - ensembl-dev@ebi.ac.uk

=cut

package Bio::EnsEMBL::Utils::GTF_handler;

use strict;
use vars qw(@ISA);
use Bio::Root::RootI;
use Bio::EnsEMBL::Gene;
use Bio::EnsEMBL::Transcript;
use Bio::EnsEMBL::Translation;
use Bio::EnsEMBL::Exon;


@ISA = qw(Bio::Root::RootI);

=head2 new

 Title   : new
 Usage   : GTF_handler->new()
 Function: Constructor
 Example : 
 Returns : Reference to an object
 Args    : 

=cut

sub new {
    my ($class, @args) = @_;
    my $self = bless {}, $class;
    $self->{'_gene_array'} = [];
    $self->{'_transcript_array'} = [];
    return $self;
}

=head2 parse_file

 Title   : parse_file
 Usage   : GTF_handler->parse_file(filename)
 Function: Parses a GTF file, reading in features
 Example : GTF_handler->parse_file(gens.gtf)
 Returns : array of Bio::EnsEMBL::Gene objects
 Args    : name of the file

=cut

sub parse_file {
    my ($self,$fh) = @_;

    $fh || $self->throw("You have to pass a filehandle in order to parse a file!");
    
    my @genes;
    my $oldgene;
    my $oldtrans;
    my $flag=1;
    my %exons;
    my $trans_start;
    my $trans_end;
    my $type;

    while( <$fh> ) {
	(/^\#/) && next;
	(/^$/) && next;
	my ($contig,$source,$feature,$start,$end,$score,$strand,$frame);
	my ($gene_name, $gene_id,$transcript_id,$exon_num,$exon_id);

	#First we have to be able to parse the basic feature information
	if (/^(\w+)\s+(\w+)\s+(\w+)\s+(\d+)\s+(\d+)\s+(.)\s+(.)\s+(.)/){
	    $contig=$1;
	    $type=$2;
	    $feature=$3;
	    $start=$4;
	    $end=$5;
	    $score=$6;
	    $strand=$7;
	    $frame=$8;
	}
	#This allows us to parse gtf entries starting with a rawcontig id
	elsif (/^(\w+\.\w+)\s+(\w+)\s+(\w+)\s+(\d+)\s+(\d+)\s+(.)\s+(.)\s+(.)/){
	    $contig=$1;
	    $type=$2;
	    $feature=$3;
	    $start=$4;
	    $end=$5;
	    $score=$6;
	    $strand=$7;
	    $frame=$8;
	}
	#This was a sneaky patch for parsing badly formed ensembl gtf files...
	#elsif (/^(\w+)\s+(\w+)\s+(\w+)\s+(\d+)\s+(0)\s+(0)/){
	    #$contig=$1;
	    #$source=$2;
	    #$feature=$3;
	    #$start=$end-3;
	    #$end=$5;
	    #$score=$6;
	    #$strand='+';
	    #$frame=$8;
	    #$type="ENS";
	#}
	#Another very sneaky patch!
	#elsif (/^\s+(\w+)\s+(\w+)\s+(\d+)\s+(0)\s+(0)/){
	    #$contig='xxx';
	    #$source=$2;
	    #$feature=$3;
	    #$start=$end-3;
	    #$end=$5;
	    #$score=$6;
	    #$strand='+';
	    #$frame=$8;
	    #$type="ENS";
	#}
	else {
	    $self->warn("Could not parse line:\n$_");
	}

	if ($strand eq '-') {
	    $strand = -1;
	}
	elsif ($strand eq '+') {
	    $strand =1;
	}
	else {
	    die("Parsing error! Exon with strand $strand");
	}
	   

	if (/gene_name \"(\w+)\"/) { 
	    $gene_name=$1; 
	}

	if (/transcript_id \"(.+)\"/) { 
	    $transcript_id = $1;
	}
	
        #this variant is for NCBI files...
	elsif (/transcript_id\s+(.+)\; exon/) {
	    $transcript_id = $1;
	} 
	elsif (/transcript_id\s+(.+)\;/) { 
	    $transcript_id = $1;
	}
        else { 
	    $self->warn("Cannot parse line without transcript id, skipping!\nLine:$_");
	    next;
	}
	if (/gene_id \"(.+)\".+transcript/) { 
	    $gene_id = $1;
	}
	elsif (/gene_id (\d+)\;/) {
	    $gene_id=$1;
	}
	else { 
	    #NCBI files don't have a gene id
	    $gene_id= $transcript_id;
	    #$self->warn("Cannot parse line without gene id, skipping!");
	    #next;
	}
	if (/exon_number (\d+)/) { $exon_num = $1;}
	if (/Exon_id (.+)\;/) { $exon_id = $1;}
	
	if ($flag == 1) {
	    $oldtrans = $transcript_id;
	    $oldgene = $gene_id;
	    $flag=0;
	}

	#When new gene components start, do the gene building 
	#with all the exons found up to now, start_codon and end_codon
	
	if ($oldtrans ne $transcript_id) {
	    my $gene=$self->_build_transcript($trans_start,$trans_end,$oldtrans,%exons);
	    $trans_start = undef;
	    $trans_end = undef;
	    %exons = ();
	}
	if ($oldgene ne $gene_id) {
	    $self->_build_gene($oldgene);
	}
	
	if ($feature eq 'exon') {
	   
	    my $exon = Bio::EnsEMBL::Exon->new($start,$end,$strand);
	    if ($exon_id) {
		$exon->id($exon_id);
	    } 
	    else {
		my $id = "$type-$gene_id-$exon_num";
		$exon->id($id);
	    }
	    $exon->version(1);
	    $exon->contig_id($contig);
	    $exon->seqname($contig);
	    $exon->sticky_rank(1);
	    my $time = time; chomp($time);
	    $exon->created($time);
	    $exon->modified($time);
	    $exons{$exon_num}=$exon;
	}
	elsif ($feature eq 'start_codon') {
	    $trans_start=$start;
	}
	elsif ($feature eq 'stop_codon') {
	    $trans_end=$end;
	}
	else {
	    #print STDERR "Feature $feature not parsed\n";
	}
	$oldgene=$gene_id;
	$oldtrans=$transcript_id;
	print STDERR "Contig: $contig\nSource: $type\nFeature: $feature\nStart: $start\nEnd: $end\nScore: $score\nStrand: $strand\nFrame: $frame\nGene name: $gene_name\nGene id: $gene_id\nTranscript id: $transcript_id\nExon number: $exon_num\n\n";
    }
    $self->_build_transcript($trans_start,$trans_end,$oldtrans,%exons);
    my $gene = $self->_build_gene($oldgene);
    return  @{$self->{'_gene_array'}};
}

=head2 _build_gene

 Title   : _build_gene
 Usage   : GTF_handler->_build_gene()
 Function: Internal method used to build a gene using an internal array
           of transcripts
 Example : 
 Returns : a Bio::EnsEMBL::Gene object
 Args    : hash of exons, int translation start, int translation end, 
           old gene id
=cut

sub _build_gene {
    my ($self,$oldgene) = @_;

    my $trans_number= scalar(@{$self->{'_transcript_array'}});

    #Only build genes if there are transcripts in the trans array
    #If translation start/end were not found, no transcript would be built!
    if ($trans_number > 1) {
	#print STDERR "Got multiple transcripts for gene $oldgene\n";
    }
    if ($trans_number) {
	my $gene=Bio::EnsEMBL::Gene->new();
	$gene->id($oldgene);
	$gene->version(1);
	my $time = time; chomp($time);
	$gene->created($time);
	$gene->modified($time);
	foreach my $transcript (@{$self->{'_transcript_array'}}) {
	    $gene->add_Transcript($transcript);
	}
	$self->{'_transcript_array'}=[];
	$gene && push(@{$self->{'_gene_array'}},$gene);
    }
}

=head2 _build_transcript

 Title   : _build_transcript
 Usage   : GTF_handler->_build_transcript($trans_start,$trans_end,
           $oldtrans,%exons)
 Function: Internal method used to build a transcript using a hash of 
           exons, translation start and translation end
 Example : 
 Returns : a Bio::EnsEMBL::Transcript object
 Args    : hash of exons, int translation start, int translation end, 
           old gene id
=cut

sub _build_transcript {
    my ($self,$trans_start,$trans_end,$oldtrans,%exons)=@_;

    #Create transcript, translation, and assign phases to exons

    my $trans = Bio::EnsEMBL::Transcript->new;
    my $translation = Bio::EnsEMBL::Translation->new;
    $translation->id($oldtrans);
    $translation->version(1);
    $trans->id($oldtrans);
    $trans->version(1);
    my $time = time; chomp($time);
    $trans->created($time);
    $trans->modified($time);
    if (!defined($trans_start)) {
	$self->warn("Could not find translation start for transcript $oldtrans, skipping");
	return;
    }
    
    $translation->start($trans_start);
    
    if (!defined($trans_end)) {
	$self->warn("Could not find translation end for transcript $oldtrans, skipping");
	return;
    }
    my $phase=0;
    my $end_phase;
    foreach my $num (keys%exons) {

	#Positive strand
	if ($exons{$num}->strand == 1) {

	    #Start exon
	    if (($trans_start >= $exons{$num}->start)&&($trans_start<= $exons{$num}->end)) {
		#Assign start exon id
		$translation->start_exon_id($exons{$num}->id);

		#Phase for start exons is always zero (irrelevant)
		$phase=0;
		
		#Now calculate end_phase, used for next exon
		$end_phase=($exons{$num}->end-$trans_start+1)%3;
	    }

	    #All other exons
	    else {
		#Calculate the end_phase for all other exons
		my $mod_phase;
		
		if ($phase != 0){
		    $mod_phase=3-$phase;
		}
		$end_phase=($exons{$num}->length-$mod_phase)%3;
	    }

	    #Find the end exon id
	    if (($trans_end >= $exons{$num}->start)&&($trans_end <= $exons{$num}->end)) {
		$translation->end_exon_id($exons{$num}->id);
	    }
	}
	
	#Negative strand
	else {

	    #Start exon
	    if (($trans_start >= $exons{$num}->start)&&($trans_start <= $exons{$num}->end)) {
		#Assign the start_exon_id
		$translation->start_exon_id($exons{$num}->id);
		
		#Phase for start exons is always zero (irrelevant)
		$phase=0;
		
		#Calculate the end_phase, used for next exon
		$end_phase=($trans_start-$exons{$num}->start+1)%3;
	    }
	    
	    #All other exons
	    else {
		
		#Calculate end_phase
		my $mod_phase;
		if ($phase != 0){
		    $mod_phase=3-$phase;
		}
		$end_phase=($exons{$num}->length-$mod_phase)%3;
	    }

	    #Find the end exon id
	    if (($trans_end >= $exons{$num}->start)&&($trans_end <= $exons{$num}->end)) {
		$translation->end_exon_id($exons{$num}->id);
	    }

	}
	#print STDERR "Phase:   $phase\n";

	#Assign phase to exon
	$exons{$num}->phase($phase);

	#Add exon to transcript
	$trans->add_Exon($exons{$num});

	#Assign its end_phase to the next exon's phase
	$phase=$end_phase;
    }

    #This is somehow tight, but finds buggy gtf files!
    if (!defined($translation->start_exon_id)) {
	$self->warn("Could not find translation exon start for transcript $oldtrans, skipping");
	return;
    }
    
    if (!defined($translation->end_exon_id)) {
	$self->warn("Could not find translation exon end for transcript $oldtrans, skipping");
	return;
    }
   
    $translation->end($trans_end);
    $trans->translation($translation);
    push(@{$self->{'_transcript_array'}},$trans);
}

=head2 dump_genes

 Title   : dump_genes
 Usage   : GTF_handler->dump_genes($file,@genes)
 Function: Dumps genes to a GTF file
 Example : 
 Returns : 
 Args    : array of Bio::EnsEMBL::Gene objects

=cut

sub dump_genes {
    my ($self,$fh,@genes) = @_;
    
    print $fh "##gff-version 2\n##source-version EnsEMBL-Gff 1.0\n";
    print $fh "##date ".time()."\n";
    foreach my $gene (@genes) {
	
        #print STDERR "Dumping gene ".$gene->id."\n";
	foreach my $trans ($gene->each_Transcript) {
	    print STDERR "Dumping transcript ".$trans->id."\n";
	    my $c=1;
	    my $seen=0;
	    my $exon_string;
	    
	    my ($start,$start_end,$start_seqname,$start_strand,$start_exon_id);
	    if ($trans->translation->start) {
		$start=$trans->translation->start;
	    }
	    else {
		$self->warn("Translation does not have start for transcript ".$trans->id.", skipping!");
		next;
	    }
	    
	    if ($trans->translation->start_exon_id) {
		$start_exon_id=$trans->translation->start_exon_id;
	    }
	    else {
		$self->warn("Translation does not have start exon id for transcript ".$trans->id.", skipping!");
		next;
	    }

	    my ($end,$end_start,$end_seqname,$end_strand,$end_exon_id);
	    if ($trans->translation->end) {
		$end_start=$trans->translation->end;
	    }
	    else {
		$self->warn("Translation does not have end for transcript ".$trans->id.", skipping!");
		next;
	    }
	    
	    if ($trans->translation->end_exon_id) {
		$end_exon_id=$trans->translation->end_exon_id;
	    }
	    else {
		$self->warn("Translation does not have end exon id for transcript ".$trans->id.", skipping!");
		next;
	    }

	    #Loop through all exons to find start and end 
	    foreach my $exon ($trans->each_Exon) {
		my $score = "0";
		if ($exon->score) {
		    $score=$exon->score;
		}
		
		my $strand="+";
		if ($exon->strand == -1) {
		    $strand="-";
		}
		$exon_string .= $exon->contig_id."\tensembl\texon\t".$exon->start."\t".$exon->end."\t$score\t$strand\t0\tgene_id \"".$gene->id."\"\;\ttranscript_id \"".$trans->id."\"\;\texon_number ".$c."\n"; 
		
		$c++;
		if ($exon->id eq $start_exon_id) {
		    if ($exon->strand == -1) {
			$start_strand = "-";
			$start_end=$start-3;
		    }
		    else {
			$start_strand = "+";
			$start_end=$start+3;
		    }
		    $start_seqname=$exon->contig_id;
		    $seen++;
		}
		if ($exon->id eq $end_exon_id) {
		    if ($exon->strand == -1) {
			$end_strand = "-";
			$end=$end_start+3;
		    }
		    else {
			$end=$end_start-3;
			$end_strand="+";
		    }
		    $end_seqname=$exon->contig_id;
		    $seen++;
		}
	    }
	    if ($seen == 2) {
		print $fh $exon_string;
		print $fh "$start_seqname\tensembl\tstart_codon\t$start\t$start_end\t0\t$start_strand\t0\tgene_id \"".$gene->id."\"\;\ttranscript_id \"".$trans->id."\"\n";
		print $fh "$end_seqname\tensembl\tstop_codon\t$end\t$end_start\t0\t$end_strand\t0\tgene_id \"".$gene->id."\"\;\ttranscript_id \"".$trans->id."\"\;\n";
	    }
	    else {
		$self->warn("Could not find start and/or end exon for transcript ".$trans->id.", skipping!");
	    }
	}
    }
}
=head2 print_genes

 Title   : print_genes
 Usage   : GTF_handler->print_genes(@genes)
 Function: Prints gene structures to STDOUT (for tests)
 Example : 
 Returns : nothing
 Args    : 

=cut

sub print_genes {
    my ($self) = @_;
    
    my @genes= @{$self->{'_gene_array'}};

    foreach my $gene (@genes) {
	print STDOUT "Gene ".$gene->id."\n";
	foreach my $trans ($gene->each_Transcript) {
	    print STDOUT "  Transcript ".$trans->id."\n";
	    foreach my $exon ($gene->each_unique_Exon) {
		print STDOUT "   exon ".$exon->id."\n";
	    }
	    print STDOUT "   translation start ".$trans->translation->start."\n";
	    print STDOUT "   translation end ".$trans->translation->end."\n";
	}
    }
}

