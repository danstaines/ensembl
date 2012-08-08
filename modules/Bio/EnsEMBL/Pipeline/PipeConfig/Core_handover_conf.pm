package Bio::EnsEMBL::Pipeline::PipeConfig::Core_handover_conf;

use strict;
use warnings;

use base ('Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf');

use Bio::EnsEMBL::ApiVersion qw/software_version/;

sub default_options {
    my ($self) = @_;
    
    return {
        # inherit other stuff from the base class
        %{ $self->SUPER::default_options() }, 
        
        ### OVERRIDE
        
        ### Optional overrides        
        species => [],
        
        release => software_version(),

        run_all => 0,

        bin_count => '150',

        max_run => '100',
        
        ### Defaults 
        
        pipeline_name => 'core_handover_update_'.$self->o('release'),
        
        email => $self->o('ENV', 'USER').'@sanger.ac.uk',
    };
}

sub pipeline_create_commands {
    my ($self) = @_;
    return [
      # inheriting database and hive tables' creation
      @{$self->SUPER::pipeline_create_commands}, 
    ];
}

## See diagram for pipeline structure 
sub pipeline_analyses {
    my ($self) = @_;
    
    return [
    
      {
        -logic_name => 'ScheduleSpecies',
        -module     => 'Bio::EnsEMBL::Pipeline::Production::ClassSpeciesFactory',
        -parameters => {
          species => $self->o('species'),
          run_all => $self->o('run_all'),
          max_run => $self->o('max_run')

        },
        -input_ids  => [ {} ],
        -flow_into  => {
          1 => 'Notify',
          2 => ['GeneGC', 'PepStats', 'GeneCount', 'ConstitutiveExons'],
          3 => ['PercentGC', 'PercentRepeat', 'CodingDensity', 'NonCodingDensity', 'PseudogeneDensity'],
        },
      },

      {
        -logic_name => 'ConstitutiveExons',
        -module     => 'Bio::EnsEMBL::Pipeline::Production::ConstitutiveExons',
        -parameters => {
          dbtype => 'core',
        },
        -max_retry_count  => 5,
        -hive_capacity    => 100,
        -rc_name          => 'normal',
      },

      {
        -logic_name => 'PepStats',
        -module     => 'Bio::EnsEMBL::Pipeline::Production::PepStats',
        -parameters => {
          tmpdir => '/tmp', binpath => '/software/pubseq/bin/emboss',
          dbtype => 'core',
        },
        -max_retry_count  => 5,
        -hive_capacity    => 100,
        -rc_name          => 'mem',
      },

      {
        -logic_name => 'GeneCount',
        -module     => 'Bio::EnsEMBL::Pipeline::Production::GeneCount',
        -max_retry_count  => 1,
        -hive_capacity    => 100,
        -rc_name          => 'normal',
      },

      {
        -logic_name => 'NonCodingDensity',
        -module     => 'Bio::EnsEMBL::Pipeline::Production::NonCodingDensity',
        -parameters => {
          logic_name => 'noncodingdensity', value_type => 'sum',
          bin_count => $self->o('bin_count'), max_run => $self->o('max_run'),
        },
        -max_retry_count  => 1,
        -hive_capacity    => 100,
        -rc_name          => 'normal',
        -can_be_empty     => 1,
        -wait_for         => ['GeneGC', 'CodingDensity'],
      },

      {
        -logic_name => 'PseudogeneDensity',
        -module     => 'Bio::EnsEMBL::Pipeline::Production::PseudogeneDensity',
        -parameters => {
          logic_name => 'pseudogenedensity', value_type => 'sum',
          bin_count => $self->o('bin_count'), max_run => $self->o('max_run'),
        },
        -max_retry_count  => 1,
        -hive_capacity    => 100,
        -rc_name          => 'normal',
        -can_be_empty     => 1,
        -wait_for         => ['ConstitutiveExons', 'NonCodingDensity', 'CodingDensity'],
      },

      {
        -logic_name => 'CodingDensity',
        -module     => 'Bio::EnsEMBL::Pipeline::Production::CodingDensity',
        -parameters => {
          logic_name => 'codingdensity', value_type => 'sum',
          bin_count => $self->o('bin_count'), max_run => $self->o('max_run'),
        },
        -max_retry_count  => 1,
        -hive_capacity    => 100,
        -rc_name          => 'normal',
        -can_be_empty     => 1,
      },

      {
        -logic_name => 'GeneGC',
        -module     => 'Bio::EnsEMBL::Pipeline::Production::GeneGC',
        -max_retry_count  => 1,
        -hive_capacity    => 100,
        -rc_name => 'normal',
      },

      {
        -logic_name => 'PercentGC',
        -module     => 'Bio::EnsEMBL::Pipeline::Production::PercentGC',
        -parameters => {
          table => 'repeat', logic_name => 'percentgc', value_type => 'ratio',
          bin_count => $self->o('bin_count'), max_run => $self->o('max_run'),
        },
        -max_retry_count  => 1,
        -hive_capacity    => 100,
        -rc_name          => 'normal',
        -can_be_empty     => 1,
        -wait_for         => ['PercentRepeat'],
      },

      {
        -logic_name => 'PercentRepeat',
        -module     => 'Bio::EnsEMBL::Pipeline::Production::PercentRepeat',
        -parameters => {
          logic_name => 'percentagerepeat', value_type => 'ratio',
          bin_count => $self->o('bin_count'), max_run => $self->o('max_run'),
        },
        -max_retry_count  => 1,
        -hive_capacity    => 100,
        -rc_name          => 'mem',
        -can_be_empty     => 1,
        -wait_for         => ['CodingDensity', 'NonCodingDensity', 'PseudogeneDensity'],
      },

      ####### NOTIFICATION
      
      {
        -logic_name => 'Notify',
        -module     => 'Bio::EnsEMBL::Pipeline::Production::EmailSummaryCore',
        -parameters => {
          email   => $self->o('email'),
          subject => $self->o('pipeline_name').' has finished',
        },
        -wait_for   => ['PepStats', 'GeneGC', 'PercentGC', 'PercentRepeat', 'CodingDensity', 'PseudogeneDensity', 'NonCodingDensity', 'GeneCount', 'ConstitutiveExons'],
      }
    
    ];
}

sub pipeline_wide_parameters {
    my ($self) = @_;
    
    return {
        %{ $self->SUPER::pipeline_wide_parameters() },  # inherit other stuff from the base class
        release => $self->o('release'),
    };
}

# override the default method, to force an automatic loading of the registry in all workers
sub beekeeper_extra_cmdline_options {
    my $self = shift;
    return "-reg_conf ".$self->o("registry");
}

sub resource_classes {
    my $self = shift;
    return {
      'default' => { 'LSF' => '-q normal -M 500000 -R"select[mem>500 && myens_stag1tok>800 && myens_stag2tok>800] rusage[mem=500:myens_stag1tok=10:myens_stag2tok=10:duration=10]"'},
      'normal'  => { 'LSF' => '-q normal -M 1000000 -R"select[mem>1000 && myens_stag1tok>800 && myens_stag2tok>800] rusage[mem=1000:myens_stag1tok=10:myens_stag2tok=10:duration=10]"'},
      'mem'     => { 'LSF' => '-q normal -M 1500000 -R"select[mem>1500 && myens_stag1tok>800 && myens_stag2tok>800] rusage[mem=1500:myens_stag1tok=10:myens_stag2tok=10:duration=10]"'},
    }
}

1;