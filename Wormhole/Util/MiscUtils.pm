package Wormhole::Util::MiscUtils;
use strict;
use warnings;

use Exporter qw(import);
our @EXPORT_OK = qw(rand_pass ip_record_type execute_ddns);

use Net::DNS;
use Regexp::Common qw /net/;

my @key_char_set = ("A".."Z", "a".."z", "0".."9");

sub rand_pass {
    my $len = shift;
    my $pass;

    for (my $i=0; $i < $len; $i++) {
        srand; $pass .= $key_char_set[rand @key_char_set];
    }
    
    return $pass;
}

sub ip_record_type {
    my $addr = shift;
    my $type = undef;
    if ($addr =~ /^$RE{net}{IPv4}$/) {
        $type = "A";
    }
    elsif ($addr =~ /^$RE{net}{IPv6}$/) {
        $type = "AAAA";
    }
    return $type;
}

sub execute_ddns {
    my $dns_update = shift;
    
    my $dns_resolv = new Net::DNS::Resolver;
    $dns_resolv->nameserver($Wormhole::Config::NAMESERVER); # convert to list later

    my $reply = $dns_resolv->send($dns_update);
    if ($reply) {
        if ($reply->header->rcode eq 'NOERROR') {
            return (1, "");
        } else {
            return (0, $reply->header->r_code);
        }
    } else {
        return (0, $dns_resolv->errorstring);
    }
}

1;