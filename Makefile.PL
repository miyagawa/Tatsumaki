use inc::Module::Install;
name 'Tatsumaki';
all_from 'lib/Tatsumaki.pm';
readme_from 'lib/Tatsumaki.pm';
requires 'AnyEvent', 7.08;
requires 'AnyEvent::HTTP', 2.21;
requires 'Any::Moose';
requires 'Mouse', 0.34;
requires 'Plack', 0.9913;
requires 'Plack::Request', 1.0033;
requires 'Plack::Response', 1.0033;
requires 'Plack::Middleware::Static';
requires 'Twiggy';
requires 'Twiggy::Server';
requires 'JSON', 2.90;
requires 'JSON::PP', 2.27203;
requires 'JSON::PP::Compat5006', 1.09;
requires 'JSON::XS', 2.34;
requires 'JSON::XS::Boolean';
requires 'Text::MicroTemplate';
requires 'Try::Tiny', 0.22;
requires 'HTTP::Status', 6.03,
requires 'HTTP::Request', 6.00,
requires 'HTTP::Request::Common', 6.04,
requires 'HTTP::Response', 6.04,
requires 'parent';
requires 'Filter::Util::Call';
requires 'Scalar::Util', 1.41;
build_requires 'Test::More';
test_requires 'Test::Requires';
use_test_base;
auto_include_deps;
auto_install;
tests 't/*.t t/*/*.t';
author_tests('xt');
auto_set_repository;
WriteAll;
