package Finance::YahooJapan::HistoricalQuotes;
$VERSION = '0.01';

# Historical Stock Quotes
# Copyright (c) 2002 Masanori HATA. All rights reserved.
# This program is free software; you can redistribute it and/or modify
# it under the same terms as Perl itself.
# Note that you must use this software at your sole risk, and I make
# no warranty of any kinds.

use strict;
use Carp;

use LWP::Simple;

my $Today = join '-', (gmtime(time + (9 * 3600)))[5] + 1900,
                      (gmtime(time + (9 * 3600)))[4] + 1,
                      (gmtime(time + (9 * 3600)))[3];
                      # This time value is based on JST
                      # (Japan Standard Time: GMT + 9.0h).

sub quotes {
	my ($class, $symbol, $start) = @_;
	my $self = {};
	bless $self, $class;
	
	$start = '1980-01-01' unless $start;
	$self->_check($symbol, $start);
	
	$self->adjust(1)->ascend(1)->silent(1);
	$self->fetch($symbol, $start)->show('quotes');
}
sub quotes_custom {
	my ($class, $symbol, $adjust, $ascend, $silent, $start) = @_;
	my $self = {};
	bless $self, $class;
	
	$start = '1980-01-01' unless $start;
	$self->_check($symbol, $start);
	
	$self->adjust($adjust)->ascend($ascend)->silent($silent);
	$self->fetch($symbol, $start)->show('quotes');
}

sub splits {
	my ($class, $symbol, $start) = @_;
	my $self = {};
	bless $self, $class;
	
	$start = '1980-01-01' unless $start;
	$self->_check($symbol, $start);
	
	$self->adjust(0)->ascend(1)->silent(1);
	$self->fetch($symbol, $start)->show('splits');
}
sub splits_custom {
	my ($class, $symbol, $ascend, $silent, $start) = @_;
	my $self = {};
	bless $self, $class;
	
	$start = '1980-01-01' unless $start;
	$self->_check($symbol, $start);
	
	$self->ascend($ascend)->silent($silent);
	$self->fetch($symbol, $start)->show('splits');
}

sub _check {
	my ($self, $symbol, $start) = @_;
	unless ($symbol =~ /^\d{4}\.[a-zA-Z]$/) {
		croak "Stock symbol should be given 4 numbers followed by market extension: `.' and 1 alphabet. (ex. `6758.t' )";
	}
	unless ($start =~ /^\d{4}-\d{2}-\d{2}$/) {
		croak "Date should be given in a format `YYYY-MM-DD'. (ex. `2002-01-04')";
	}
	return $self;
}

sub adjust {
	my $self = shift;
	$$self{'adjust'} = shift;
	return $self;
}
sub ascend {
	my $self = shift;
	$$self{'ascend'} = shift;
	return $self;
}
sub silent {
	my $self = shift;
	$$self{'silent'} = shift;
	return $self;
}

sub show {
	my ($self, $data_type) = @_;
	if ($data_type eq 'splits') {
		if ($$self{'ascend'} == 0) { return @{ $$self{'splits'} }; }
		else { _reverse_order(\@{ $$self{'splits'} }); }
	}
	elsif ($$self{'adjust'} == 1) {
		if ($$self{'ascend'} == 0) { return @{ $$self{'quotes_adjusted'} }; }
		else { _reverse_order(\@{ $$self{'quotes_adjusted'} }); }
	}
	else {
		if ($$self{'ascend'} == 0) { return @{ $$self{'quotes'} }; }
		else { _reverse_order(\@{ $$self{'quotes'} }); }
	}
}

