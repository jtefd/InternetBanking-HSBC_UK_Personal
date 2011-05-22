#!/usr/bin/env perl

=pod

=head1 NAME

hsbc-ib

=head1 SYNOPSIS

hsbc-ib --id <ID> --dob <DOB> --secret <SECRET> [options]

=head1 OPTIONS

=head2 REQUIRED

If any of the following are not given, the user will be prompted to provide them

=over 8

=item B<--id> <ID>

The user's HSBC internet banking user ID

=item B<--dob> <DOB>

The user's date of birth

=item B<--secret> <SECRET>

The user's secret code for HSBC internet banking

=back

=head2 SWITCHES

=over 8

=item B<--show-accounts>

Show balances for all accounts

=item B<--download-statements>

Download available statements for all accounts

=over 8

=item B<--format> <csv|qif>

Download statements in the given format (defaults to qif)

=item B<--account> <ACC_CODE>

Download statements for the given account only

=back

=item B<--save-auth>

Save user authentication details to avoid having to provide them next time

=item B<--help>

Show help (this screen)

=back

=head1 AUTHOR

James Telford (jtefd@cpan.org)

=cut

use strict;
use warnings;

use File::Basename qw/dirname/;
use File::Path qw/mkpath/;
use File::Spec::Functions qw/catfile/;
use Getopt::Long;
use InternetBanking::HSBC::UK::Personal;
use Pod::Usage;
use Term::ReadKey;

use constant USER_AUTH_FILE => catfile($ENV{'HOME'}, '.hsbc-ib', 'auth');

sub GetMaskedUserInput($) {
	my ($msg) = @_;
	
	ReadMode('noecho');
    print STDERR $msg;
    chomp(my $result = <STDIN>);
    ReadMode('restore');
    print STDERR "\n"; 
    
    return $result;
}

sub LoadUserAuth() {
	my $auth = {};
	
	if (-f USER_AUTH_FILE) {
        open FILE, USER_AUTH_FILE;
    
        while (<FILE>) {
        	chomp;
        	
        	my ($k, $v) = split('=');
        	
        	$auth->{$k} = $v;
        }
    
        close FILE;	
	}
	return $auth;
}

sub PersistUserAuth($$$) {
	my ($id, $dob, $secret) = @_;
	
	unless (-d dirname(USER_AUTH_FILE)) {
		mkpath(dirname(USER_AUTH_FILE));
	}
	
	open FILE, '>' . USER_AUTH_FILE;
	printf(FILE "id=%s\n", $id);
	printf(FILE "dob=%s\n", $dob);
	printf(FILE "secret=%s\n", $secret);
	close FILE;
}

my %opts = ();

GetOptions(
    \%opts,
    'id=s',
    'dob=s',
    'secret=s',
    'show-accounts',
    'download-statements',
    'account=s',
    'format=s',
    'save-auth',
    'help|h|?'
);

if ($opts{'help'}) {
	pod2usage(-verbose => 1, -exitval => 0);
}

unless ($opts{'show-accounts'} || $opts{'download-statements'}) {
	pod2usage(-verbose => 1, -exitval => 1);
}

my $auth = LoadUserAuth();

unless ($opts{'id'}) {
	if ($auth->{'id'}) {
	   $opts{'id'} = $auth->{'id'};	
	}
	else {
	   $opts{'id'} = GetMaskedUserInput('User ID: ');	
	}
}

unless ($opts{'dob'}) {
	if ($auth->{'dob'}) {
       $opts{'dob'} = $auth->{'dob'}; 
    }
    else {
        $opts{'dob'} = GetMaskedUserInput('Date of birth (DDMMYY): ');	
    }
}

unless ($opts{'secret'}) {
	if ($auth->{'secret'}) {
       $opts{'secret'} = $auth->{'secret'}; 
    }
    else {
        $opts{'secret'} = GetMaskedUserInput('Secret: ');	
    }
}

if ($opts{'save-auth'}) {
	PersistUserAuth($opts{'id'}, $opts{'dob'}, $opts{'secret'});
}

eval {
	my $ib = InternetBanking::HSBC::UK::Personal->new(
  	  id => $opts{'id'}, dob => $opts{'dob'}, secret => $opts{'secret'}
	);
	
	$ib->login();
	
	if ($opts{'show-accounts'}) {
		my $accounts = $ib->getAccounts();
		
		while (my ($k, $acc) = each %{$accounts}) {
	        printf("%s\t%s\t%s\n", $acc->{_ACCOUNT_NUMBER}, $acc->{_NAME}, $acc->{_BALANCE});
	    }
	}
	elsif ($opts{'download-statements'}) {
		unless ($opts{'format'}) {
			$opts{'format'} = 'qif';
		}
		
	    my $accounts = $ib->getAccounts();
	    
		while (my ($k, $acc) = each %{$accounts}) {
			my $flag;
			
			if ($opts{'account'}) {
				if ($opts{'account'} eq $k) {
					$flag = 1;
				}
			}
			else {
				$flag = 1;
			}
			
			if ($flag) {
	            my $filename = sprintf('%s_%s', $k, time);
	            
	            my $txns = $ib->getTransactions($acc, format => $opts{'format'});
	
	            if ($txns) {
	                open FILE, '>' . $filename . '.' . $opts{'format'};
	                print FILE $txns;
	                close FILE;	
	            }
			} 
	    }
	}
	
	$ib->logoff();

} or do {
	if ($@->isa(qw/InternetBanking::HSBC::UK::Personal::Exception/)) {
		print STDERR $@->getMessage();
	}
	else {
		printf(STDERR "The requested operation failed to complete:\n\n%s", $@);
	}
};
