#!/usr/bin/perl

use strict;
use WWW::Mechanize;
use HTML::TreeBuilder;
use Data::Dumper;
use Text::ASCIITable;
use CGI qw(:standard);

use constant {
    CHART_PREPARED     => 1,
    CHART_NOT_PREPARED => 0
};

my $class_struct = {};
my $pnr          = param('pnr');
my ( $pnrno1, $pnrno2 ) = $pnr =~ /(\d{3})(\d{7})/;

print header();
print start_html( -title => "$pnrno1-$pnrno2" );

## different layout & info of Indian Railway class
$class_struct->{'2A'} = {
    max_seats        => 45,
    seats_block_size => 6,
    layout           => [qw/LB UB LB UB SL SU/]
};

$class_struct->{'SL'} = $class_struct->{'3A'} = {
    max_seats        => 72,
    seats_block_size => 8,
    layout           => [qw/LB UB LB UB SL SU/]
};

$class_struct->{'3A'}->{max_seats} = 64;    ## max is different
## layout done

my $mech = WWW::Mechanize->new( onerror => sub { warn @_; } );
$mech->agent_alias('Windows IE 6');

$mech->get("http://www.indianrail.gov.in/pnr_stat.html");

$mech->submit_form(
    form_name => 'pnr_stat',
    fields    => { lccp_pnrno1 => "$pnrno1", lccp_pnrno2 => "$pnrno2" },
    button    => 'submitpnr'
);

my %data;

my $html_tree = HTML::TreeBuilder->new;    # empty tree
$html_tree->parse( $mech->content );

## let's get train info, tricky as table is hard to identify
my ($train_info_table) = grep {
    $_->look_down(
        sub {
            $_[0]->tag eq 'td' && $_[0]->as_text =~ /journey details/sig;
        }
      )
  } $html_tree->look_down(
    sub {
        $_[0]->tag eq 'table' && $_[0]->attr('class') eq 'table_border';
    }
  );

## if we have the train info table, grab the required info
if ( $train_info_table && ref $train_info_table eq 'HTML::Element' )
{
    my %train_info;

    @train_info{qw/name no dt from to rupto bpoint class/} = map { my $t = $_->as_text; $t =~ s/(^\s+|\s+$)//g; $t; } $train_info_table->look_down(
        sub {
            $_[0]->tag eq 'td' && $_[0]->attr('class') eq 'table_border_both';
        }
    );

    %data = ( %data, %train_info ) if ( scalar keys %train_info );
}

my ($data_table) = $html_tree->look_down(
    sub {
        $_[0]->attr('id') eq 'center_table';
    }
);

my @data;

$data{passenger_info} ||= [];

foreach my $tr (
    $data_table->look_down(
        sub {
            $_[0]->tag eq 'tr';
        }
    )
  )
{
    my @tds = $tr->look_down(
        sub {
            $_[0]->tag eq 'td' && $_[0]->attr('class') eq 'table_border_both';
        }
    );

    next unless (@tds);

    if ( scalar(@tds) >= 3 )
    {
        my ( $p, $bs, $cs, $cp ) = map { $_->as_text } @tds;

        push( @{ $data{passenger_info} }, { raw => [ $p, $bs, $cs, $cp ] } );
    }
    elsif ( scalar(@tds) == 1 )
    {
        $data{chart} = ( $tds[0]->as_text =~ /not/i ) ? CHART_NOT_PREPARED : CHART_PREPARED;
    }
}

## loop and get seat, coach, etc.

@{ $data{passenger_info} } = map {
    my @bs_bu = map { s/\s+//g; $_; } split( /,/, $_->{raw}->[1] );
    my @cs_bu = map { s/\s+//g; $_; } split( /,/, $_->{raw}->[2] );

    my %tmp;

    if ( $data{chart} == CHART_PREPARED )
    {
        @tmp{qw/coach seat coach_position/} = ( @cs_bu, $_->{raw}->[3] );
    }
    else
    {
        @tmp{qw/coach seat quota/} = @bs_bu;
    }

    my $seat_pos = $class_struct->{ $data{class} }->{layout}->[ ( $tmp{seat} % $class_struct->{ $data{class} }->{seats_block_size} ) - 1 ] if ( exists( $class_struct->{ $data{class} } ) && $class_struct->{ $data{class} }->{seats_block_size} && $tmp{seat} );

    $_->{raw}->[0] =~ s/Passenger //i;

    @tmp{qw/p raw seat_pos/} = ( $_->{raw}->[0], $_->{raw}, $seat_pos );

    $data{has_seat_pos} = 1 if ($seat_pos);
    $data{tkt_is_confirmed} = 1 if ( $_->{raw}->[2] =~ /CNF/ );

    \%tmp;

} @{ $data{passenger_info} };

my $t = Text::ASCIITable->new( { headingText => "PNR $pnr" } );

my @cols = ( 'No.', 'Ori. Status', 'Cur. Status', 'Seat', 'Coach Pos' );
my @to_delete;

push( @to_delete, 1 ) if ( $data{chart} == CHART_PREPARED );
push( @to_delete, 3 ) unless ( $data{has_seat_pos} );
push( @to_delete, 4 ) if ( $data{chart} == CHART_NOT_PREPARED );
push( @to_delete, 2 ) if ( $data{tkt_is_confirmed} );

delete @cols[@to_delete];

$t->setCols( grep( $_, @cols ) );

foreach my $p ( @{ $data{passenger_info} } )
{
    my @t;
    push( @t, $p->{p} );
    push( @t, $p->{raw}->[1] ) if ( $data{chart} == CHART_NOT_PREPARED );
    push( @t, $p->{raw}->[2] ) unless ( $data{tkt_is_confirmed} );
    push( @t, $p->{seat_pos} ) if ( $data{has_seat_pos} );
    push( @t, $p->{coach_position} ) if ( $data{chart} == CHART_PREPARED );

    $t->addRow(@t);
}

print "<pre>$t</pre>";

print end_html();
