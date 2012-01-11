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
my $sth_ins = $dbh->prepare(q[INSERT INTO episode_list(serial_code, episode_date, url , dt_added) VALUES(?,?,?,DATETIME(?))]);

my %urls = map { $_ => [ $serial_urls{$_} ] } keys %serial_urls;

## if asked to process all
if ( defined $options{a} && $options{a} ) {
    foreach my $s ( keys %urls ) {
        my @urls = @{ $urls{$s} };
        my $url  = pop(@urls);

        do {
            $mech->get($url);
            my $html_tree = HTML::TreeBuilder->new_from_content( $mech->content );
            $url = undef;
            if ( my $next_link = $mech->find_link( text_regex => qr/Next Page/i ) ) {

                push( @{ $urls{$s} }, $next_link->url() );
                $url = $next_link->url();
            }
        } while ($url);
    }
}

foreach my $s ( keys %urls ) {
    foreach my $pg_url ( @{ $urls{$s} } ) {
        $mech->get($pg_url);
        my $html_tree = HTML::TreeBuilder->new_from_content( $mech->content );
        my @links     = map {
            $_->look_down( sub { $_[0]->tag eq 'a' } )
        } $html_tree->look_down( sub { $_[0]->tag eq 'div' && defined $_[0]->attr('id') && $_[0]->attr('id') =~ /^post-\d+$/ } );

        foreach my $link (@links) {
            $link->attr('title') =~ /(\d+?)\w{2} (\w+) (\d{4})$/;
            my $date = strptime( '%d %B %Y', "$1 $2 $3" );

            $mech->get( $link->attr('href') );
            my $html_tree = HTML::TreeBuilder->new_from_content( $mech->content );

            foreach my $link ( $html_tree->look_down( sub { $_[0]->tag eq 'a' && defined $_[0]->attr('href') && $_[0]->attr('href') =~ /dm\.html/ } ) ) {
                local $\ = "\n";
                $link->attr('href') =~ /file=(.+)/;
                my $u = "http://www.dailymotion.com/video/$1";

				$sth_ins->execute($s,$date->strftime('%F'),$u,'now');
            }
        }

		$dbh->commit;
    }
}

__END__

CREATE TABLE episode_list(serial_code VARCHAR(30), episode_date DATE, url VARCHAR(255), dt_added DATETIME, is_fetched INTEGER DEFAULT 0)
CREATE UNIQUE INDEX unqIdx ON episode_list(serial_code,episode_date,url)
