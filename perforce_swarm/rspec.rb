# This file implements the override logic for tests defined under perforce_swarm/spec
# Note: An rspec test is marked as an override in perforce_swarm/spec by adding the 'override: true' tag to it
#       A test in perforce_swarm/spec should be written as an override only if the engine (under perforce_swarm dir.)
#       is overriding a certain behavior defined within the main application ( written outside perforce_swarm dir.)
#       The test in the engine must have same file path and description path as the corresponding main application
#       test, except for the 'override: true' tag on its 'describe/context/it' block

# To run all tests in spec/ and its corresponding overrides in the engine (under perforce_swarm/spec):
# gitlab-shell $ bundle exec rspec -t override -t main_app [-f documentation] spec perforce_swarm/spec

# To run tests in the engine that are not-overrides (new tests defined under engine's perforce_swarm/spec dir.):
# gitlab-shell $ bundle exec rspec -t ~override  [-f documentation] perforce_swarm/spec

require 'rspec'

RSpec.configure do |config|
  # this array will hold strings which represent an overridden test
  # each string is made up of the file path and the test description
  # of a test that is tagged with the override tag
  overrides = []

  # get the description for a test
  # @param [Hash] metadata - metadata from a rspec test
  # @return [String] -  the full description for the test
  # this return string is made up of the descriptions of
  # the nested it, context, and describe blocks for the test
  # each level of description is joined with a slash (/)
  def test_description(metadata)
    if metadata[:example_group].nil? || metadata[:example_group][:description_args].length == 0
      return metadata[:description_args][0].to_s.strip
    end
    (test_description(metadata[:example_group]) + '/' + metadata[:description_args][0].to_s).strip
  end

  # get the filepath of a test
  # @param [Hash] metadata - metadata from a rspec test
  # @return [String] -  the relative filepath for the test
  # relative to the folder which contains the spec folder
  def test_filepath(metadata)
    metadata[:file_path].gsub(%r{^.*/spec}, './spec')
  end

  # string label used to uniquely identify an overridden test
  # @param [Hash] metadata - metadata from a rspec test
  # @return [String] -  the filepath and the description in one string
  # they are joined with comma (,)
  def override_label(metadata)
    test_filepath(metadata) + ',' + test_description(metadata)
  end

  # print a warning to users who are not running any tests from the engine
  unless config.files_to_run.any? { |path| path.include?('perforce_swarm') }
    p 'WARNING: Running the main test without the Swarm overrides.'
    p 'To include the overrides add the perforce_swarm/spec filepath and the main_app and override tags'
    p 'eg: rspec -t override -t main_app spec perforce_swarm/spec'
  end

  # this filter sets up which tests to run
  #
  # it will apply a tag 'main_app' to any test that is not in the engine
  #
  # it will check for the test to be marked as an override
  # if it is an override
  # it will store it's identifier string into the overrides array
  # and return false so that this test is not skipped
  #
  # if it is not tagged as an override it will check the overrides array
  # if the array contains the test's identifier string it will skip the test
  # if the array does not contain it, it will not skip the test
  config.filter_run_excluding example_group: (lambda do |_example_group_meta, metadata|
    metadata[:main_app] = true unless metadata[:file_path].include?('perforce_swarm')
    if metadata.key?(:override) && metadata[:override] == true
      unless overrides.include? override_label(metadata)
        overrides << override_label(metadata)
      end
      return false
    end
    return true if overrides.include? override_label(metadata)
    false
  end)
end
