require 'spec_helper'

describe Slowproxy do
  it 'should have a version number' do
    Slowproxy::VERSION.should_not be_nil
  end

  it 'performs basic math' do
    (1 + 1).should eq(2)
  end
end
