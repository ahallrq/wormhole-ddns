package conf;
use strict;
use warnings;

our $admin_key = "<insert key here>";
our $NAMESERVER_DNSSEC_KEY = "/path/to/a/dnssec/key";
our $NAMESERVER_DNS_ZONE = "ddns.example.org";
#my @NAMESERVER_NS_LIST = ("ns1.ddns.example.org", "ns2.ddns.example.org");
our $NAMESERVER = "ns1.ddns.example.org";

1;