## Wormhole Dynamic DNS Manager

Wormhole is a lightweight free DDNS management web application written in Perl and utilising Plack/PSGI.

### Features

* Admin controls to create, delete, lock/unlock and modify subdomains as you would expect.

* Simple method of updating and clearing subdomains. Just fire a HTTP POST request at this bad boy and you're all good.

* Should work with any database that Perl's DBI package supports. Only really tested it with SQLite though so you might need to do some extra stuff for MySQL or PostgreSQL.

* Tested with multiple processes and it hasn't segfaulted or broken yet.

* Guaranteed 100% Australian made software. (Guarantee does not apply to Perl libraries)

### Limitations

* Currently unsecure password generation and storage (see the Security secion for more details).

* Only supports one DNS zone. Of course you could probably run multiple copies for each DNS zone or whatever.

* The response codes aren't worked out or documented properly yet.

* Hard coded config options including admin keys. This will be fixed in the future.

* Management of IPv4 and IPv6 could be better. You could probably proxy both an v4 and a v6 address to Wormhole though and just have your users update on both.

* The code is an uncommented mess. I sincerely apologise in advance for any eye or brain trauma that may result from reading the code.

### Requirements

* A server running an operating system, preferably not Windows.

* Perl 5 (obviously)

* Plack (technically not required but it bitches at you if you don't have it)

* DBI and some DBI drivers (sqlite if you're using the default one used)

* uwsgi and the psgi plugin if you use the .ini file

* Regexp::Common

* Net::DNS

### Usage

Simple as. For admins:

    [POST] /create <key> <subdomain>           - Create a subdomain with a random key
    [POST] /modify <key> <subdomain> <ip4/ip6> - Manually assign an address to a subdomain
    [POST] /delete <key> <subdomain>           - Delete a subdomain
    [POST] /lock   <key> <subdomain>           - Lock a subdomain to prevent updates
    [POST] /unlock <key> <subdomain>           - Unlock a subdomain to allow updates
    [POST] /chgkey <key> <subdomain>           - Generate a new random key for a subdomain
    [POST] /list   <key> <subdomain>           - List all subdomains, their ips and last update
    [POST] /help   <key>                       - Display admin help

And for users:

    [POST] /update <key> <subdomain> - Update your subdomain
    [POST] /clear  <key> <subdomain> - Clear your subdomain
    [ GET] /help                     - Display help

### Security

I'll be honest, security is quite shitty here. Keys are not only stored in plaintext, but they are readable by the admin and are generated from an unsecure method (namely Perl's `rand` subroutine). Also there's no rate limiting.

The only thing that's probably secure here is the use of a DNSSEC key for domain stuff. Security will be improved in a later release, with use of salted and SHA-256/512 hashed keys generated from some secure source. It'll probably just read from `/dev/random` or something.

TL;DR - Use at your own risk. Don't be surprised if some Kali Linux wielding skiddy bruteforces it.