sub fetch {
	my ($self, $symbol, $start) = @_;
	# estimate fetching period
	my ($year_a, $month_a, $day_a) = split /-/, $start;
	my ($year_z, $month_z, $day_z) = split /-/, $Today;
	
	# multi page fetching
	print 'fetching: ' if $$self{'silent'} != 1;
	my @remotedocs;
	for (my $page = 0; ; $page++) {
		my $y = $page * 50; # 50rows / 1page is max @ Yahoo (J) Finance
		my $url = "http://chart.yahoo.co.jp/t?a=$month_a&b=$day_a&c=$year_a&d=$month_z&e=$day_z&f=$year_z&g=d&s=$symbol&y=$y";
		my $remotedoc = get($url);
		
		# testing whether it is the final page (with bulk rows) or not
		if ($remotedoc =~ m/\n<tr bgcolor="#dcdcdc"><th>日付<\/th><th>始値<\/th><th>高値<\/th><th>安値<\/th><th>終値<\/th><th>出来高<\/th><th>調整後終値\*<\/th><\/tr>\n<\/table>\n/) {
			last;
		}
		push (@remotedocs, $remotedoc); # store the passed pages
		print $page + 1, '->' if $$self{'silent'} != 1;
	}
	print "finished.\n" if $$self{'silent'} != 1;
	
	# extract quotes data from fetched pages
	for (my $i = 0; $i <= $#remotedocs; $i++) {
		$self->_crop_n_scan($remotedocs[$i]);
	}
	
	# adjust values for splits
	$self->_adjust_for_splits();
	
	return $self;
}

# quotes data extracter from fetched Yahoo (J) Finance pages
sub _crop_n_scan {
	my $self = shift;
	my @page = split /\n/, $_[0]; # split page to lines
	
	# remove lines before & after the quotes data rows.
	my ($cut_from_here, $cut_by_here);
	for (my $i = 0; $i <= $#page; $i++) {
		if ($page[$i] =~ m/^<tr bgcolor="#dcdcdc"><th>日付<\/th><th>始値<\/th><th>高値<\/th><th>安値<\/th><th>終値<\/th><th>出来高<\/th><th>調整後終値\*<\/th><\/tr>$/) {
			$cut_from_here = $i + 2;
			unless ($page[$cut_from_here - 1] =~ m/^<tr$/) { $cut_from_here--; } # in the only case split row is the top row
		}
	}
	for (my $i = $cut_from_here; $i <= $#page; $i++) {
		if ($page[$i] =~ m/<\/table>/) {
			$cut_by_here = $i;
			last;
		}
	}
	# restruct a new list with the quotes data rows
	my @table;
	for (my $i = $cut_from_here; $i <= $cut_by_here; $i++) {
		push @table, $page[$i];
	}
	
	# remove needless texts at the head of the lines (except for the top split row)
	foreach my $row (@table) {
		$row =~ s/^align=right><td>//;
	}
	
	foreach my $row (@table) {
		my ($date, $open, $high, $low, $close, $volume, $extra);
		# in the case the row is the top split row
		if ($row =~ m/^<tr><td align=right>/) {
			$row =~ s/<tr><td align=right>/><td align=right>/;
			$row =~ s/<\/td><\/tr><tr$//;
			$extra = $row;
		}
		# this case is normal: quotes data rows
		else {
			# split the line with </td><td>
			($date, $open, $high, $low, $close, $volume, $extra) = split /<\/td><td>/, $row;
			$close =~ s/<b>//;
			$close =~ s/<\/b>//;
			# changing date & numeric formats
			$date =~ s/(.*?)年(.*?)月(.*?)日/$1-$2-$3/;
			$date =~ s/(.*?-)(\d)(-.*)/${1}0$2$3/;
			$date =~ s/(.*?-.*?-)(\d)$/${1}0$2/;
			foreach my $number ($open, $high, $low, $close, $volume) {
				$number =~ s/,//g;
			}
			$row = join "\t", ($date, $open, $high, $low, $close, $volume);
			push @{ $$self{'quotes'} }, $row; # store the quotes data in the style just we've wanted ever! ;)
		}
		
		# here it is, another splits infomations...
		$extra =~ s/^.*<\/table>$//; # remove the bottom row. you don't worry, because a split row will never appears in the bottom row.
		$extra =~ s/^.*?<\/td><\/tr><tr//; # if the row data don't contain the split data, it is converted to a bulk data ('').
		# find the splits!
		unless ($extra eq '') {
			$extra =~ s/><td align=right>(.*?)年(.*?)月(.*?)日<\/td><td colspan=6 align=center>分割: (.*?)株 -> (.*?)株.*/$1-$2-$3\t$4\t$5/;
			$extra =~ s/(.*?-)(\d)(-.*)/${1}0$2$3/;
			$extra =~ s/(.*?-.*?-)(\d)(\t.*)/${1}0$2$3/;
			push @{ $$self{'splits'} }, $extra;
		}
	}
}

