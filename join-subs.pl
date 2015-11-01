#!/usr/bin/env perl
#===============================================================================
#       AUTHOR: dracorp <piotr.r.public@gmail.com>
#         DATE: $Date$
#     REVISION: $Revision$
#           ID: $Id$
#===============================================================================

use strict;
use warnings;

use Carp;
use English qw( -no_match_vars );
use Getopt::Long;
use Pod::Usage;
use File::Slurp;
use Data::Dumper;
use Video::Subtitle::SRT qw(:all);
use feature qw(:all);

our $VERSION = '0.1';

# Global variables for command line options
my $options = {};
my @files;

sub join_subtitles { #{{{
    #===  FUNCTION  ================================================================
    #         NAME: join_subtitles
    #      PURPOSE: joins two ( or more, todo) SRT subtitles into one in ASS format
    #   PARAMETERS: ref array[files]
    #      RETURNS: scalar(joined subtitles)
    #  DESCRIPTION: ????
    #       THROWS: no exceptions
    #     COMMENTS: none
    #     SEE ALSO: n/a
    #===============================================================================
    my $files = shift;

    if ( ref $files ne 'ARRAY' ) {
        croak "Argument for 'join_subtitles' must be ref to array of files";
    }

    # temporary hash used to obtain data from callback
    my $tmp_callback_hash;

    # callback for Video::Subtitle::SRT->parse
    my $callback = sub { #{{{
        my $data = shift;

        # $data->{number}     = number
        #       >{start_time} = '00:00:05,400'
        #       >{end_time}   = '00:00:09,100'
        #       >{text}       = subtitle

        $data->{text} =~ s/\n/\\N/g;
        my $start_time = srt_time_to_milliseconds( $data->{start_time} );

        # convert comma to dot, comma(,) is separator for ASS format
        $data->{start_time} =~ s/,(\d\d)\d/.$1/;
        $data->{end_time} =~ s/,(\d\d)\d/.$1/;
        
        $data->{start_time} =~ s/^0(\d)/$1/;
        $data->{end_time} =~ s/^0(\d)/$1/;
        # remove useless formating
        $data->{text} =~ s|</?i>||g;

        $tmp_callback_hash->{$start_time}->{start_time} = $data->{start_time};
        $tmp_callback_hash->{$start_time}->{end_time}   = $data->{end_time};
        $tmp_callback_hash->{$start_time}->{text}       = $data->{text};
    }; #}}}

    # joined subtitles in hash
    # $subs->{$index_of_file}->{file} = 'file name'
    #                         >{srt}->{$start_time}->{start_time} = 'start_time in SRT'
    #                                >{$start_time}->{end_time}   = 'end_time in SRT'
    #                                >{$start_time}->{text}       = 'text'
    my $subs = {};

    # above subtitles, unsorted, transformed to array
    # @subs->[ $start_time, $index, $subs->{$index}->{srt}->{$start_time}
    my @subs;

    # iterate by input files
    for my $index ( 0 .. $#{ $options->{files} } ) {
        my $file = $options->{files}->[$index];
        $tmp_callback_hash = {};
        my $srt = new Video::Subtitle::SRT($callback);
        $subs->{$index}->{file} = $file;
        eval {
            $srt->parse($file);
        };
        if ($EVAL_ERROR) {
            if ( $EVAL_ERROR =~ m/Number must be digits: '...1/ ) {
                say "Probably BOM in file '$file', TODO. You can use iconv program. See `man iconv` for more.";
            }
            say "Parsing the file '$file' failed: $EVAL_ERROR";
        }
        $subs->{$index}->{srt} = $tmp_callback_hash;

        # transform hash to array
        for my $start_time ( keys %{ $subs->{$index}->{srt} } ) {
            push @subs, [ $start_time, $index, $subs->{$index}->{srt}->{$start_time} ];
        }
    }

    # sort by start_time(ms) and then by index
    @subs = sort {
        if ( $a->[0] != $b->[0] ) {
            return $a->[0] <=> $b->[0];
        }
        else {
            return $a->[1] <=> $b->[1];
        }
    } @subs;

    # prepare returned text
    my @result;
    for my $line (@subs) {
        my $index = $line->[1];
        $index = $index ? 'Bot' : 'Top';
        my $start_time = $line->[2]->{start_time};
        my $end_time   = $line->[2]->{end_time};
        my $sub        = $line->[2]->{text};
        push @result, "Dialogue: 0,$start_time,$end_time,$index,,0000,0000,0000,,$sub";
    }
    my $result = <<EOT;
[Script Info]
ScriptType: v4.00+
Collisions: Normal
PlayDepth: 0
Timer: 100,0000
Video Aspect Ratio: 0
WrapStyle: 0
ScaledBorderAndShadow: no

[V4+ Styles]
Format: Name,Fontname,Fontsize,PrimaryColour,SecondaryColour,OutlineColour,BackColour,Bold,Italic,Underline,StrikeOut,ScaleX,ScaleY,Spacing,Angle,BorderStyle,Outline,Shadow,Alignment,MarginL,MarginR,MarginV,Encoding
Style: Default,Comic Sans MS,18,&H00FFFFFF,&H00FFFFFF,&H80000000,&H80000000,-1,0,0,0,100,100,0,0,1,3,0,2,10,10,10,0
Style: Top,Comic Sans MS,18,&H0019E0FF,&H001EFFFF,&H80000000,&H80000000,-1,0,0,0,100,100,0,0,1,3,0,2,10,10,30,0
Style: Mid,Comic Sans MS,18,&H0000FFFF,&H00FFFFFF,&H80000000,&H80000000,-1,0,0,0,100,100,0,0,1,3,0,5,10,10,10,0
Style: Bot,Comic Sans MS,18,&H008AFF99,&H00A6FFB8,&H80000000,&H80000000,-1,0,0,0,100,100,0,0,1,3,0,2,10,10,0,0

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
EOT
    $result .= join "\n", @result, '';

    return $result;
} # end sub join_subtitles }}}

