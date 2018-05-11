require 'test_helper'

class Optic::Rails::Test < ActiveSupport::TestCase
  test "truth" do
    assert_kind_of Module, Optic::Rails
  end
end
