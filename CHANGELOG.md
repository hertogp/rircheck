# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [unreleased]

- [.] setup flow of api calls, decoding and error handling
- [x] accept either as number or ip address/prefix
- [ ] peer-check: check import/exports are reciprocal
- [ ] uplink: check which routes are visible via which upstream peer
- [ ] roa-check: table of prefixes and their status

---- --------- ------ ------- -------- ------- --------- ---
asn  prefix      bgp?  whois?  roa?    Nroas   roa       max
xyz  a.b.c.d/e   no    yes     valid    4      a.b.x.y/z 24
xyz  a.b.c.d/e   yes   yes     invalid  4      a.b.x.y/z 24
xyz  a.b.c.d/e   yes   no      unknown  4      a.b.x.y/z 24
---- --------- ------ ------- -------- ------- --------- ---
