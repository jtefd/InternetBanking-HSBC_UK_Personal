#!/usr/bin/env perl

package InternetBanking::HSBC::UK::Personal;

use strict;
use warnings;

use Carp;
use HTML::TreeBuilder;
use POSIX qw/strftime/;
use WWW::Mechanize;

use vars qw/$VERSION/;

$VERSION = '0.0.2';

use constant WEBAPP_URL => qw(http://www.hsbc.co.uk/1/2/personal);

sub new(%) {
    my ($proto, %opts) = @_;
  
    my $class = ref $proto || $proto;
    
    unless ($opts{'id'} && $opts{'dob'} && $opts{'secret'}) {
        confess InternetBanking::HSBC::UK::Personal::Exception->new(
        	InternetBanking::HSBC::UK::Personal::Exception->MISSING_AUTH
        );
    }
    
    my $self = {
        _USERID => $opts{'id'},
        _DATEOFBIRTH => $opts{'dob'},
        _SECRET => $opts{'secret'}
    };
    
    return bless($self, $class);
}

sub login() {
    my ($self) = @_;
    
    $self->{_C} = WWW::Mechanize->new();
    $self->{_C}->agent_alias('Linux Mozilla');
    
    # Get start page
    unless ($self->{_C}->get(WEBAPP_URL)) {
        confess InternetBanking::HSBC::UK::Personal::Exception->new(
			InternetBanking::HSBC::UK::Personal::Exception->FAILED_WEB_CONNECTION
		);
    }
    
    # Get Internet Banking login page
    $self->{_C}->follow_link(text => 'Log on');

    # Get Internet Banking security page for user
    $self->{_C}->form_id('logonForm');
    $self->{_C}->field('userid', $self->{_USERID});
    
    unless ($self->{_C}->click()) {
        confess 'FAILED OPENING ACCOUNT SECURITY PAGE';
    }
    
    # Determine required digits of secret 
    my $root = HTML::TreeBuilder->new_from_content($self->{_C}->response->decoded_content);
    
    my %grammar_index = (
        'FIRST' => 1,
        'SECOND' => 2,
        'THIRD' => 3,
        'FOURTH' => 4,
        'FIFTH' => 5,
        'SIXTH' => 6,
        'SEVENTH' => 7,
        'EIGHTH' => 8,
        'NINTH' => 9,
        'TENTH' => 10,
        'NEXT TO LAST' => length($self->{_SECRET}) - 1,
        'LAST' => length($self->{_SECRET})
    );
    
    my @pass = ();
    
    foreach ($root->look_down('_tag' => 'p', 'class' => 'eg')) {
    	foreach ($_->look_down('_tag' => 'strong')) {
    		my $index = $_->as_text();
    		
    		if ($grammar_index{$index}) {
                $index = $grammar_index{$index};
                
                push @pass, substr($self->{_SECRET}, $index -1, 1);
    		}
    	}
    }

    unless (scalar(@pass) == 3) {
        confess InternetBanking::HSBC::UK::Personal::Exception->new(
			InternetBanking::HSBC::UK::Personal::Exception->UNKNOWN_EXCEPTION
		);
    }
       
    $self->{_C}->form_with_fields( qw/password memorableAnswer/ );
    
    $self->{_C}->field('memorableAnswer', $self->{_DATEOFBIRTH});
    $self->{_C}->field('password', join('', @pass));

	eval {
		$self->{_C}->click_button(value => 'Continue');
	} or do {
		confess InternetBanking::HSBC::UK::Personal::Exception->new(
			InternetBanking::HSBC::UK::Personal::Exception->FAILED_AUTH
		);
	};

	eval {
		$self->{_C}->follow_link(text => 'here');	
	} or do {
		confess InternetBanking::HSBC::UK::Personal::Exception->new(
			InternetBanking::HSBC::UK::Personal::Exception->FAILED_LOGIN
		);	
	};
    
    $self->{_HOME} = $self->{_C}->uri()->as_string();
        
    return $self->{_C};
}

sub getAccounts() {
	my ($self) = @_;
	
	$self->{_C}->get($self->{_HOME});
	#$self->{_C}->follow_link(text => 'Show All');
	
	my $html = HTML::TreeBuilder->new_from_content($self->{_C}->content);
	
	my $accounts = {};
	
	foreach ($html->look_down('_tag', 'div', 'class', 'extContentHighlightPib hsbcCol')) {
        foreach ($_->look_down('_tag', 'tr')) {
        	my $key;
        	
            foreach ($_->look_down('_tag', 'div', 'class', 'col2 rowNo1')) {    
                my $account_number = $_->as_trimmed_text();
                
                $key = $account_number;
                $key =~ s/[^\d]//g;
                
                $accounts->{$key}->{_ACCOUNT_NUMBER} = $account_number;
                last;   
            }
            
            foreach ($_->look_down('_tag', 'input', 'type', 'submit')) {
            	if ($key) {
            	   $accounts->{$key}->{_NAME} = $_->attr('value');
            	   last;	
            	}    
            }
            
            foreach ($_->look_down('_tag', 'div', 'class', 'col3 rowNo1 rightAlign')) {    
                if ($key) {
                	$accounts->{$key}->{_BALANCE} = $_->as_trimmed_text();
                	last; 
                }
            }
            
            foreach ($_->look_down('_tag', 'form')) {
                if ($key && $_->attr('action') =~ /transaction/) {
                   
                    my $form_data = {
                       _PATH => $_->attr('action')
                    };
                   
                    foreach ($_->look_down('_tag', 'input')) {
                        $form_data->{_INPUTS}->{$_->attr('name')} = $_->attr('value');
                    }
                   
                    $accounts->{$key}->{_FORM_DATA} = $form_data;
                   
                    last;
                }
            }
        }
	}
	
	return $accounts;
}

sub getTransactions($;%) {
	my ($self, $account, %opts) = @_;
	
	my $cc_account;
	
	if ($account->{_FORM_DATA}->{_INPUTS}->{'productType'} && $account->{_FORM_DATA}->{_INPUTS}->{'productType'} eq 'CCA') {
		$cc_account = 1;
	}
    
    my $acc_url = sprintf(
        '%s://%s%s',
        $self->{_C}->uri()->scheme(),
        $self->{_C}->uri()->host(),
        $account->{_FORM_DATA}->{_PATH}
    );
	
	$self->{_C}->post($acc_url, $account->{_FORM_DATA}->{_INPUTS});
	
	my $html = HTML::TreeBuilder->new_from_content($self->{_C}->content);
	
	unless ($cc_account) {
		my ($fd, $fm, $fy) = ();
	
		foreach ($html->look_down('_tag', 'div', 'class', 'extPibRow hsbcRow')) {
			foreach ($_->look_down('_tag', 'p')) {
				if (($fd, $fm, $fy) = ($_->as_trimmed_text() =~ /The earliest date you can view is.+(\d{2}) (\w{3}) (\d{4})\./)) {
					last;
				}
			}
		}
		
		my %date_map = (
		   Jan => '01',
		   Feb => '02',
		   Mar => '03',
		   Apr => '04',
		   May => '05',
		   Jun => '06',
		   Jul => '07',
		   Aug => '08',
		   Sep => '09',
		   Oct => '10',
		   Nov => '11',
		   Dec => '12'
		);
		
		$fm = $date_map{$fm};
    
        my ($td, $tm, $ty) = split(' ', strftime('%d %m %Y', localtime));
        
        $self->{_C}->submit_form(
            with_fields => {
                fromDateDay => $fd,
                fromDateMonth => $fm,
                fromDateYear => $fy,
                toDateDay => $td,
                toDateMonth => $tm,
                toDateYear => $ty
            }
        );
	}
	
    $self->{_C}->follow_link(text => 'Download transactions');
    
    my %formats = ();
    
    if ($cc_account) {
    	%formats = (
        	csv => 'CSV1',
        	qif => 'QIF2'
    	);
    }
    else {
    	%formats = (
        	csv => 'S_Text',
        	qif => 'Q_QIF'
    	);
    } 
    
    my $format = $formats{'csv'};
    
    if ($opts{'format'} && $formats{lc($opts{'format'})}) {
    	$format = $formats{lc($opts{'format'})};
    }
    
    if ($cc_account) {
    	$self->{_C}->form_with_fields( qw/formats transactionPeriodSelected es_iid/ );
    	$self->{_C}->field('formats', $format);
    	$self->{_C}->field('transactionPeriodSelected', 'CURRENTPERIOD');
    	$self->{_C}->click();
  
    	$self->{_C}->form_with_fields( qw/es_iid/ );
    }
    else {
		$self->{_C}->submit_form(
       		with_fields => {
           		downloadType => $format
       		}
    	);
    	
    	$self->{_C}->form_with_fields( qw/fileKey token/ );
    }
    
    $self->{_C}->click_button(value => 'Confirm');
    
    return $self->{_C}->content();
}

sub logoff() {
    my ($self) = @_;
    
    $self->{_C}->get($self->{_HOME});
    
    $self->{_C}->follow_link(text => 'Log off');
}

sub dump() {
	my ($self) = @_;
	
	my $filename = sprintf('%s.html', time);
	
	open FILE, ">$filename";
	print FILE $self->{_C}->content;
	close FILE;
}

1;

package InternetBanking::HSBC::UK::Personal::Exception;

use strict;
use warnings;

use constant MISSING_AUTH => 'Please provide user id, date of birth and secret';
use constant FAILED_AUTH => 'Authentication failed, please check the provided details are correct';
use constant FAILED_LOGIN => 'Failed to login to the internet banking service';
use constant FAILED_WEB_CONNECTION => 'Failed to connect to the internet banking service - please verify your internet connection and try again later';
use constant UNKNOWN => 'An unknown error occurred';

sub new($) {
	my ($class, $msg) = @_;
	
	my $self->{_MSG} = $msg;
	
	return bless($self, $class);
}

sub getMessage() {
	my ($self) = @_;
	
	return $self->{_MSG};
}

1;