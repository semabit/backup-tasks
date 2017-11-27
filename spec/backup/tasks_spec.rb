require "spec_helper"

RSpec.describe Backup::Tasks do
  it "has a version number" do
    expect(Backup::Tasks::VERSION).not_to be nil
  end
end
