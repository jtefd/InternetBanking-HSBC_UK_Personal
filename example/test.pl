#!/usr/bin/env perl

BEGIN {
	push @INC, '../lib';
}

use strict;

use Data::Dumper;
use InternetBanking::HSBC::UK::Personal;

my $id = '';
my $dob = '';
my $secret = '';

my $ib = InternetBanking::HSBC::UK::Personal->new(id => $id, dob => $dob, secret => $secret);
$ib->login();

$ib->dump();

$ib->logoff();
