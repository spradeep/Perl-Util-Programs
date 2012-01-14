#!/usr/bin/perl

use strict;
use warnings;
use WWW::Mechanize;
use HTML::TreeBuilder;
use LWP::UserAgent;
use HTML::Entities;
use DBI;
use Devel::StackTrace;

$SIG{__DIE__} = sub {
	my $s = new Devel::StackTrace;

	print $s->as_string;
};

my $iphone_ua = 'Mozilla/5.0 (iPhone; U; CPU like Mac OS X; en) AppleWebKit/420+ (KHTML, like Gecko) Version/3.0 Mobile/1A543a Safari/419.3';

my $mech = WWW::Mechanize->new( onerror => sub { warn @_; }, agent => $iphone_ua );
my $dbh = DBI->connect( "dbi:SQLite:dbname=rkm.db", "", "", { AutoCommit => 0 } );
my $sth = $dbh->prepare(q[INSERT INTO songs(album,music,year,lyrics, song, artist,url,size) VALUES(?,?,?,?,?,?,?,?)]);

$dbh->do(q[DELETE FROM songs]);

my $html_tree = HTML::TreeBuilder->new;    # empty tree
my $ua        = LWP::UserAgent->new;

$ua->agent($iphone_ua);

## fetch all albums
my @albums;

for my $alphabet ( qw/b/ ) {
    $mech->get( sprintf( 'http://m.rkmania.com/albumlist.php?category=&catid=2&letter=%s', $alphabet ) );

    $html_tree = HTML::TreeBuilder->new_from_content( $mech->content );

    foreach my $link ( $html_tree->look_down( sub { $_[0]->tag eq 'a' && defined $_[0]->attr('href') && $_[0]->attr('href') =~ /^album\.php/ } ) ) {
        printf( "%s - %s\n", $link->attr('title'), $link->attr('href') );

        push( @albums, { l => $link->attr('href'), a => $link->attr('title') } );
    }

    sleep(3);
}

my @albums_data;

foreach my $album (@albums[0..4]) {
    $mech->get( $album->{l} );

    my $data    = { a => $album->{a} };
    my $content = $mech->content;
    ($data->{music}) = $content =~ /Music:\s([^<]+)/;

    ($data->{lyrics}) = $content =~ /Lyrics:\s([^<]+)/;

    ($data->{year}) = $content =~ /Year:\s([^<]+)/;

    ($data->{bitrate}) = $content =~ /Bitrate:\s([\w\s]+)/;

    $html_tree = HTML::TreeBuilder->new_from_content( $mech->content );

    my @songs;
    foreach my $link ( $html_tree->look_down( sub { $_[0]->tag eq 'a' && defined $_[0]->attr('href') && $_[0]->attr('href') =~ /^songs\.php/ && defined $_[0]->attr('title') && $_[0]->attr('title') !~ /download/i } ) ) {
        printf( "%s - %s\n", $link->attr('title'), $link->attr('href') );

        push( @songs, { l => $link->attr('href'), a => $link->attr('title') } );
    }

    $data->{songs} = \@songs;

    push( @albums_data, $data );

    sleep(3);
}


foreach my $a (@albums_data) {

    my @tmp_songs;    # replace original data
    foreach my $song ( @{ $a->{songs} } ) {
        $mech->get( $song->{l} );

        my $link = $mech->uri->clone;

        $link->path_query( $link->path_query() . '&get=1' );

        $html_tree = HTML::TreeBuilder->new_from_content( $mech->content );
        my $content = $mech->content;
        my @matches = $content =~ /Artist :\s([^<]+)/;
        my $artist = decode_entities( $matches[0] );

        @matches = $content =~ /File Size :\s([^<]+)/;
        my $size = $matches[0];

        $sth->execute( @{$a}{qw/a music year lyrics/}, @{$song}{qw/a/},$artist,$link->as_string,$size );

		sleep(3);
    }
}

#foreach my $a (@albums_data) {
#
#    print $a->{a} . "==" . scalar( @{ $a->{songs} } ) . "\n";
#    my @tmp_songs;    # replace original data
#    foreach my $song ( @{ $a->{songs} } ) {
#        $sth->execute( @{$a}{qw/a music year lyrics/}, @{$song}{qw/a artist l size/} );
#    }
#}

$dbh->commit;

=pod
CREATE VIRTUAL TABLE songs USING fts3(album, song, artist,url,size,music,year,lyrics);
=cut
