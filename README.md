**ssl** is a program that helps you manage SSL certificates on servers that serve
multiple domains using SNI. It works by maintaining a directory of symlinks to
certificates, which includes a certificate for each domain name served by the
server and a default "fallback" certificate for clients that don't support
SNI. **ssl** ensures that each certificate links to the "best" certificate
available that covers the given domain name. It generates self-signed
certificates for each domain name so that there will always be at least one
certificate available.

Other certificates can be added using the other commands provided. **ssl csr**
can be used to generate certificate signing requests which can then be signed
by a legitimate certificate authority. You can pipe the output of **ssl csr** to
**ssl acme** to have your request automatically signed by the free LetsEncrypt
certificate authority (or any other ceritificate authority that uses the ACME
protocol for verification). **ssl import** reads the given certificate (which can
be piped from **ssl acme**) and installs it to the appropriate location and sets
up the appropriate symlinks.

**ssl** has the following usages:

## Initialisation and Status

    # ssl
    # ssl status

This first ensures that the certificates are all set up correctly and valid,
before displaying status information in a table that lists each domain served
by the server and information about the certificates that cover these domains,
such as their certificate authority and their expiration date.

## Generating certificate signing requests

    # ssl csr [--domain DOMAIN]... [--ip IP]... [--zone ZONE]... CN
    # ssl csr all [--no-ips] [--exclude-domain DOMAIN]... \
                  [--exclude-zone ZONE]... [--exclude-ip IP]... [CN]

Before you can import real SSL certificates signed by a legitimate certificate
authority, you'll first need to be able to send a certificate signing request
for your public key. **ssl** can generate these certificate signing requests for
you.

In the first usage above, you specify the common name (CN) of the identity you
want to associate with your public key. This is the primary domain name
associated with your certificate. Additional domains and IP addresses can be
included in the subjectAltName field of your certificate can be specified with
the --domain and --ip options respectively. The --zone option also takes a
domain: this domain should be served by a local DNS server. --zone will query
the local DNS server to get a list of all subdomains of ZONE, before adding
both ZONE and all of its subdomains to the certificate's subjectAltName field.

In the second usage above (**ssl csr all**), the common name (CN) defaults to the
system's hostname (but you can still override this), and all domains (served
by the local DNS server; only **nsd** is supported) and non-local system IP
addresses are included in the certificate by default. The other options can be
used filter this list to exclude certain domains and IP addresses if needed.

## Importing certificates

    # ssl import [--default] [CERTIFICATE]

This will import the specified certificate; if unspecified it will try to read
a certificate from standard input. The --default option specifies that the
certificate being imported should be treated as the default, fallback
certificate for clients that don't support SNI; otherwise it will be treated
as a certificate for one or more individual domains.

If the imported certificate covers any domain served by the server and is
better than the existing options for that domain, the symlink for that domain
will be changed to link to the new certificate. The status table will be
displayed at the end to show the effect of importing the certificate.

## ACME/LetsEncrypt support

    # ssl acme [--staging | --ca SERVER] [CSR]

Given a certificate signing request, given by either the CSR parameter or read
from standard input, **ssl acme** tries to get the free LetsEncrypt certificate
authority to sign it automatically. LetsEncrypt verifies ownership of the
domains in the certificate signing request automatically using the ACME
protocol.

At the moment, **ssl acme** only supports DNS verification. By default, it will
add the required TXT records to the local DNS server (only **nsd** is supported).

If the --staging is given, **ssl acme** will use LetsEncrypt's staging server
instead of its production server. This will produce a certificate signed by a
fake "happy hacker" certificate authority. It's a good idea to do this first,
because if you mess up your certificate signing request a few times, you could
run into rate limits on the production server and have to wait up to a week
before trying again.

Alternatively, you can manually specify a different certificate authority that
uses the ACME protocol with the --ca option.

## Help

    # ssl help

Displays this very help message!