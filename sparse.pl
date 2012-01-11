#!/usr/bin/perl

use strict;
use warnings;
use DateTime;
use DateTime::Format::Strptime qw[strptime];
use Getopt::Std;
use WWW::Mechanize;
use HTML::TreeBuilder;
use Carp;
use DBI;

=pod
Options:
c - name of config file to load
d - debug flag
a - all flag - will fetch for all available pages
=cut

use vars qw[%serial_urls %options];

getopt( 'dac:', \%options );

my $config_file = $options{c} || 'config.pl';

  eval { require $config_file; };

if ($@) {
    die "Could not load config file";
}


my $mech = WWW::Mechanize->new( onerror => sub { carp @_; } );
my $dbh = DBI->connect( 'dbi:SQLite:dbname=ssl.db', undef, undef, { AutoCommit => 0 } );

my %urls = map { $_ => [ $serial_urls{$_} ] } keys %serial_urls;

## if asked to process all
if ( defined $options{a} && $options{a} ) {
    foreach my $s ( keys %urls ) {
        my @urls = @{ $urls{$s} };
        my $url  = pop(@urls);

        do {
            $mech->get($url);
            my $html_tree = HTML::TreeBuilder->new_from_content( $mech->content );
            if ( my $next_link = $mech->find_link( text_regex => qr/Next Page/i ) ) {

                push( @{ $urls{$s} }, $next_link->url() );
                $url = $next_link->url();
            }
            else {
                $url = undef;
            }
        } while ($url);
    }
}

use Data::Dumper; warn Dumper(\%urls,\%options);

foreach my $s (keys %urls) {
}
