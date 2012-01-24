#!/usr/bin/perl

use strict;
use WWW::Mechanize;
use HTML::TreeBuilder;
use CGI qw(:standard);

use constant {
    CHART_PREPARED     => 1,
    CHART_NOT_PREPARED => 0
};

$SIG{__DIE__} = sub {
	use Devel::StackTrace;

	my $s = Devel::StackTrace->new;

	print $s->as_string;
};

my $class_struct = {};
my $pnr          = param('pnr');
my ( $pnrno1 ) = $pnr;

print header();
print start_html( -title => "$pnrno1" );

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

$mech->add_header( Referer => 'http://www.indianrail.gov.in/index.html');
$mech->get("http://www.indianrail.gov.in/pnr_Enq.html");
$mech->delete_header( 'Referer' );

$mech->submit_form(
    form_name => 'pnr_stat',
    fields    => { lccp_pnrno1 => "$pnrno1" },
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
if ( $train_info_table && ref $train_info_table eq 'HTML::Element' ) {
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

    if ( scalar(@tds) >= 3 ) {
        my ( $p, $bs, $cs, $cp ) = map { $_->as_text } @tds;

        push( @{ $data{passenger_info} }, { raw => [ $p, $bs, $cs, $cp ] } );
    }
    elsif ( scalar(@tds) == 1 ) {
        $data{chart} = ( $tds[0]->as_text =~ /not/i ) ? CHART_NOT_PREPARED : CHART_PREPARED;
    }
}

## loop and get seat, coach, etc.

@{ $data{passenger_info} } = map {
    my @bs_bu = map { s/\s+//g; $_; } split( /,/, $_->{raw}->[1] );
    my @cs_bu = map { s/\s+//g; $_; } split( /,/, $_->{raw}->[2] );

    my %tmp;

    if ( $data{chart} == CHART_PREPARED ) {
        @tmp{qw/coach seat coach_position/} = ( @cs_bu, $_->{raw}->[3] );
    }
    else {
        @tmp{qw/coach seat quota/} = @bs_bu;
    }

    $data{tkt_is_confirmed} = 1 if ( $_->{raw}->[2] =~ /CNF/ );
    my $seat_pos;

    if ( $data{tkt_is_confirmed} ) {
        $seat_pos = $class_struct->{ $data{class} }->{layout}->[ ( $tmp{seat} % $class_struct->{ $data{class} }->{seats_block_size} ) - 1 ] if ( exists( $class_struct->{ $data{class} } ) && $class_struct->{ $data{class} }->{seats_block_size} && $tmp{seat} );
    }

    $_->{raw}->[0] =~ s/Passenger //i;

    @tmp{qw/p raw seat_pos/} = ( $_->{raw}->[0], $_->{raw}, $seat_pos );

    $data{has_seat_pos} = 1 if ($seat_pos);

    \%tmp;

} @{ $data{passenger_info} };

print '<table style="width:100%; border-collapse:collapse; border: #000 1px solid" border=1 bordercolor="#000000"><thead><tr style="background-color:#eee">';
printf( '<th>%s</th>', $_ ) for ( ( 'No.', 'Ori. Status', 'Cur. Status', 'Seat', 'Coach Pos' ) );
print '</th></tr></thead><tbody>';
foreach my $p ( @{ $data{passenger_info} } ) {
    print '<tr>';
    printf( '<td>%s</td>', $_ ) for ( ( $p->{p}, $p->{raw}->[1], $p->{raw}->[2], $p->{seat_pos} || 'NA', $p->{coach_position} || 'NA' ) );
    print '</tr>';
}

print '</tbody></table>';

print end_html();