sub _adjust_for_splits {
	my $self = shift;
	@{ $$self{'quotes_adjusted'} } = @{ $$self{'quotes'} };
	my $j = 0;
	for (my $k = 0; $k <= $#{ $$self{'splits'} }; $k++) {
		my ($split_date, $split_pre, $split_post) = split /\t/, ${ $$self{'splits'} }[$k];
		for (my $i = $j; $i <= $#{ $$self{'quotes'} }; $i++) {
			my($date, undef, undef, undef, undef, undef) = split /\t/, ${ $$self{'quotes_adjusted'} }[$i];
			if ($date eq $split_date) {
				$j = $i + 1;
				last;
			}
		}
		for (my $i = $j; $i <= $#{ $$self{'quotes'} }; $i++) {
			my($date, $open, $high, $low, $close, $volume) = split /\t/, ${ $$self{'quotes_adjusted'} }[$i];
			foreach my $price ($open, $high, $low, $close) {
				$price = int($price * $split_pre / $split_post + 0.5);
			}
			$volume = int($volume * $split_post / $split_pre + 0.5);
			${ $$self{'quotes_adjusted'} }[$i] = "$date\t$open\t$high\t$low\t$close\t$volume";
		}
	}
}

# reverse row order from descending to ascending.
sub _reverse_order {
	my $self = shift;
	my @reversed;
	for (my $i = $#$self; $i >= 0; $i--) {
		push @reversed, $$self[$i];
	}
	return @reversed;
}

__END__

=head1 NAME

Finance::YahooJapan::HistoricalQuotes

=head1 DESCRIPTION

This module fetchs historical stock quotes of Japanese market.

=head1 SYNOPSIS

 use Finance::YahooJapan::HistoricalQuotes;
 
 # fetch the quotes of Sony Corp. at Tokyo market.
 @quotes = Finance::YahooJapan::HistoricalQuotes->quotes('6758.t');
 
 foreach $quotes (@quotes) {
 	print $quotes, "\n";
 }

=head1 METHODS

=over

=item quotes($symbol [, $start])

quotes() method fetches quotes; those values have been already adjusted for splits;
showing data in ascending order; silent fetching during its procedure.

=item splits($symbol [, $start])

splits() method fetches splits;
showing data in ascending order; silent fetching during its procedure.

A stock symbol ($symbol) should be given 4 numbers followed by market extension: `.' and 1 alphabet. (ex. `6758.t' )
For more informations about market extensions, check at: http://help.yahoo.co.jp/help/jp/fin/quote/stock/quote_02.html

Starting date ($start) should be given in a format `YYYY-MM-DD'. (ex. `2002-01-04')
The default $start is '1980-01-01'. (Be careful, do not forget to quote words,
because bare word 2000-01-01 will be conprehend by Perl as 2000 - 1 - 1 = 1998 !)

=item quotes_custom($symbol, $adjust, $order, $silent [, $start])

quotes_custom() method presents some more options to quotes() method.

=item splits_custom($symbol, $order, $silent [, $start])

splits_custom() method presents some more options to splits() method.

$adjust: for splits, adjust(1) or not adjust(0).

$order: showing data in ascending order(1) or descending order(0).

$silent: during its procedure, fetching in silent(1) or not(0).

=back

=head1 THIS VERSION

v0.01

=head1 DEVELOPED PLATFORM

Perl v5.6.1 for MSWin32-x86-multi-thread (ActivePerl b631)

=head1 NOTES

This program calculates adjusted values originally including closing price.
The only adjusted value which Yahoo presents is closing price,
and its numbers are not rounded but cut for decimal fractions.
For this reason, I decided to ignore Yahoo's adjusted values (that's why some adjusted closing prices are different from Yahoo's).

For non-Japanese users:
this program includes some Japanese multi-byte character codes called `EUC-JP'
for analyzing Yahoo! Japan's HTML data.

This is an idea, experimental version. Some interfaces may be changed in the future development.

Sorry, my poor English. `All your code is blong to CPAN!' (I hope so.)

=head1 AUTHOR

Masanori HATA <lovewing@geocities.co.jp>

=head1 COPYRIGHT

Copyright (c) 2002 Masanori HATA. All rights reserved.
This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 HISTORY

 2002-04-09 v0.01
 2002-03-18 v0.00
 2001-05-30 (Yahoo! Cropper v0.1)
