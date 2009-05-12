package MyApp;

use strict;
use warnings;

use Catalyst qw/Zero PluginLoader Three/;

__PACKAGE__->config( 
  'Plugin::PluginLoader' => {
    plugins => [qw/+MyApp::Plugin::One Two/]
  }
);

__PACKAGE__->setup;

1;