if ( grep /\P{ASCII}/ => @ARGV ) {
    @ARGV = map { decode( 'UTF-8', $_ ) } @ARGV;
}

pod2usage(2) unless (@ARGV);

GetOptions(
    'h|help'       => sub { pod2usage(0); },
    'f|file=s{1,}' => \@files,
    'o|output=s'   => \$options->{output},
) or pod2usage(2);

if ( scalar @files < 2 ) {
    pod2usage("Should be at least two files for input");
}

if ( scalar @files > 2 ) {
    pod2usage("Too many files at input. TODO");
}

# multiply option '-f'
$options->{files} = \@files;

my $ass = join_subtitles( $options->{files} );

if ( $options->{output} ) {
    eval { write_file( $options->{output}, $ass ) };
    if ($EVAL_ERROR) {
        croak "Writing to file '$options->{output}' failed:\n$EVAL_ERROR";
    }
}
else {
    print $ass;
}

# {{{ END
__END__

=pod

=encoding utf8

=head1 NAME

join-subs.pl - joins SRT subtitles into one

=head1 SYNOPSIS

join-subs.pl [-h|--help] [-f|--file file] [-o|--output file]

=head1 DESCRIPTION

joins-subs.pl joins the subtitles into one SSA/ASS subtitle file.

=head1 OPTIONS

=over 4

=item -h, --help

Print a summary of options and exit.

=item -f file, --file file

Input SRT subtitles. Should be at least two files for input. Subtitles must be in L<SRT|https://en.wikipedia.org/wiki/SubRip> format.

=item -o file, --output file

Output L<SSA/ASS|https://en.wikipedia.org/wiki/SubStation_Alpha> subtitle. If this option is missing then write to STDOUT.

=back

=head1 EXAMPLE

    join_subtitles.pl -f file.en.srt -f file.pl.srt -o file.ass

=head1 AUTHOR

dracorp E<lt>piotr.r.public@gmail.comE<gt>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

=cut
