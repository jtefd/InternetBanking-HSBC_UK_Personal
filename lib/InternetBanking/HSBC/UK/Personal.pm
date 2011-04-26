#!/usr/bin/env perl

package InternetBanking::HSBC::UK::Personal;

use strict;

use Carp;
use HTML::TreeBuilder;
use WWW::Mechanize;

use constant WEBAPP_URL => qw(http://www.hsbc.co.uk/1/2/personal);

sub new(%) {
    my ($proto, %opts) = @_;
    
    my $class = ref $proto || $proto;
    
    unless ($opts{'id'} && $opts{'dob'} && $opts{'secret'}) {
        confess 'MISSING AUTH DATA';
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
        confess 'FAILED OPENING WEB APP';
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
        'NEXT TO LAST' => 5,
        'LAST' => 6
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
        confess 'FAILED DETERMINING ACCOUNT SECRET';
    }
       
    $self->{_C}->form_with_fields( qw/password memorableAnswer/ );
    
    $self->{_C}->field('memorableAnswer', $self->{_DATEOFBIRTH});
    $self->{_C}->field('password', join('', @pass));

    unless ($self->{_C}->click_button(value => 'Continue')) {
        confess 'FAILED AUTHENTICATION';
    }

    unless ($self->{_C}->follow_link(text => 'here')) {
        confess 'FAILED LOGGING IN';
    }
    
    $self->{_C}->follow_link(text => 'Show All');
        
    return 1;
}

sub logoff() {
    my ($self) = @_;
    
    $self->{_C}->follow_link(text => 'Log off');
}

sub getAccounts() {
    my ($self) = @_;
    
    
}

sub dump() {
    my ($self) = @_;
    
    open FILE, '>', time . '.html';
    print FILE $self->{_C}->content;
    close FILE;
}

1;