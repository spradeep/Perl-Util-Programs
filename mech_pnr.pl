#!/usr/bin/perl


use CGI qw(:standard);
use CGI::Carp qw(fatalsToBrowser);
use WWW::Mechanize;
use HTML::TableContentParser;
my $mech = WWW::Mechanize->new();
$mech->agent_alias( 'Windows IE 6' );


$mech->get( "http://www.indianrail.gov.in/pnr_stat.html" );
$pnr=param('pnr');
($pnrno1,$pnrno2) = $pnr =~ /(\d{3})(\d{7})/ ;

print header();
print start_html(-title=>"$pnrno1-$pnrno2");

$mech->submit_form(
		form_name => 'pnr_stat',
		fields    => { lccp_pnrno1  => "$pnrno1", lccp_pnrno2 => "$pnrno2"},
		button    => 'submitpnr'
);

my $p = HTML::TableContentParser->new( );
my $tables = $p->parse( $mech->content( ) );
# Table with the values is has its class attribute set to report.
my @report_tables = grep { exists $_->{id} and $_->{id} eq 'center_table' } @$tables;

my $table = $report_tables[0];
my @row_cell_objs = grep { $_->{cells} } @{ $table->{rows} };
my @data_cells = map { $_->{cells} } @row_cell_objs;

use Text::ASCIITable;
$t = Text::ASCIITable->new({ headingText => "PNR $pnr" });
$t->setCols('No.','Ori Status','Current');


foreach my $row ( @data_cells ) {
	my @data = map { $_->{data} } @$row;
	foreach (@data) {
	# Remove HTML tags and surrounding whitespace.
	s/<[^>]*>//g;
	s/^\s+//;
	s/\s+$//;
	s/\&lt;/</g;
	s/Passenger //g;
	}
$t->addRow(@data);

}

print "<PRE>$t</PRE>";

