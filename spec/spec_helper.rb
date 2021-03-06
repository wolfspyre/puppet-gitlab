require 'rspec-puppet'
require 'rubygems'
require 'puppetlabs_spec_helper/module_spec_helper'
require 'rspec/expectations'
require 'puppetlabs_spec_helper/module_spec_helper'
require 'gitlab_shared'

fixture_path = File.expand_path(File.join(__FILE__, '..', 'fixtures'))

dir = File.expand_path(File.dirname(__FILE__))
$LOAD_PATH.unshift File.join(dir, 'lib')

# Don't want puppet getting the command line arguments for rake or autotest
ARGV.clear

RSpec.configure do |config|
  @gitlab_variables    = "$abc=123"
  config.module_path   = File.join(fixture_path, 'modules')
  config.manifest_dir  = File.join(fixture_path, 'manifests')
  config.color_enabled = true
  config.before :each do
    # Ensure that we don't accidentally cache facts and environment between
    # test cases.  This requires each example group to explicitly load the
    # facts being exercised with something like
    # Facter.collection.loader.load(:ipaddress)
    Facter::Util::Loader.any_instance.stubs(:load_all)
    Facter.clear
    Facter.clear_messages
  end
end
